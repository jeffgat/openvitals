import Foundation

struct MobileCaptureStreamSession {
  let sessionID: String
  let source: String
  let startedAtUnixMS: Int64
  let deviceModel: String
  let activeDeviceID: String?
  let provenance: [String: String]

  var jsonObject: [String: Any] {
    [
      "session_id": sessionID,
      "source": source,
      "started_at_unix_ms": startedAtUnixMS,
      "device_model": deviceModel,
      "active_device_id": activeDeviceID ?? NSNull(),
      "provenance": provenance,
    ]
  }
}

struct MobileCaptureStreamEnqueueResult: Sendable {
  let acceptedFrameCount: Int
  let droppedFrameCount: Int
  let queuedRowCount: Int
  let maxQueuedRows: Int
}

struct MobileCaptureStreamResult: Sendable {
  let kind: String
  let sentFrameCount: Int
  let importedFrameCount: Int
  let existingFrameCount: Int
  let rawInserted: Int
  let rawExisting: Int
  let queuedRowCount: Int
  let pass: Bool
  let status: String
  let errorDescription: String?
}

private struct MobileCaptureQueuedRows {
  var rows: [CapturedFrameWriteRow]
  let session: MobileCaptureStreamSession
  var retryAttempt: Int
}

private struct MobileCaptureSessionFinish {
  let sessionID: String
  let endedAtUnixMS: Int64
  let frameCount: Int
  var retryAttempt: Int
}

private struct MobileCapturePostResult {
  let result: MobileCaptureStreamResult
  let shouldRetry: Bool
}

final class MobileCaptureStreamQueue: @unchecked Sendable {
  var onResult: ((MobileCaptureStreamResult) -> Void)?

  private let queue = DispatchQueue(label: "com.open_vitals.swift.mobile-capture-stream", qos: .utility)
  private let stateLock = NSLock()
  private let maxQueuedRows: Int
  private let maxBatchRows: Int
  private let coalesceDelay: TimeInterval = 0.25
  private let requestTimeout: TimeInterval = 10
  private let retryBaseDelay: TimeInterval = 2
  private let retryMaxDelay: TimeInterval = 30

  private var enabled = false
  private var endpointURL: URL?
  private var token: String?
  private var pendingBatches: [MobileCaptureQueuedRows] = []
  private var pendingFinishes: [MobileCaptureSessionFinish] = []
  private var queuedRowCount = 0
  private var isSending = false

  init(maxQueuedRows: Int, maxBatchRows: Int) {
    self.maxQueuedRows = max(0, maxQueuedRows)
    self.maxBatchRows = max(1, maxBatchRows)
  }

  func update(enabled: Bool, endpointURL: URL?, token: String?) {
    stateLock.lock()
    self.enabled = enabled && endpointURL != nil
    self.endpointURL = endpointURL
    self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    if !self.enabled {
      pendingBatches.removeAll()
      pendingFinishes.removeAll()
      queuedRowCount = 0
      isSending = false
    }
    stateLock.unlock()
  }

  func cancelPending() {
    stateLock.lock()
    pendingBatches.removeAll()
    pendingFinishes.removeAll()
    queuedRowCount = 0
    isSending = false
    stateLock.unlock()
  }

