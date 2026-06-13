import CryptoKit
import Foundation

struct OpenVitalsSupabaseDebugUploadResult {
  let bundlePath: String
  let manifestPath: String?
  let databaseRowID: String
  let uploadedByteCount: UInt64

  var summary: String {
    "Uploaded \(bundlePath) and metadata row \(databaseRowID)"
  }
}

enum OpenVitalsSupabaseDebugUploadProgress {
  case bundleUploading(String)
  case bundleUploaded(String)
  case manifestUploading(String)
  case manifestUploaded(String)
  case manifestSkipped
  case metadataInserting
  case metadataInserted(String)
}

struct OpenVitalsSupabaseDebugUploader {
  struct Config {
    let projectURL: String
    let anonKey: String
    let bucket: String
    let deviceAlias: String
    let appVersion: String
    let coreVersion: String
  }

  private struct UploadedObject {
    let path: String
    let byteCount: UInt64
    let sha256: String
  }

  private struct RequestResult {
    let data: Data
    let response: HTTPURLResponse
  }

  private static let defaultBucket = "openvitals-debug"
  private static let defaultDeviceAlias = "dev-device"

  func upload(
    bundle result: OpenVitalsLocalDataExportResult,
    config: Config,
    progress: (OpenVitalsSupabaseDebugUploadProgress) -> Void = { _ in }
  ) throws -> OpenVitalsSupabaseDebugUploadResult {
    let projectURL = try Self.normalizedProjectURL(config.projectURL)
    let anonKey = config.anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let bucket = Self.sanitizedPathComponent(config.bucket, fallback: Self.defaultBucket)
    let alias = Self.sanitizedPathComponent(config.deviceAlias, fallback: Self.defaultDeviceAlias)
    guard !anonKey.isEmpty else {
      throw OpenVitalsSupabaseDebugUploadError.notConfigured("Anon key is required")
    }

    let prefix = "\(alias)/\(Self.timestamp())-\(UUID().uuidString.lowercased())"
    let bundlePath = "\(prefix)/\(result.url.lastPathComponent)"
    progress(.bundleUploading(result.url.lastPathComponent))
    let uploadedBundle = try uploadObject(
      fileURL: result.url,
      path: bundlePath,
      projectURL: projectURL,
      bucket: bucket,
      anonKey: anonKey,
      action: "Bundle object upload"
    )
    progress(.bundleUploaded(uploadedBundle.path))

    let uploadedManifest: UploadedObject?
    if let manifestURL = result.manifestURL {
      progress(.manifestUploading(manifestURL.lastPathComponent))
      let manifest = try uploadObject(
        fileURL: manifestURL,
        path: "\(prefix)/\(manifestURL.lastPathComponent)",
        projectURL: projectURL,
        bucket: bucket,
        anonKey: anonKey,
        action: "Manifest object upload"
      )
      uploadedManifest = manifest
      progress(.manifestUploaded(manifest.path))
    } else {
      uploadedManifest = nil
      progress(.manifestSkipped)
    }

    progress(.metadataInserting)
    let rowID = try insertMetadataRow(
      bundle: result,
      uploadedBundle: uploadedBundle,
      uploadedManifest: uploadedManifest,
      projectURL: projectURL,
      bucket: bucket,
      prefix: prefix,
      deviceAlias: alias,
      anonKey: anonKey,
      appVersion: config.appVersion,
      coreVersion: config.coreVersion
    )
    progress(.metadataInserted(rowID))

    return OpenVitalsSupabaseDebugUploadResult(
      bundlePath: uploadedBundle.path,
      manifestPath: uploadedManifest?.path,
      databaseRowID: rowID,
      uploadedByteCount: uploadedBundle.byteCount + (uploadedManifest?.byteCount ?? 0)
    )
  }

  private func uploadObject(
    fileURL: URL,
    path: String,
    projectURL: URL,
    bucket: String,
    anonKey: String,
    action: String
  ) throws -> UploadedObject {
    let digest = try Self.fileDigest(fileURL)
    let url = Self.storageObjectURL(projectURL: projectURL, bucket: bucket, path: path)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("false", forHTTPHeaderField: "x-upsert")

    let response = try Self.performUpload(request: request, fileURL: fileURL)
    try Self.validateHTTPResponse(response, action: action)
    return UploadedObject(path: path, byteCount: digest.byteCount, sha256: digest.sha256)
  }

