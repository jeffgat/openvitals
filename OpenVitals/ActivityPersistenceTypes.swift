import Foundation
import UIKit

struct ActiveActivityPersistence {
  private static let motionFeatureWindowDuration: TimeInterval = 10

  let activitySessionID: String
  let captureSessionID: String
  let startedAt: Date
  let source: String
  let detectionMethod: String
  let syncStatus: String
  var importedFrameCount: Int
  var lastImportedFrameAt: Date?
  var movementPacketCount = 0
  var meanMotionIntensity = 0.0
  var peakMotionIntensity = 0.0
  var averageHeartRate: Int?
  var maxHeartRate: Int?
  var zoneDurations: [Int: TimeInterval] = [:]

  private var lastMovementSampleAt: Date?
  private var lastHeartRate: Int?
  private var heartRateWeightedTotal = 0.0
  private var heartRateMeasuredSeconds: TimeInterval = 0
  private var motionIntensityTotal = 0.0
  private var motionFeatureBuilder: ActivityMotionFeatureWindowBuilder?
  private var completedMotionFeatureWindows: [ActivityMotionFeatureWindow] = []

  init(
    activitySessionID: String,
    captureSessionID: String,
    startedAt: Date,
    source: String,
    detectionMethod: String,
    syncStatus: String,
    importedFrameCount: Int
  ) {
    self.activitySessionID = activitySessionID
    self.captureSessionID = captureSessionID
    self.startedAt = startedAt
    self.source = source
    self.detectionMethod = detectionMethod
    self.syncStatus = syncStatus
    self.importedFrameCount = importedFrameCount
  }

  mutating func recordImportedFrames(_ count: Int, at date: Date) {
    importedFrameCount += count
    lastImportedFrameAt = lastImportedFrameAt.map { maxDate($0, date) } ?? date
  }

  mutating func ingest(
    _ sample: MovementPacketSample,
    gpsPaceSecondsPerKilometer: TimeInterval?
  ) {
    let previousSampleAt = lastMovementSampleAt ?? startedAt
    let delta = min(max(sample.capturedAt.timeIntervalSince(previousSampleAt), 0), 15)
    lastMovementSampleAt = sample.capturedAt
    movementPacketCount += 1
    motionIntensityTotal += sample.motionIntensity
    meanMotionIntensity = motionIntensityTotal / Double(max(movementPacketCount, 1))
    peakMotionIntensity = max(peakMotionIntensity, sample.motionIntensity)

    if let heartRateBPM = sample.heartRateBPM {
      lastHeartRate = heartRateBPM
      maxHeartRate = max(maxHeartRate ?? heartRateBPM, heartRateBPM)
    }

    recordMotionFeature(sample, gpsPaceSecondsPerKilometer: gpsPaceSecondsPerKilometer)

    guard delta > 0, let heartRateBPM = sample.heartRateBPM ?? lastHeartRate else {
      return
    }

    let zoneID = HeartRateZone.zoneID(for: heartRateBPM)
    zoneDurations[zoneID, default: 0] += delta
    heartRateWeightedTotal += Double(heartRateBPM) * delta
    heartRateMeasuredSeconds += delta
    averageHeartRate = Int((heartRateWeightedTotal / max(heartRateMeasuredSeconds, 1)).rounded())
  }