  func enqueue(
    rows: [CapturedFrameWriteRow],
    session: MobileCaptureStreamSession
  ) -> MobileCaptureStreamEnqueueResult {
    guard !rows.isEmpty else {
      stateLock.lock()
      let currentQueuedRowCount = queuedRowCount
      stateLock.unlock()
      return MobileCaptureStreamEnqueueResult(
        acceptedFrameCount: 0,
        droppedFrameCount: 0,
        queuedRowCount: currentQueuedRowCount,
        maxQueuedRows: maxQueuedRows
      )
    }

    var acceptedFrameCount = 0
    var shouldStartSender = false
    var currentQueuedRowCount = 0

    stateLock.lock()
    defer { stateLock.unlock() }

    guard enabled, endpointURL != nil else {
      return MobileCaptureStreamEnqueueResult(
        acceptedFrameCount: 0,
        droppedFrameCount: 0,
        queuedRowCount: queuedRowCount,
        maxQueuedRows: maxQueuedRows
      )
    }

    let capacity = max(0, maxQueuedRows - queuedRowCount)
    if capacity > 0 {
      let acceptedRows = Array(rows.prefix(capacity))
      acceptedFrameCount = acceptedRows.count
      queuedRowCount += acceptedRows.count
      pendingBatches.append(MobileCaptureQueuedRows(rows: acceptedRows, session: session, retryAttempt: 0))
      if !isSending {
        isSending = true
        shouldStartSender = true
      }
    }
    currentQueuedRowCount = queuedRowCount

    if shouldStartSender {
      queue.asyncAfter(deadline: .now() + coalesceDelay) { [weak self] in
        self?.flushNext()
      }
    }

    return MobileCaptureStreamEnqueueResult(
      acceptedFrameCount: acceptedFrameCount,
      droppedFrameCount: rows.count - acceptedFrameCount,
      queuedRowCount: currentQueuedRowCount,
      maxQueuedRows: maxQueuedRows
    )
  }

  func finish(sessionID: String, endedAtUnixMS: Int64, frameCount: Int) {
    var shouldStartSender = false
    stateLock.lock()
    if enabled, endpointURL != nil {
      pendingFinishes.append(
        MobileCaptureSessionFinish(
          sessionID: sessionID,
          endedAtUnixMS: endedAtUnixMS,
          frameCount: frameCount,
          retryAttempt: 0
        )
      )
      if !isSending {
        isSending = true
        shouldStartSender = true
      }
    }
    stateLock.unlock()

    if shouldStartSender {
      queue.asyncAfter(deadline: .now() + coalesceDelay) { [weak self] in
        self?.flushNext()
      }
    }
  }

  private func flushNext() {
    while true {
      let work = nextWorkItem()
      switch work {
      case .rows(let rows, let session, let endpoint, let token, let queuedAfterPop, let retryAttempt):
        let post = sendRows(rows, session: session, endpoint: endpoint, token: token, queuedAfterPop: queuedAfterPop)
        if scheduleRetryIfNeeded(post, rows: rows, session: session, retryAttempt: retryAttempt) {
          return
        }
        notify(post.result)
      case .finish(let finish, let endpoint, let token, let queuedAfterPop):
        let post = sendFinish(finish, endpoint: finishURL(from: endpoint), token: token, queuedAfterPop: queuedAfterPop)
        if scheduleRetryIfNeeded(post, finish: finish) {
          return
        }
        notify(post.result)
      case .none:
        stateLock.lock()
        isSending = false
        stateLock.unlock()
        return
      }
    }
  }

  private enum WorkItem {
    case rows([CapturedFrameWriteRow], MobileCaptureStreamSession, URL, String?, Int, Int)
    case finish(MobileCaptureSessionFinish, URL, String?, Int)
    case none
  }

  private func nextWorkItem() -> WorkItem {
    stateLock.lock()
    defer { stateLock.unlock() }

    guard enabled, let endpointURL else {
      pendingBatches.removeAll()
      pendingFinishes.removeAll()
      queuedRowCount = 0
      return .none
    }

    if !pendingBatches.isEmpty {
      var batch = pendingBatches.removeFirst()
      let rowCount = min(maxBatchRows, batch.rows.count)
      let rows = Array(batch.rows.prefix(rowCount))
      if rowCount < batch.rows.count {
        batch.rows.removeFirst(rowCount)
        pendingBatches.insert(batch, at: 0)
      }
      queuedRowCount = max(0, queuedRowCount - rows.count)
      return .rows(rows, batch.session, endpointURL, token, queuedRowCount, batch.retryAttempt)
    }

    if !pendingFinishes.isEmpty {
      let finish = pendingFinishes.removeFirst()
      return .finish(finish, endpointURL, token, queuedRowCount)
    }

    return .none
  }

