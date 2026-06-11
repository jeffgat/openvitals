import Foundation
import UIKit

struct NotificationFrame: Sendable {
  let hex: String
}

struct NotificationIngestResult: Sendable {
  let event: OpenVitalsNotificationEvent
  let frames: [NotificationFrame]
  let bufferedBytes: Int
  let expectedBytes: Int?
  let droppedBytes: Int
  let usedBufferedData: Bool
}

struct FrameReassemblyResult: Sendable {
  let frames: [Data]
  let bufferedBytes: Int
  let expectedBytes: Int?
  let droppedBytes: Int
  let usedBufferedData: Bool
}

final class NotificationFrameReassembler: @unchecked Sendable {
  private let maximumBufferedFrameBytes: Int
  private let stateLock = NSLock()
  private var frameReassemblyBuffers: [String: Data] = [:]

  init(maximumBufferedFrameBytes: Int) {
    self.maximumBufferedFrameBytes = maximumBufferedFrameBytes
  }

  func notificationIngestResult(for event: OpenVitalsNotificationEvent) -> NotificationIngestResult {
    let reassembly = openVitalsFrames(in: event.value, event: event)
    return NotificationIngestResult(
      event: event,
      frames: reassembly.frames.map { NotificationFrame(hex: $0.hexString) },
      bufferedBytes: reassembly.bufferedBytes,
      expectedBytes: reassembly.expectedBytes,
      droppedBytes: reassembly.droppedBytes,
      usedBufferedData: reassembly.usedBufferedData
    )
  }

  private func openVitalsFrames(in data: Data, event: OpenVitalsNotificationEvent) -> FrameReassemblyResult {
    stateLock.lock()
    defer { stateLock.unlock() }

    let key = frameReassemblyKey(for: event)
    let hadBufferedData = frameReassemblyBuffers[key]?.isEmpty == false
    var bytes = Array(frameReassemblyBuffers[key] ?? Data())
    bytes.append(contentsOf: data)
    var frames: [Data] = []
    var droppedBytes = 0
    var expectedBytes: Int?
    let headerLength = event.rustDeviceType == "GEN4" ? 4 : 8

    while let startIndex = bytes.firstIndex(of: 0xaa) {
      if startIndex > 0 {
        droppedBytes += startIndex
        bytes.removeFirst(startIndex)
      }
      guard bytes.count >= headerLength else {
        break
      }

      let declaredLength: Int
      if event.rustDeviceType == "GEN4" {
        declaredLength = Int(bytes[1]) | Int(bytes[2]) << 8
      } else {
        declaredLength = Int(bytes[2]) | Int(bytes[3]) << 8
      }
      guard declaredLength >= 4,
            declaredLength + headerLength <= maximumBufferedFrameBytes else {
        droppedBytes += 1
        bytes.removeFirst()
        continue
      }

      let expectedLength = declaredLength + headerLength
      guard bytes.count >= expectedLength else {
        expectedBytes = expectedLength
        break
      }
      frames.append(Data(bytes[0..<expectedLength]))
      bytes.removeFirst(expectedLength)
    }

    if frames.isEmpty, bytes.count > maximumBufferedFrameBytes {
      droppedBytes += bytes.count
      bytes.removeAll(keepingCapacity: true)
    }

    if bytes.isEmpty {
      frameReassemblyBuffers.removeValue(forKey: key)
    } else {
      frameReassemblyBuffers[key] = Data(bytes)
    }

    return FrameReassemblyResult(
      frames: frames,
      bufferedBytes: bytes.count,
      expectedBytes: expectedBytes,
      droppedBytes: droppedBytes,
      usedBufferedData: hadBufferedData
    )
  }

  private func frameReassemblyKey(for event: OpenVitalsNotificationEvent) -> String {
    "\(event.deviceID.uuidString)|\(event.serviceUUID)|\(event.characteristicUUID)|\(event.rustDeviceType)"
  }
}

struct NotificationFrameParseResult: @unchecked Sendable {
  let parsed: [String: Any]?
  let compact: NotificationFrameCompactSummary?
  let errorDescription: String?
}

