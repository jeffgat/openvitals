import Foundation

enum OpenVitalsRustBridgeError: Error {
  case encodingFailed
  case nullResponse
  case malformedResponse
  case methodFailed(String)
}

struct OpenVitalsRustBridgeTiming: Sendable {
  let method: String
  let methodElapsedMicroseconds: Int
  let requestEncodeMicroseconds: Int
  let ffiRoundTripMicroseconds: Int
  let responseDecodeMicroseconds: Int

  var boundaryMicroseconds: Int {
    requestEncodeMicroseconds + ffiRoundTripMicroseconds + responseDecodeMicroseconds
  }
}

final class OpenVitalsRustBridge {
  private static let utilityQueue = DispatchQueue(label: "com.open_vitals.swift.rust-bridge.utility", qos: .utility)
  private static let userInitiatedQueue = DispatchQueue(label: "com.open_vitals.swift.rust-bridge.user-initiated", qos: .userInitiated)

  private var counter = 0
  private(set) var lastTiming: OpenVitalsRustBridgeTiming?

  static func performInBackground<T>(
    qos: DispatchQoS.QoSClass = .utility,
    _ work: @escaping () throws -> T,
    completion: @escaping (Result<T, Error>) -> Void
  ) {
    queue(for: qos).async {
      let result: Result<T, Error>
      do {
        result = .success(try work())
      } catch {
        result = .failure(error)
      }
      DispatchQueue.main.async {
        completion(result)
      }
    }
  }

  private static func queue(for qos: DispatchQoS.QoSClass) -> DispatchQueue {
    switch qos {
    case .userInteractive, .userInitiated:
      return userInitiatedQueue
    default:
      return utilityQueue
    }
  }

  func request(method: String, args: [String: Any] = [:]) throws -> [String: Any] {
    try requestValue(method: method, args: args) as? [String: Any] ?? [:]
  }

  func requestValue(method: String, args: [String: Any] = [:]) throws -> Any {
    lastTiming = nil
    counter += 1
    let payload: [String: Any] = [
      "schema": "open_vitals.bridge.request.v1",
      "request_id": "open-vitals-\(Date().timeIntervalSince1970)-\(counter)",
      "method": method,
      "args": args,
    ]
    let encodeStarted = DispatchTime.now()
    let data = try JSONSerialization.data(withJSONObject: payload)
    guard let request = String(data: data, encoding: .utf8) else {
      throw OpenVitalsRustBridgeError.encodingFailed
    }
    let requestEncodeMicroseconds = Self.elapsedMicroseconds(since: encodeStarted)

    var responsePointer: UnsafeMutablePointer<CChar>?
    let ffiStarted = DispatchTime.now()
    request.withCString { pointer in
      responsePointer = open_vitals_bridge_handle_json(pointer)
    }
    let ffiRoundTripMicroseconds = Self.elapsedMicroseconds(since: ffiStarted)
    guard let responsePointer else {
      throw OpenVitalsRustBridgeError.nullResponse
    }
    defer {
      open_vitals_bridge_free_string(responsePointer)
    }

    let responseDecodeStarted = DispatchTime.now()
    let responseText = String(cString: responsePointer)
    let responseData = Data(responseText.utf8)
    guard
      let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let ok = response["ok"] as? Bool
    else {
      throw OpenVitalsRustBridgeError.malformedResponse
    }
    let responseDecodeMicroseconds = Self.elapsedMicroseconds(since: responseDecodeStarted)
    lastTiming = Self.timing(
      from: response,
      requestEncodeMicroseconds: requestEncodeMicroseconds,
      ffiRoundTripMicroseconds: ffiRoundTripMicroseconds,
      responseDecodeMicroseconds: responseDecodeMicroseconds
    )
    if !ok {
      let error = response["error"] as? [String: Any]
      let message = error?["message"] as? String ?? "Rust bridge method failed"
      throw OpenVitalsRustBridgeError.methodFailed(message)
    }
    return response["result"] ?? [:]
  }

  private static func timing(
    from response: [String: Any],
    requestEncodeMicroseconds: Int,
    ffiRoundTripMicroseconds: Int,
    responseDecodeMicroseconds: Int
  ) -> OpenVitalsRustBridgeTiming? {
    guard let timing = response["timing"] as? [String: Any],
          let method = timing["method"] as? String else {
      return nil
    }
    if let elapsed = timing["method_elapsed_us"] as? Int {
      return OpenVitalsRustBridgeTiming(
        method: method,
        methodElapsedMicroseconds: elapsed,
        requestEncodeMicroseconds: requestEncodeMicroseconds,
        ffiRoundTripMicroseconds: ffiRoundTripMicroseconds,
        responseDecodeMicroseconds: responseDecodeMicroseconds
      )
    }
    if let elapsed = timing["method_elapsed_us"] as? Double {
      return OpenVitalsRustBridgeTiming(
        method: method,
        methodElapsedMicroseconds: Int(elapsed),
        requestEncodeMicroseconds: requestEncodeMicroseconds,
        ffiRoundTripMicroseconds: ffiRoundTripMicroseconds,
        responseDecodeMicroseconds: responseDecodeMicroseconds
      )
    }
    return nil
  }

  private static func elapsedMicroseconds(since started: DispatchTime) -> Int {
    let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
    let elapsedMicroseconds = elapsedNanoseconds / 1_000
    return Int(min(elapsedMicroseconds, UInt64(Int.max)))
  }
}