  private func insertMetadataRow(
    bundle result: OpenVitalsLocalDataExportResult,
    uploadedBundle: UploadedObject,
    uploadedManifest: UploadedObject?,
    projectURL: URL,
    bucket: String,
    prefix: String,
    deviceAlias: String,
    anonKey: String,
    appVersion: String,
    coreVersion: String
  ) throws -> String {
    let row: [String: Any] = [
      "device_alias": deviceAlias,
      "bucket": bucket,
      "storage_prefix": prefix,
      "bundle_path": uploadedBundle.path,
      "manifest_path": uploadedManifest?.path ?? NSNull(),
      "bundle_file_name": result.url.lastPathComponent,
      "bundle_byte_count": Self.int64(uploadedBundle.byteCount),
      "bundle_sha256": uploadedBundle.sha256,
      "manifest_file_name": result.manifestURL?.lastPathComponent ?? NSNull(),
      "manifest_byte_count": uploadedManifest.map { Self.int64($0.byteCount) } ?? NSNull(),
      "manifest_sha256": uploadedManifest?.sha256 ?? NSNull(),
      "validation_summary": result.validation.summary,
      "upload_status": "uploaded",
      "metadata": [
        "schema": "open_vitals.supabase_debug_upload.v1",
        "app_version": appVersion,
        "core_version": coreVersion,
        "time_zone": TimeZone.current.identifier,
        "bundle_file_count": result.fileCount,
        "bundle_source_byte_count": Self.int64(result.byteCount),
        "manifest_error": result.manifestError ?? NSNull(),
        "validation": result.validation.jsonObject,
      ],
    ]
    guard JSONSerialization.isValidJSONObject(row) else {
      throw OpenVitalsSupabaseDebugUploadError.invalidJSON("Supabase metadata row is not valid JSON")
    }

    let data = try JSONSerialization.data(withJSONObject: row, options: [])
    var request = URLRequest(url: Self.restInsertURL(projectURL: projectURL))
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("return=representation", forHTTPHeaderField: "Prefer")

    let response = try Self.performDataRequest(request)
    try Self.validateHTTPResponse(response, action: "Metadata row insert")
    return Self.insertedRowID(from: response.data) ?? "inserted"
  }

  private static func normalizedProjectURL(_ text: String) throws -> URL {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw OpenVitalsSupabaseDebugUploadError.notConfigured("Project URL is required")
    }
    if !trimmed.contains("://") {
      trimmed = "https://\(trimmed)"
    }
    guard var components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          scheme == "https" || scheme == "http",
          components.host != nil else {
      throw OpenVitalsSupabaseDebugUploadError.invalidProjectURL(text)
    }
    components.path = ""
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      throw OpenVitalsSupabaseDebugUploadError.invalidProjectURL(text)
    }
    return url
  }

  private static func storageObjectURL(projectURL: URL, bucket: String, path: String) -> URL {
    var url = projectURL
      .appendingPathComponent("storage")
      .appendingPathComponent("v1")
      .appendingPathComponent("object")
      .appendingPathComponent(bucket)
    for component in path.split(separator: "/") {
      url.appendPathComponent(String(component))
    }
    return url
  }

  private static func restInsertURL(projectURL: URL) -> URL {
    projectURL
      .appendingPathComponent("rest")
      .appendingPathComponent("v1")
      .appendingPathComponent("openvitals_debug_uploads")
  }

  private static func performUpload(request: URLRequest, fileURL: URL) throws -> RequestResult {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<RequestResult, Error>?
    URLSession.shared.uploadTask(with: request, fromFile: fileURL) { data, response, error in
      result = requestResult(data: data, response: response, error: error)
      semaphore.signal()
    }.resume()
    semaphore.wait()
    guard let result else {
      throw OpenVitalsSupabaseDebugUploadError.invalidResponse
    }
    return try result.get()
  }

  private static func performDataRequest(_ request: URLRequest) throws -> RequestResult {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<RequestResult, Error>?
    URLSession.shared.dataTask(with: request) { data, response, error in
      result = requestResult(data: data, response: response, error: error)
      semaphore.signal()
    }.resume()
    semaphore.wait()
    guard let result else {
      throw OpenVitalsSupabaseDebugUploadError.invalidResponse
    }
    return try result.get()
  }

  private static func requestResult(data: Data?, response: URLResponse?, error: Error?) -> Result<RequestResult, Error> {
    if let error {
      return .failure(error)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      return .failure(OpenVitalsSupabaseDebugUploadError.invalidResponse)
    }
    return .success(RequestResult(data: data ?? Data(), response: httpResponse))
  }

  private static func validateHTTPResponse(_ result: RequestResult, action: String) throws {
    guard 200..<300 ~= result.response.statusCode else {
      let body = String(data: result.data, encoding: .utf8) ?? "<non-utf8 response>"
      throw OpenVitalsSupabaseDebugUploadError.requestFailed(
        action: action,
        statusCode: result.response.statusCode,
        body: body
      )
    }
  }

  private static func insertedRowID(from data: Data) -> String? {
    guard !data.isEmpty,
          let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let row = rows.first,
          let id = row["id"] else {
      return nil
    }
    return MoreDataStore.stringValue(id)
  }

  private static func fileDigest(_ url: URL) throws -> (byteCount: UInt64, sha256: String) {
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data)
    let byteCount = UInt64(data.count)
    let sha256 = hash.map { String(format: "%02x", $0) }.joined()
    return (byteCount, sha256)
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }

  private static func sanitizedPathComponent(_ text: String, fallback: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines).map { character -> Character in
      allowed.contains(character) ? character : "_"
    }
    let value = String(sanitized)
      .split(separator: "_", omittingEmptySubsequences: true)
      .joined(separator: "_")
      .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
    return value.isEmpty ? fallback : value
  }

  private static func int64(_ value: UInt64) -> Int64 {
    Int64(min(value, UInt64(Int64.max)))
  }
}