struct NotificationFrameBatchTiming: Sendable {
  let totalMicroseconds: Int
  let parseMicroseconds: Int
  let compactSummaryMicroseconds: Int
  let resultSerializationMicroseconds: Int
  let includeResult: Bool
  let okCount: Int
  let errorCount: Int

  init?(raw: [String: Any]) {
    guard let totalMicroseconds = NotificationFrameParser.intValue(raw["total_us"]) else {
      return nil
    }
    self.totalMicroseconds = totalMicroseconds
    parseMicroseconds = NotificationFrameParser.intValue(raw["parse_us"]) ?? 0
    compactSummaryMicroseconds = NotificationFrameParser.intValue(raw["compact_summary_us"]) ?? 0
    resultSerializationMicroseconds = NotificationFrameParser.intValue(raw["result_serialization_us"]) ?? 0
    includeResult = NotificationFrameParser.boolValue(raw["include_result"]) ?? false
    okCount = NotificationFrameParser.intValue(raw["ok_count"]) ?? 0
    errorCount = NotificationFrameParser.intValue(raw["error_count"]) ?? 0
  }

  var statusSummary: String {
    String(
      format: "batch %.1fms parse %.1f compact %.1f serialize %.1f ok %d err %d full=%@",
      Double(totalMicroseconds) / 1_000,
      Double(parseMicroseconds) / 1_000,
      Double(compactSummaryMicroseconds) / 1_000,
      Double(resultSerializationMicroseconds) / 1_000,
      okCount,
      errorCount,
      includeResult ? "yes" : "no"
    )
  }
}

struct NotificationFrameCompactSummary: Sendable {
  struct Movement: Sendable {
    let axisCount: Int
    let parsedSampleCount: Int
    let rawPeakRange: Double
    let rawPeakAbs: Double
    let accelerometerPeakRange: Double
    let gyroscopePeakRange: Double
    let accelerometerVectorRange: Double
    let motionIntensity: Double

    init?(raw: [String: Any]) {
      axisCount = NotificationFrameParser.intValue(raw["axis_count"]) ?? 0
      parsedSampleCount = NotificationFrameParser.intValue(raw["parsed_sample_count"]) ?? 0
      rawPeakRange = NotificationFrameParser.doubleValue(raw["raw_peak_range"]) ?? 0
      rawPeakAbs = NotificationFrameParser.doubleValue(raw["raw_peak_abs"]) ?? 0
      accelerometerPeakRange = NotificationFrameParser.doubleValue(raw["accelerometer_peak_range"]) ?? 0
      gyroscopePeakRange = NotificationFrameParser.doubleValue(raw["gyroscope_peak_range"]) ?? 0
      accelerometerVectorRange = NotificationFrameParser.doubleValue(raw["accelerometer_vector_range"]) ?? 0
      motionIntensity = NotificationFrameParser.doubleValue(raw["motion_intensity"]) ?? 0
      guard parsedSampleCount > 0 else {
        return nil
      }
    }
  }

  let summary: String?
  let packetType: Int?
  let packetTypeName: String?
  let sequence: Int?
  let warningsCount: Int
  let payloadKind: String?
  let packetK: Int?
  let domain: String?
  let counterOrPage: Int?
  let timestampSeconds: Int?
  let timestampSubseconds: Int?
  let bodyHex: String?
  let bodyKind: String?
  let bodyByteCount: Int?
  let heartRateBPM: Int?
  let r17Flags: Int?
  let r17SampleCount: Int?
  let r17ParsedSampleCount: Int?
  let r17Min: Int?
  let r17Max: Int?
  let r17ChannelsOrGain: [Int]
  let dataHex: String?
  let eventID: Int?
  let eventName: String?
  let eventByteCount: Int?
  let movement: Movement?