  func sensorMetricSnapshot(endedAt: Date) -> ActivitySensorMetricSnapshot {
    var finalZoneDurations = zoneDurations
    var finalHeartRateWeightedTotal = heartRateWeightedTotal
    var finalHeartRateMeasuredSeconds = heartRateMeasuredSeconds

    if let lastMovementSampleAt, let lastHeartRate {
      let tail = min(max(endedAt.timeIntervalSince(lastMovementSampleAt), 0), 15)
      if tail > 0 {
        let zoneID = HeartRateZone.zoneID(for: lastHeartRate)
        finalZoneDurations[zoneID, default: 0] += tail
        finalHeartRateWeightedTotal += Double(lastHeartRate) * tail
        finalHeartRateMeasuredSeconds += tail
      }
    }

    let finalAverageHeartRate = finalHeartRateMeasuredSeconds > 0
      ? Int((finalHeartRateWeightedTotal / finalHeartRateMeasuredSeconds).rounded())
      : averageHeartRate

    return ActivitySensorMetricSnapshot(
      averageHeartRate: finalAverageHeartRate,
      maxHeartRate: maxHeartRate,
      zoneDurations: finalZoneDurations,
      movementPacketCount: movementPacketCount,
      meanMotionIntensity: meanMotionIntensity,
      peakMotionIntensity: peakMotionIntensity,
      hasHeartRate: finalHeartRateMeasuredSeconds > 0
    )
  }

  func motionFeatureWindows(endedAt: Date) -> [ActivityMotionFeatureWindow] {
    var windows = completedMotionFeatureWindows
    if let window = motionFeatureBuilder?.finalized(endedAt: endedAt) {
      windows.append(window)
    }
    return windows
  }

  private mutating func recordMotionFeature(
    _ sample: MovementPacketSample,
    gpsPaceSecondsPerKilometer: TimeInterval?
  ) {
    let sampleAt = sample.capturedAt < startedAt ? startedAt : sample.capturedAt
    let sequence = max(
      0,
      Int(sampleAt.timeIntervalSince(startedAt) / Self.motionFeatureWindowDuration)
    )

    if let builder = motionFeatureBuilder, sequence > builder.sequence {
      if let window = builder.finalized(endedAt: builder.endAt) {
        completedMotionFeatureWindows.append(window)
      }
      motionFeatureBuilder = makeMotionFeatureBuilder(sequence: sequence)
    } else if motionFeatureBuilder == nil {
      motionFeatureBuilder = makeMotionFeatureBuilder(sequence: sequence)
    }

    motionFeatureBuilder?.ingest(
      sample,
      gpsPaceSecondsPerKilometer: gpsPaceSecondsPerKilometer
    )
  }

  private func makeMotionFeatureBuilder(sequence: Int) -> ActivityMotionFeatureWindowBuilder {
    let startAt = startedAt.addingTimeInterval(
      TimeInterval(sequence) * Self.motionFeatureWindowDuration
    )
    return ActivityMotionFeatureWindowBuilder(
      sequence: sequence,
      startAt: startAt,
      endAt: startAt.addingTimeInterval(Self.motionFeatureWindowDuration)
    )
  }
}

struct ActivitySensorMetricSnapshot {
  let averageHeartRate: Int?
  let maxHeartRate: Int?
  let zoneDurations: [Int: TimeInterval]
  let movementPacketCount: Int
  let meanMotionIntensity: Double
  let peakMotionIntensity: Double
  let hasHeartRate: Bool
}

struct ActivityMotionFeatureWindow {
  let sequence: Int
  let startAt: Date
  let endAt: Date
  let movementPacketCount: Int
  let sourceFrameIDs: [String]
  let sourceEvidenceIDs: [String]
  let meanMotionIntensity: Double
  let peakMotionIntensity: Double
  let meanAccelerometerVectorIntensity: Double?
  let peakAccelerometerPeakRange: Double?
  let meanGyroscopePeakRange: Double?
  let peakGyroscopePeakRange: Double?
  let stillnessRatio: Double
  let averageHeartRateBPM: Double?
  let maxHeartRateBPM: Double?
  let heartRateSampleCount: Int
  let dominantHeartRateZone: Int?
  let gpsPaceSecondsPerKilometer: Double?
  let gpsSpeedMetersPerSecond: Double?
  let cadenceSPMCandidate: Double?
  let qualityFlags: [String]