  private func sendRows(
    _ rows: [CapturedFrameWriteRow],
    session: MobileCaptureStreamSession,
    endpoint: URL,
    token: String?,
    queuedAfterPop: Int
  ) -> MobileCapturePostResult {
    let body: [String: Any] = [
      "schema": "open_vitals.mobile-capture-frame-batch.v1",
      "sent_at_unix_ms": unixMilliseconds(Date()),
      "capture_session": session.jsonObject,
      "frames": rows.map(\.bridgeObject),
    ]
    return postJSON(body, endpoint: endpoint, token: token, kind: "frame_batch", sentFrameCount: rows.count, queuedAfterPop: queuedAfterPop)
  }

  private func sendFinish(
    _ finish: MobileCaptureSessionFinish,
    endpoint: URL,
    token: String?,
    queuedAfterPop: Int
  ) -> MobileCapturePostResult {
    let body: [String: Any] = [
      "schema": "open_vitals.mobile-capture-session-finished.v1",
      "session_id": finish.sessionID,
      "ended_at_unix_ms": finish.endedAtUnixMS,
      "frame_count": finish.frameCount,
    ]
    return postJSON(body, endpoint: endpoint, token: token, kind: "finish", sentFrameCount: 0, queuedAfterPop: queuedAfterPop)
  }

  private func postJSON(
    _ body: [String: Any],
    endpoint: URL,
    token: String?,
    kind: String,
    sentFrameCount: Int,
    queuedAfterPop: Int
  ) -> MobileCapturePostResult {
    do {
      var request = URLRequest(url: endpoint)
      request.httpMethod = "POST"
      request.timeoutInterval = requestTimeout
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      if let token {
        request.setValue(token, forHTTPHeaderField: "X-OpenVitals-Ingest-Token")
      }
      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      let response = performRequest(request)
      if let error = response.error {
        throw error
      }
      guard let http = response.response as? HTTPURLResponse else {
        throw MobileCaptureStreamError("Missing HTTP response", retryable: true)
      }
      let payload = response.data.flatMap(Self.jsonObject) ?? [:]
      guard (200..<300).contains(http.statusCode) else {
        let serverError = (payload["error"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        throw MobileCaptureStreamHTTPError(statusCode: http.statusCode, message: serverError)
      }

      return MobileCapturePostResult(result: MobileCaptureStreamResult(
        kind: kind,
        sentFrameCount: sentFrameCount,
        importedFrameCount: Self.intValue(payload["frames_inserted"]) ?? 0,
        existingFrameCount: Self.intValue(payload["frames_existing"]) ?? 0,
        rawInserted: Self.intValue(payload["raw_inserted"]) ?? 0,
        rawExisting: Self.intValue(payload["raw_existing"]) ?? 0,
        queuedRowCount: queuedAfterPop,
        pass: true,
        status: kind == "finish" ? "Mac stream session finished" : "Mac stream sent \(sentFrameCount) frames",
        errorDescription: nil
      ), shouldRetry: false)
    } catch {
      return MobileCapturePostResult(result: MobileCaptureStreamResult(
        kind: kind,
        sentFrameCount: 0,
        importedFrameCount: 0,
        existingFrameCount: 0,
        rawInserted: 0,
        rawExisting: 0,
        queuedRowCount: queuedAfterPop,
        pass: false,
        status: "Mac stream failed",
        errorDescription: Self.errorSummary(error)
      ), shouldRetry: Self.isRetryable(error))
    }
  }

  private func performRequest(_ request: URLRequest) -> (data: Data?, response: URLResponse?, error: Error?) {
    let semaphore = DispatchSemaphore(value: 0)
    var data: Data?
    var response: URLResponse?
    var error: Error?

    let task = URLSession.shared.dataTask(with: request) { responseData, urlResponse, responseError in
      data = responseData
      response = urlResponse
      error = responseError
      semaphore.signal()
    }
    task.resume()

    if semaphore.wait(timeout: .now() + requestTimeout + 2) == .timedOut {
      task.cancel()
      return (nil, nil, MobileCaptureStreamError("Request timed out", retryable: true))
    }
    return (data, response, error)
  }

  private func scheduleRetryIfNeeded(
    _ post: MobileCapturePostResult,
    rows: [CapturedFrameWriteRow],
    session: MobileCaptureStreamSession,
    retryAttempt: Int
  ) -> Bool {
    guard post.shouldRetry else {
      return false
    }
    let nextAttempt = retryAttempt + 1
    let queuedCount = requeue(rows: rows, session: session, retryAttempt: nextAttempt)
    let delay = retryDelay(for: nextAttempt)
    notify(retryResult(from: post.result, queuedRowCount: queuedCount, delay: delay))
    scheduleRetry(after: delay)
    return true
  }

  private func scheduleRetryIfNeeded(
    _ post: MobileCapturePostResult,
    finish: MobileCaptureSessionFinish
  ) -> Bool {
    guard post.shouldRetry else {
      return false
    }
    var retryFinish = finish
    retryFinish.retryAttempt += 1
    let queuedCount = requeue(finish: retryFinish)
    let delay = retryDelay(for: retryFinish.retryAttempt)
    notify(retryResult(from: post.result, queuedRowCount: queuedCount, delay: delay))
    scheduleRetry(after: delay)
    return true
  }

  private func requeue(
    rows: [CapturedFrameWriteRow],
    session: MobileCaptureStreamSession,
    retryAttempt: Int
  ) -> Int {
    stateLock.lock()
    defer { stateLock.unlock() }

    pendingBatches.insert(
      MobileCaptureQueuedRows(rows: rows, session: session, retryAttempt: retryAttempt),
      at: 0
    )
    queuedRowCount += rows.count
    return queuedRowCount
  }

  private func requeue(finish: MobileCaptureSessionFinish) -> Int {
    stateLock.lock()
    defer { stateLock.unlock() }

    pendingFinishes.insert(finish, at: 0)
    return queuedRowCount
  }

  private func retryResult(
    from result: MobileCaptureStreamResult,
    queuedRowCount: Int,
    delay: TimeInterval
  ) -> MobileCaptureStreamResult {
    MobileCaptureStreamResult(
      kind: result.kind,
      sentFrameCount: 0,
      importedFrameCount: 0,
      existingFrameCount: 0,
      rawInserted: 0,
      rawExisting: 0,
      queuedRowCount: queuedRowCount,
      pass: false,
      status: "Mac stream retrying in \(Int(delay))s",
      errorDescription: result.errorDescription
    )
  }

  private func retryDelay(for attempt: Int) -> TimeInterval {
    let cappedAttempt = max(0, min(attempt - 1, 5))
    return min(retryMaxDelay, retryBaseDelay * pow(2, Double(cappedAttempt)))
  }

  private func scheduleRetry(after delay: TimeInterval) {
    queue.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.flushNext()
    }
  }

  private func notify(_ result: MobileCaptureStreamResult) {
    onResult?(result)
  }

  private func finishURL(from endpoint: URL) -> URL {
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      return endpoint
    }
    components.path = "/v1/mobile/capture-session-finished"
    components.query = nil
    components.fragment = nil
    return components.url ?? endpoint
  }