  init(raw: [String: Any]) {
    summary = raw["summary"] as? String
    packetType = NotificationFrameParser.intValue(raw["packet_type"])
    packetTypeName = raw["packet_type_name"] as? String
    sequence = NotificationFrameParser.intValue(raw["sequence"])
    warningsCount = NotificationFrameParser.intValue(raw["warnings_count"]) ?? 0
    payloadKind = raw["payload_kind"] as? String
    packetK = NotificationFrameParser.intValue(raw["packet_k"])
    domain = raw["domain"] as? String
    counterOrPage = NotificationFrameParser.intValue(raw["counter_or_page"])
    timestampSeconds = NotificationFrameParser.intValue(raw["timestamp_seconds"])
    timestampSubseconds = NotificationFrameParser.intValue(raw["timestamp_subseconds"])
    bodyHex = raw["body_hex"] as? String
    bodyKind = raw["body_kind"] as? String
    bodyByteCount = NotificationFrameParser.intValue(raw["body_byte_count"])
    heartRateBPM = NotificationFrameParser.intValue(raw["heart_rate"])
    r17Flags = NotificationFrameParser.intValue(raw["r17_flags"])
    r17SampleCount = NotificationFrameParser.intValue(raw["r17_sample_count"])
    r17ParsedSampleCount = NotificationFrameParser.intValue(raw["r17_parsed_sample_count"])
    r17Min = NotificationFrameParser.intValue(raw["r17_min"])
    r17Max = NotificationFrameParser.intValue(raw["r17_max"])
    r17ChannelsOrGain = (raw["r17_channels_or_gain"] as? [Any])?.compactMap { NotificationFrameParser.intValue($0) } ?? []
    dataHex = raw["data_hex"] as? String
    eventID = NotificationFrameParser.intValue(raw["event_id"])
    eventName = raw["event_name"] as? String
    eventByteCount = NotificationFrameParser.intValue(raw["event_byte_count"])
    movement = (raw["movement"] as? [String: Any]).flatMap(Movement.init(raw:))
  }
}

struct NotificationFrameInterpretation: @unchecked Sendable {
  let parseErrorDescription: String?
  let summary: String?
  let packetType: Int?
  let healthPacketFamily: HealthPacketCaptureFamily?
  let heartRateBPM: Int?
  let movementSample: MovementPacketSample?
  let whoopEvent: WhoopEventSample?
  let dataSignal: WhoopDataSignalSample?
}

struct ParsedNotificationFrameResult: @unchecked Sendable {
  let interpretation: NotificationFrameInterpretation
  let event: OpenVitalsNotificationEvent
  let bridgeTiming: OpenVitalsRustBridgeTiming?
}

struct ParsedNotificationFrameDispatch: @unchecked Sendable {
  let mainResults: [ParsedNotificationFrameResult]
  let totalFrameCount: Int
  let offMainDataSignalCount: Int
  let skippedDiagnosticFrameCount: Int
  let skippedParseErrorCount: Int
  let bridgeTiming: OpenVitalsRustBridgeTiming?
  let batchTiming: NotificationFrameBatchTiming?
}

struct NotificationParseContext: @unchecked Sendable {
  let deviceType: String
  let healthCaptureActive: Bool
  let overnightGuardActive: Bool
  let respiratoryPacketWatchActive: Bool
  let fallbackHeartRate: Int?
  let ble: OpenVitalsBLEClient
  let packetUIStateAggregator: PacketUIStateAggregator
  let whoopDataSignalPipeline: WhoopDataSignalPipeline
}

enum OvernightRawNotificationStorageClassifier {
  struct Classification {
    let packetType: UInt8?
    let packetK: UInt8?
    let compactKey: String?

    var isCompactLiveFlood: Bool {
      compactKey != nil
    }
  }

  static let compactLiveSamplePolicy = "first_5_then_every_100"
  static let compactLiveSampleWarmupCount = 5
  static let compactLiveSampleInterval = 100
  static let checksumAlgorithm = "sha256(original_value_bytes)"

  private static let compactLivePacketTypes: Set<UInt8> = [40, 43, 51]
  private static let compactLivePacketKs: Set<UInt8> = [2, 10, 11, 20, 21]