  func bridgeObject(
    activitySessionID: String,
    captureSessionID: String?,
    source: String
  ) -> [String: Any] {
    let captureSessionValue: Any = captureSessionID ?? NSNull()
    return [
      "feature_id": "\(activitySessionID).motion.window.\(sequence)",
      "activity_session_id": activitySessionID,
      "capture_session_id": captureSessionValue,
      "start_time_unix_ms": Self.unixMilliseconds(startAt),
      "end_time_unix_ms": Self.unixMilliseconds(endAt),
      "sequence": sequence,
      "movement_packet_count": movementPacketCount,
      "source_frame_ids": sourceFrameIDs,
      "source_evidence_ids": sourceEvidenceIDs,
      "mean_motion_intensity": meanMotionIntensity,
      "peak_motion_intensity": peakMotionIntensity,
      "mean_accelerometer_vector_intensity": meanAccelerometerVectorIntensity ?? NSNull(),
      "peak_accelerometer_peak_range": peakAccelerometerPeakRange ?? NSNull(),
      "mean_gyroscope_peak_range": meanGyroscopePeakRange ?? NSNull(),
      "peak_gyroscope_peak_range": peakGyroscopePeakRange ?? NSNull(),
      "stillness_ratio": stillnessRatio,
      "average_heart_rate_bpm": averageHeartRateBPM ?? NSNull(),
      "max_heart_rate_bpm": maxHeartRateBPM ?? NSNull(),
      "heart_rate_sample_count": heartRateSampleCount,
      "dominant_hr_zone": dominantHeartRateZone ?? NSNull(),
      "gps_pace_seconds_per_km": gpsPaceSecondsPerKilometer ?? NSNull(),
      "gps_speed_mps": gpsSpeedMetersPerSecond ?? NSNull(),
      "cadence_spm_candidate": cadenceSPMCandidate ?? NSNull(),
      "quality_flags": qualityFlags,
      "provenance": [
        "source": source,
        "capture_session_id": captureSessionValue,
        "window_seconds": endAt.timeIntervalSince(startAt),
        "feature_kind": "activity_motion_window",
      ],
    ]
  }

  private static func unixMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}

private struct ActivityMotionFeatureWindowBuilder {
  let sequence: Int
  let startAt: Date
  let endAt: Date

  private var movementPacketCount = 0
  private var movingPacketCount = 0
  private var motionIntensityTotal = 0.0
  private var peakMotionIntensity = 0.0
  private var accelerometerVectorIntensityTotal = 0.0
  private var peakAccelerometerPeakRange = 0.0
  private var gyroscopePeakRangeTotal = 0.0
  private var peakGyroscopePeakRange = 0.0
  private var heartRateSampleCount = 0
  private var heartRateTotal = 0.0
  private var maxHeartRateBPM: Int?
  private var heartRateZoneCounts: [Int: Int] = [:]
  private var gpsPaceSampleCount = 0
  private var gpsPaceTotal = 0.0
  private var gpsSpeedTotal = 0.0
  private var sourceFrameIDs: [String] = []
  private var sourceEvidenceIDs: [String] = []

  init(sequence: Int, startAt: Date, endAt: Date) {
    self.sequence = sequence
    self.startAt = startAt
    self.endAt = endAt
  }

  mutating func ingest(
    _ sample: MovementPacketSample,
    gpsPaceSecondsPerKilometer: TimeInterval?
  ) {
    movementPacketCount += 1
    if sample.isMoving {
      movingPacketCount += 1
    }
    motionIntensityTotal += sample.motionIntensity
    peakMotionIntensity = max(peakMotionIntensity, sample.motionIntensity)

    let accelerometerIntensity = min(1, max(0, sample.accelerometerVectorRange / 8192.0))
    accelerometerVectorIntensityTotal += accelerometerIntensity
    peakAccelerometerPeakRange = max(peakAccelerometerPeakRange, sample.accelerometerPeakRange)
    gyroscopePeakRangeTotal += sample.gyroscopePeakRange
    peakGyroscopePeakRange = max(peakGyroscopePeakRange, sample.gyroscopePeakRange)

    if let heartRateBPM = sample.heartRateBPM {
      heartRateSampleCount += 1
      heartRateTotal += Double(heartRateBPM)
      maxHeartRateBPM = max(maxHeartRateBPM ?? heartRateBPM, heartRateBPM)
      let zoneID = HeartRateZone.zoneID(for: heartRateBPM)
      heartRateZoneCounts[zoneID, default: 0] += 1
    }

    if let pace = gpsPaceSecondsPerKilometer, pace > 0 {
      gpsPaceSampleCount += 1
      gpsPaceTotal += pace
      gpsSpeedTotal += 1000 / pace
    }

    if let sourceFrameID = sample.sourceFrameID,
       !sourceFrameIDs.contains(sourceFrameID) {
      sourceFrameIDs.append(sourceFrameID)
    }
    if let sourceEvidenceID = sample.sourceEvidenceID,
       !sourceEvidenceIDs.contains(sourceEvidenceID) {
      sourceEvidenceIDs.append(sourceEvidenceID)
    }
  }