  private func unixMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  private static func jsonObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func intValue(_ value: Any?) -> Int? {
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

  private static func isRetryable(_ error: Error) -> Bool {
    if let error = error as? MobileCaptureStreamError {
      return error.retryable
    }
    if let error = error as? MobileCaptureStreamHTTPError {
      return error.retryable
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorTimedOut,
           NSURLErrorCannotFindHost,
           NSURLErrorCannotConnectToHost,
           NSURLErrorNetworkConnectionLost,
           NSURLErrorNotConnectedToInternet,
           NSURLErrorDNSLookupFailed,
           NSURLErrorInternationalRoamingOff,
           NSURLErrorCallIsActive,
           NSURLErrorDataNotAllowed:
        return true
      default:
        return false
      }
    }

    return false
  }

  private static func errorSummary(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }
    return String(describing: error)
  }
}

private struct MobileCaptureStreamError: Error, CustomStringConvertible {
  let description: String
  let retryable: Bool

  init(_ description: String, retryable: Bool) {
    self.description = description
    self.retryable = retryable
  }
}

private struct MobileCaptureStreamHTTPError: Error, CustomStringConvertible {
  let statusCode: Int
  let message: String

  var retryable: Bool {
    statusCode == 408 || statusCode == 429 || statusCode >= 500
  }

  var description: String {
    "HTTP \(statusCode): \(message)"
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