  static func classify(_ event: OpenVitalsNotificationEvent) -> Classification {
    let headerBytes = Array(event.value.prefix(10))
    guard headerBytes.count >= 9, headerBytes[0] == 0xaa else {
      return Classification(packetType: nil, packetK: nil, compactKey: nil)
    }

    let packetType = headerBytes[8]
    let packetK = headerBytes.count > 9 ? headerBytes[9] : nil
    guard compactLivePacketTypes.contains(packetType),
          let packetK,
          compactLivePacketKs.contains(packetK) else {
      return Classification(packetType: packetType, packetK: packetK, compactKey: nil)
    }

    let compactKey = [
      event.serviceUUID.lowercased(),
      event.characteristicUUID.lowercased(),
      "packet\(packetType)",
      "k\(packetK)",
    ].joined(separator: ":")
    return Classification(packetType: packetType, packetK: packetK, compactKey: compactKey)
  }

  static func shouldKeepCompactLiveSample(count: Int) -> Bool {
    count <= compactLiveSampleWarmupCount || count.isMultiple(of: compactLiveSampleInterval)
  }
}

final class NotificationFrameParser: @unchecked Sendable {
  private let rust = OpenVitalsRustBridge()

  func parse(frameHex: String, deviceType: String) -> NotificationFrameParseResult {
    do {
      let parsed = try rust.request(
        method: "protocol.parse_frame_hex",
        args: [
          "device_type": deviceType,
          "frame_hex": frameHex,
        ]
      )
      return NotificationFrameParseResult(parsed: parsed, compact: nil, errorDescription: nil)
    } catch {
      return NotificationFrameParseResult(parsed: nil, compact: nil, errorDescription: String(describing: error))
    }
  }

  func parseBatch(
    frameHexes: [String],
    deviceType: String
  ) -> ([NotificationFrameParseResult], OpenVitalsRustBridgeTiming?, NotificationFrameBatchTiming?) {
    guard !frameHexes.isEmpty else {
      return ([], nil, nil)
    }

    do {
      let response = try rust.request(
        method: "protocol.parse_frame_hex_batch",
        args: [
          "device_type": deviceType,
          "frames": frameHexes,
          "include_result": false,
        ]
      )
      let batchTiming = (response["timing"] as? [String: Any]).flatMap(NotificationFrameBatchTiming.init(raw:))
      let rawResults = response["results"] as? [[String: Any]] ?? []
      var parsedResults = Array(
        repeating: NotificationFrameParseResult(parsed: nil, compact: nil, errorDescription: "missing parse result"),
        count: frameHexes.count
      )
      for rawResult in rawResults {
        guard let index = Self.intValue(rawResult["index"]),
              index >= 0,
              index < parsedResults.count else {
          continue
        }
        if Self.boolValue(rawResult["ok"]) == true {
          let compact = (rawResult["compact"] as? [String: Any]).map(NotificationFrameCompactSummary.init(raw:))
          let parsed = rawResult["result"] as? [String: Any]
          parsedResults[index] = NotificationFrameParseResult(parsed: parsed, compact: compact, errorDescription: nil)
        } else {
          let error = rawResult["error"] as? String ?? "unknown parse error"
          parsedResults[index] = NotificationFrameParseResult(parsed: nil, compact: nil, errorDescription: error)
        }
      }
      return (parsedResults, rust.lastTiming, batchTiming)
    } catch {
      let errorDescription = String(describing: error)
      return (
        frameHexes.map { _ in NotificationFrameParseResult(parsed: nil, compact: nil, errorDescription: errorDescription) },
        rust.lastTiming,
        nil
      )
    }
  }

  static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? Double {
      return Int(value)
    }
    if let value = value as? String {
      return Int(value)
    }
    return nil
  }

  static func doubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  static func boolValue(_ value: Any?) -> Bool? {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? Int {
      return value != 0
    }
    if let value = value as? String {
      switch value.lowercased() {
      case "true", "1", "yes":
        return true
      case "false", "0", "no":
        return false
      default:
        return nil
      }
    }
    return nil
  }
}