enum OpenVitalsSupabaseDebugUploadError: LocalizedError, CustomStringConvertible {
  case notConfigured(String)
  case invalidProjectURL(String)
  case invalidResponse
  case invalidJSON(String)
  case requestFailed(action: String, statusCode: Int, body: String)

  var errorDescription: String? {
    description
  }

  var description: String {
    switch self {
    case .notConfigured(let message):
      return message
    case .invalidProjectURL(let value):
      return "Invalid Supabase project URL: \(value)"
    case .invalidResponse:
      return "Supabase returned an invalid response"
    case .invalidJSON(let message):
      return message
    case .requestFailed(let action, let statusCode, let body):
      if Self.isPayloadTooLarge(statusCode: statusCode, body: body) {
        return "\(action) failed: object is larger than the Supabase bucket file-size limit"
      }
      if let message = Self.responseMessage(from: body), !message.isEmpty {
        return "\(action) failed with HTTP \(statusCode): \(message)"
      }
      return "\(action) failed with HTTP \(statusCode): \(body)"
    }
  }

  static func isPayloadTooLarge(statusCode: Int, body: String) -> Bool {
    let normalized = body.lowercased()
    return statusCode == 413 || normalized.contains("payload too large") || normalized.contains("\"413\"")
  }

  private static func responseMessage(from body: String) -> String? {
    guard let data = body.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return body.isEmpty ? nil : body
    }
    for key in ["message", "error", "msg"] {
      if let value = object[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }
}

extension MoreDataStore {
  static func supabaseDefaultedValue(_ value: String?, fallback: String) -> String {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  var supabaseUploadIsConfigured: Bool {
    !supabaseProjectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !supabaseBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !supabaseDeviceAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canUploadSupabaseDebugBundle: Bool {
    supabaseUploadBlockedReason == nil
  }

  var supabaseUploadReadinessSummary: String {
    supabaseUploadBlockedReason ?? "Settings saved; upload can be tried now"
  }

  var supabaseUploadReadinessStatus: MoreStatusKind {
    if supabaseUploadInProgress {
      return .inProgress
    }
    return supabaseUploadBlockedReason == nil ? .ready : .blocked
  }

  var supabaseUploadStatusBadgeTitle: String {
    if supabaseUploadInProgress {
      return "Running"
    }
    if !supabaseUploadIsConfigured {
      return "Needs Settings"
    }
    let normalized = supabaseUploadStatus.lowercased()
    if normalized.contains("failed") || normalized.contains("required") {
      return "Failed"
    }
    if normalized.contains("uploaded") {
      return "Uploaded"
    }
    if normalized.contains("ready") {
      return "Idle"
    }
    return "Waiting"
  }

  var supabaseUploadReadinessBadgeTitle: String {
    if supabaseUploadInProgress {
      return "Busy"
    }
    if supabaseUploadBlockedReason == nil {
      return "Settings OK"
    }
    return supabaseUploadIsConfigured ? "Blocked" : "Missing"
  }

  var supabaseUploadActionTitle: String {
    if supabaseUploadInProgress {
      return "Uploading Debug Bundle"
    }
    if !supabaseUploadIsConfigured {
      return "Check Upload Settings"
    }
    return "Create and Upload Debug Bundle"
  }

  var supabaseUploadBlockedReason: String? {
    if supabaseUploadInProgress {
      return "Upload already running"
    }
    if localExportInProgress {
      return "Wait for the local data file to finish saving"
    }
    if rawExportInProgress {
      return "Wait for raw export to finish"
    }
    return supabaseUploadConfigurationIssue()
  }

  var supabaseUploadStatusKind: MoreStatusKind {
    if supabaseUploadInProgress {
      return .inProgress
    }
    if !supabaseUploadIsConfigured {
      return .unavailable
    }
    let normalized = supabaseUploadStatus.lowercased()
    if normalized.contains("failed") || normalized.contains("required") {
      return .blocked
    }
    if normalized.contains("uploaded") || normalized.contains("ready") {
      return .ready
    }
    return .pending
  }

  var supabaseBucketStatus: MoreStatusKind {
    supabaseUploadIsConfigured ? .ready : .unavailable
  }

  var supabaseBucketStatusTitle: String {
    supabaseUploadIsConfigured ? "Configured" : "Missing"
  }

  var supabaseBundleObjectStatus: MoreStatusKind {
    Self.supabaseDebugUploadArtifactStatus(
      supabaseLastBundlePath,
      emptyValues: [Self.supabaseNoBundleUploadText, "No upload"]
    )
  }

  var supabaseBundleObjectStatusTitle: String {
    Self.supabaseDebugUploadArtifactStatusTitle(
      supabaseLastBundlePath,
      status: supabaseBundleObjectStatus,
      readyTitle: "Uploaded",
      notRunTitle: "Not Uploaded"
    )
  }

  var supabaseManifestObjectStatus: MoreStatusKind {
    Self.supabaseDebugUploadArtifactStatus(
      supabaseLastManifestPath,
      emptyValues: [Self.supabaseNoManifestUploadText, "No manifest upload"]
    )
  }

  var supabaseManifestObjectStatusTitle: String {
    Self.supabaseDebugUploadArtifactStatusTitle(
      supabaseLastManifestPath,
      status: supabaseManifestObjectStatus,
      readyTitle: "Uploaded",
      notRunTitle: "Not Uploaded"
    )
  }

  var supabaseDatabaseRowStatus: MoreStatusKind {
    Self.supabaseDebugUploadArtifactStatus(
      supabaseLastDatabaseRow,
      emptyValues: [Self.supabaseNoDatabaseRowText, "No database row"]
    )
  }

  var supabaseDatabaseRowStatusTitle: String {
    Self.supabaseDebugUploadArtifactStatusTitle(
      supabaseLastDatabaseRow,
      status: supabaseDatabaseRowStatus,
      readyTitle: "Inserted",
      notRunTitle: "Not Inserted"
    )
  }

  func saveSupabaseDebugUploadSettings() {
    let projectURL = Self.supabaseDefaultedValue(
      supabaseProjectURL,
      fallback: Self.defaultSupabaseProjectURL
    )
    let anonKey = Self.supabaseDefaultedValue(
      supabaseAnonKey,
      fallback: Self.defaultSupabaseAnonKey
    )
    let bucket = Self.supabaseDefaultedValue(
      supabaseBucket,
      fallback: Self.defaultSupabaseBucket
    )
    let alias = Self.supabaseDefaultedValue(
      supabaseDeviceAlias,
      fallback: Self.defaultSupabaseDeviceAlias
    )

    defaults.set(projectURL, forKey: Self.supabaseProjectURLDefaultsKey)
    defaults.set(anonKey, forKey: Self.supabaseAnonKeyDefaultsKey)
    defaults.set(bucket, forKey: Self.supabaseBucketDefaultsKey)
    defaults.set(alias, forKey: Self.supabaseDeviceAliasDefaultsKey)
    defaults.synchronize()

    supabaseProjectURL = projectURL
    supabaseAnonKey = anonKey
    supabaseBucket = bucket
    supabaseDeviceAlias = alias
    supabaseUploadStatus = supabaseUploadConfigurationIssue() ?? "Ready to upload debug bundle"
  }

  func uploadSupabaseDebugBundle() {
    saveSupabaseDebugUploadSettings()
    if let blockedReason = supabaseUploadBlockedReason {
      supabaseUploadStatus = blockedReason
      return
    }

    supabaseUploadInProgress = true
    supabaseUploadStatus = "Creating debug bundle..."
    supabaseLastBundlePath = "Creating local bundle..."
    supabaseLastManifestPath = "Waiting for local manifest..."
    supabaseLastDatabaseRow = "Waiting for object uploads to finish"
    localExportInProgress = true
    localExportProgress = OpenVitalsLocalDataExportProgress(
      title: "Preparing export",
      detail: "Collecting local files",
      fractionCompleted: nil
    )
    localExportStatus = localExportProgress?.statusText ?? "Preparing export..."
    localExportURL = nil
    localExportManifestURL = nil

    let config = OpenVitalsSupabaseDebugUploader.Config(
      projectURL: supabaseProjectURL,
      anonKey: supabaseAnonKey,
      bucket: supabaseBucket,
      deviceAlias: supabaseDeviceAlias,
      appVersion: Self.appVersion,
      coreVersion: coreVersionStatus
    )

    DispatchQueue.global(qos: .userInitiated).async {
      var bundleCreated = false
      do {
        let bundle = try OpenVitalsLocalDataExporter.createBundle { progress in
          DispatchQueue.main.async {
            self.applyLocalDataExportProgress(progress)
          }
        }
        bundleCreated = true
        DispatchQueue.main.async {
          self.localExportInProgress = false
          self.localExportStatus = "Saved \(bundle.fileCount) files, \(Self.byteCountText(bundle.byteCount))\(bundle.manifestStatusSuffix) | \(bundle.validation.summary)"
          self.localExportProgress = OpenVitalsLocalDataExportProgress(
            title: "Done",
            detail: "Saved \(bundle.fileCount) files, \(Self.byteCountText(bundle.byteCount))",
            fractionCompleted: 1
          )
          self.localExportURL = bundle.url
          self.localExportManifestURL = bundle.manifestURL
          self.supabaseUploadStatus = "Uploading debug bundle objects..."
          self.supabaseLastBundlePath = "Uploading bundle object: \(bundle.url.lastPathComponent)"
          self.supabaseLastManifestPath = bundle.manifestURL.map { "Waiting to upload manifest object: \($0.lastPathComponent)" } ?? "No manifest generated for this bundle"
        }
        let upload = try OpenVitalsSupabaseDebugUploader().upload(bundle: bundle, config: config) { progress in
          DispatchQueue.main.async {
            self.applySupabaseDebugUploadProgress(progress)
          }
        }
        DispatchQueue.main.async {
          self.supabaseUploadInProgress = false
          self.supabaseUploadStatus = "\(upload.summary) | \(Self.byteCountText(upload.uploadedByteCount))"
          self.supabaseLastBundlePath = upload.bundlePath
          self.supabaseLastManifestPath = upload.manifestPath ?? "No manifest generated for this bundle"
          self.supabaseLastDatabaseRow = upload.databaseRowID
        }
      } catch {
        DispatchQueue.main.async {
          let message = Self.supabaseDebugUploadFailureSummary(error)
          if !bundleCreated {
            self.localExportStatus = "Local export failed: \(message)"
            self.localExportProgress = nil
            self.supabaseLastBundlePath = "Not uploaded because local bundle creation failed"
            self.supabaseLastManifestPath = "Not uploaded because local bundle creation failed"
            self.supabaseLastDatabaseRow = "Not inserted because local bundle creation failed"
          } else {
            self.markIncompleteSupabaseDebugUploadStepsFailed(message: message)
          }
          self.localExportInProgress = false
          self.supabaseUploadInProgress = false
          self.supabaseUploadStatus = "Upload failed: \(message)"
        }
      }
    }
  }

  private func supabaseUploadConfigurationIssue() -> String? {
    var missing: [String] = []
    if supabaseProjectURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      missing.append("Project URL")
    }
    if supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      missing.append("Publishable key")
    }
    if supabaseBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      missing.append("Bucket")
    }
    if supabaseDeviceAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      missing.append("Device alias")
    }
    guard !missing.isEmpty else {
      return nil
    }
    return "Settings required: \(missing.joined(separator: ", "))"
  }

  func applySupabaseDebugUploadProgress(_ progress: OpenVitalsSupabaseDebugUploadProgress) {
    switch progress {
    case .bundleUploading(let fileName):
      supabaseUploadStatus = "Uploading bundle object..."
      supabaseLastBundlePath = "Uploading bundle object: \(fileName)"
    case .bundleUploaded(let path):
      supabaseLastBundlePath = path
      supabaseLastDatabaseRow = "Waiting for manifest upload"
    case .manifestUploading(let fileName):
      supabaseUploadStatus = "Uploading manifest object..."
      supabaseLastManifestPath = "Uploading manifest object: \(fileName)"
    case .manifestUploaded(let path):
      supabaseLastManifestPath = path
      supabaseLastDatabaseRow = "Waiting for metadata row insert"
    case .manifestSkipped:
      supabaseLastManifestPath = "No manifest generated for this bundle"
      supabaseLastDatabaseRow = "Waiting for metadata row insert"
    case .metadataInserting:
      supabaseUploadStatus = "Inserting metadata row..."
      supabaseLastDatabaseRow = "Inserting upload metadata row..."
    case .metadataInserted(let rowID):
      supabaseLastDatabaseRow = rowID
    }
  }

  private func markIncompleteSupabaseDebugUploadStepsFailed(message: String) {
    if supabaseBundleObjectStatus != .ready {
      supabaseLastBundlePath = "Bundle object upload failed: \(message)"
    }
    if supabaseManifestObjectStatus != .ready && supabaseManifestObjectStatus != .unavailable {
      supabaseLastManifestPath = "Manifest object upload did not complete because the upload failed"
    }
    if supabaseDatabaseRowStatus != .ready {
      supabaseLastDatabaseRow = "Metadata row was not inserted because the upload failed"
    }
  }

  nonisolated static func supabaseDebugUploadFailureSummary(_ error: Error) -> String {
    if case let OpenVitalsSupabaseDebugUploadError.requestFailed(action, statusCode, body) = error,
       OpenVitalsSupabaseDebugUploadError.isPayloadTooLarge(statusCode: statusCode, body: body) {
      return "\(action) failed because the object is larger than the Supabase bucket file-size limit"
    }
    return errorSummary(error)
  }

  private static func supabaseDebugUploadArtifactStatus(_ value: String, emptyValues: Set<String>) -> MoreStatusKind {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()
    if trimmed.isEmpty || emptyValues.contains(trimmed) {
      return .notRun
    }
    if normalized.contains("failed") || normalized.contains("not inserted because") || normalized.contains("not uploaded because") {
      return .blocked
    }
    if normalized.hasPrefix("uploading") || normalized.hasPrefix("creating") || normalized.hasPrefix("inserting") {
      return .inProgress
    }
    if normalized.hasPrefix("waiting") {
      return .waiting
    }
    if normalized.hasPrefix("no manifest generated") {
      return .unavailable
    }
    return .ready
  }

  private static func supabaseDebugUploadArtifactStatusTitle(
    _ value: String,
    status: MoreStatusKind,
    readyTitle: String,
    notRunTitle: String
  ) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch status {
    case .ready:
      return readyTitle
    case .notRun:
      return notRunTitle
    case .blocked:
      return "Failed"
    case .inProgress:
      if normalized.hasPrefix("creating") {
        return "Creating"
      }
      if normalized.hasPrefix("inserting") {
        return "Inserting"
      }
      return "Uploading"
    case .waiting:
      return "Waiting"
    case .unavailable:
      return "Skipped"
    case .pending:
      return "Pending"
    case .listening:
      return "Listening"
    case .stale:
      return "Stale"
    }
  }
}