  func finalized(endedAt requestedEndAt: Date) -> ActivityMotionFeatureWindow? {
    guard movementPacketCount > 0 else {
      return nil
    }

    let boundedEndAt = min(max(requestedEndAt, startAt.addingTimeInterval(1)), endAt)
    let heartRateAverage = heartRateSampleCount > 0
      ? heartRateTotal / Double(heartRateSampleCount)
      : nil
    let dominantZone = heartRateZoneCounts.max { lhs, rhs in
      if lhs.value == rhs.value {
        return lhs.key < rhs.key
      }
      return lhs.value < rhs.value
    }?.key
    var qualityFlags: [String] = ["cadence_unavailable"]
    if sourceFrameIDs.isEmpty {
      qualityFlags.append("source_frame_id_unavailable")
    }
    if heartRateSampleCount == 0 {
      qualityFlags.append("heart_rate_unavailable")
    }
    if gpsPaceSampleCount == 0 {
      qualityFlags.append("gps_pace_unavailable")
    }
    if movementPacketCount < 2 {
      qualityFlags.append("low_motion_packet_count")
    }
    if boundedEndAt < endAt {
      qualityFlags.append("partial_window")
    }

    return ActivityMotionFeatureWindow(
      sequence: sequence,
      startAt: startAt,
      endAt: boundedEndAt,
      movementPacketCount: movementPacketCount,
      sourceFrameIDs: sourceFrameIDs,
      sourceEvidenceIDs: sourceEvidenceIDs,
      meanMotionIntensity: motionIntensityTotal / Double(movementPacketCount),
      peakMotionIntensity: peakMotionIntensity,
      meanAccelerometerVectorIntensity: accelerometerVectorIntensityTotal / Double(movementPacketCount),
      peakAccelerometerPeakRange: peakAccelerometerPeakRange,
      meanGyroscopePeakRange: gyroscopePeakRangeTotal / Double(movementPacketCount),
      peakGyroscopePeakRange: peakGyroscopePeakRange,
      stillnessRatio: Double(movementPacketCount - movingPacketCount) / Double(movementPacketCount),
      averageHeartRateBPM: heartRateAverage,
      maxHeartRateBPM: maxHeartRateBPM.map(Double.init),
      heartRateSampleCount: heartRateSampleCount,
      dominantHeartRateZone: dominantZone,
      gpsPaceSecondsPerKilometer: gpsPaceSampleCount > 0
        ? gpsPaceTotal / Double(gpsPaceSampleCount)
        : nil,
      gpsSpeedMetersPerSecond: gpsPaceSampleCount > 0
        ? gpsSpeedTotal / Double(gpsPaceSampleCount)
        : nil,
      cadenceSPMCandidate: nil,
      qualityFlags: qualityFlags
    )
  }
}

struct ActivityTimelineRefreshResult {
  let items: [ActivityTimelineItem]
  let status: String
}

struct ActivityTimelineItem: Identifiable, Equatable {
  let id: String
  let startedAt: Date
  let title: String
  let activityType: String
  let syncStatus: String
  let durationSeconds: TimeInterval
  let distanceMeters: Double?
  let averageHeartRate: Int?
}
