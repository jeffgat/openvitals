import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class MoreDataStore: ObservableObject {
  @Published var databasePath: String
  @Published var storageStatus = "Not checked"
  @Published var storageNextAction = "Run Check after OpenVitals has created the local database"
  @Published var schemaVersion = "Unknown"

  @Published var captureSessionID: String?
  @Published var captureSessionStartedAt: Date?
  @Published var captureFrameCount = 0
  @Published var captureStatus = "No capture session"
  @Published var liveCaptureStatus = "Connect a device to mirror notifications into capture"
  @Published var captureImportStatus = "Waiting for a document picker bridge"
  @Published var commandEvidenceStatus = "Waiting for a command evidence file"
  @Published var emulatorLogStatus = "Waiting for an emulator log"
  @Published var localFrameMatchStatus = "Waiting for imported frames"
  @Published var validatedCommandStatus = "Waiting for command validation samples"
  @Published var recentCaptureSessions: [String] = []

  @Published var healthBackfillStart: String
  @Published var healthBackfillEnd: String
  @Published var selectedHealthFamilies: Set<String> = []
  @Published var healthAdapterStatus = "Not refreshed"
  @Published var healthAuthorizationStatus = "Not requested in More"
  @Published var existingOpenVitalsRecordsStatus = "No local database checked"
  @Published var importedSleepHistoryStatus = "No imported sleep history loaded"
  @Published var healthSyncReports: [String] = ["No dry run yet"]

  @Published var rawExportStart: String
  @Published var rawExportEnd: String
  @Published var rawCaptureSessions = ""
  @Published var rawPacketTypes = ""
  @Published var rawSensorSignals = ""
  @Published var rawMetricFamilies = "heart_rate,hrv,activity"
  @Published var rawAlgorithmIDs = ""
  @Published var rawAlgorithmVersions = ""
  @Published var includeRawBytes = true
  @Published var selectedRawFamilies: Set<String> = ["raw_evidence", "decoded_frames", "packet_timeline", "sensor_samples", "metric_features", "metric_outputs", "algorithm_runs", "local_health_metrics", "sqlite"]
  @Published var rawExportStatus = "No export yet"
  @Published var rawExportInProgress = false
  @Published var rawBundlePath = "No bundle"
  @Published var rawZipPath = "No zip"
  @Published var rawZipURL: URL?
  @Published var rawRowCounts = "No rows"
  @Published var rawValidationManifestStatus = "No validation manifest"
  @Published var rawValidationManifestURL: URL?
  @Published var rawValidationReviewStatus = "No validation review"
  @Published var rawValidationReviewURL: URL?
  @Published var rawValidationRunbookStatus = "No validation runbook"
  @Published var rawValidationRunbookURL: URL?
  @Published var rawBundleValidation = "Not validated"
  @Published var rawZipValidation = "Not validated"
  @Published var privacyLintStatus = "Not linted"
  @Published var sanitizedPrivacyStatus = "No sanitized copy"
  @Published var streamProbeStart: String
  @Published var streamProbeEnd: String
  @Published var streamProbeBaselineStart = ""
  @Published var streamProbeBaselineEnd = ""
  @Published var streamProbeCaptureSessions = ""
  @Published var streamProbePlanStatus = "No stream probe plan"
  @Published var streamProbePlanInProgress = false
  @Published var streamProbeDeltaStatus = "No packet delta analysis"
  @Published var streamProbeDeltaInProgress = false
  @Published var streamProbeExpectedPacketFamilies: [String] = []
  @Published var streamProbeSteps: [MoreStreamProbeStep] = []
  @Published var streamProbePacketDeltas: [MoreStreamProbePacketDelta] = []
  @Published var streamProbeNextActions: [String] = []
  @Published var k20ChannelScanStatus = "No K20 channel scan"
  @Published var k20ChannelScanInProgress = false
  @Published var k20ChannelCandidates: [MoreK20ChannelCandidate] = []
  @Published var k20ChannelNextActions: [String] = []
  @Published var k20WaveformScanStatus = "No K20 waveform transform scan"
  @Published var k20WaveformScanInProgress = false
  @Published var k20WaveformCandidates: [MoreK20WaveformCandidate] = []
  @Published var k20WaveformNextActions: [String] = []
  @Published var beatEvidenceStatus = "No beat evidence report"
  @Published var beatEvidenceInProgress = false
  @Published var beatEvidenceNextActions: [String] = []
  @Published var guidedReferenceProbeStatus = "No guided reference probe run"
  @Published var guidedReferenceProbeInProgress = false
  @Published var automaticStreamProbeStatus = "No automatic stream probe run"
  @Published var automaticStreamProbeInProgress = false
  @Published var automaticStreamProbeStartedAt: Date?
  @Published var localExportStatus = "No local export"
  @Published var localExportInProgress = false
  @Published var localExportProgress: OpenVitalsLocalDataExportProgress?
  @Published var localExportURL: URL?
  @Published var localExportManifestURL: URL?
  @Published var k18ExportReadinessStatus = "K18 export readiness not checked"
  @Published var k18ExportReadinessInProgress = false
  @Published var k18ExportReadinessNextActions: [String] = []
  @Published var debugDataClearStatus = "Debug data not cleared"
  @Published var debugDataClearInProgress = false
  @Published var supabaseProjectURL: String
  @Published var supabaseAnonKey: String
  @Published var supabaseBucket: String
  @Published var supabaseDeviceAlias: String
  @Published var supabaseUploadStatus = "Not configured"
  @Published var supabaseUploadInProgress = false
  @Published var supabaseLastBundlePath = MoreDataStore.supabaseNoBundleUploadText
  @Published var supabaseLastManifestPath = MoreDataStore.supabaseNoManifestUploadText
  @Published var supabaseLastDatabaseRow = MoreDataStore.supabaseNoDatabaseRowText

  @Published var algorithmPreferenceStatus = "Local selection only"

  @Published var coreVersionStatus = "Rust bridge not checked"
  @Published var frameParseStatus = "No parser probe run"
  @Published var frameCRCStatus = "CRC pending"
  @Published var framePayloadStatus = "Payload pending"
  @Published var frameWarningsStatus = "Warnings pending"
  @Published var frameTimelineStatus = "Timeline pending"
  @Published var debugWebSocketStatus = "Not started"
  @Published var debugNextAction = "Start a local debug session"
  @Published var uiCoverageStatus = "No audit run"
  @Published var deferredSurfaceStatus = "Deferred surfaces unknown"
  @Published var propertySuiteStatus = "No property suite run"
  @Published var perfBudgetStatus = "No perf budget run"
  @Published var commandEvidenceImportStatus = "No command evidence imported"
  @Published var commandGateSweepStatus = "No gate sweep run"
  @Published var commandCapturePlanStatus = "No capture plan generated"
  @Published var commandGroups: [MoreCommandGroup] = MoreCommandGroup.defaults
  @Published var destructiveGateStatus = "Locked"

  @Published var supportBundlePath: String
  @Published var logExportStatus = "Logs remain in the app event stream"
  @Published var deletionStatus = "No local data wipe run"

  let bridge = OpenVitalsRustBridge()
  let outputDirectory: String
  let defaults = UserDefaults.standard
  static let supabaseProjectURLDefaultsKey = "open_vitals.debug_upload.supabase_project_url"
  static let supabaseAnonKeyDefaultsKey = "open_vitals.debug_upload.supabase_anon_key"
  static let supabaseBucketDefaultsKey = "open_vitals.debug_upload.supabase_bucket"
  static let supabaseDeviceAliasDefaultsKey = "open_vitals.debug_upload.device_alias"
  static let defaultSupabaseProjectURL = "https://gpvltilwupglfaiosdcq.supabase.co"
  static let defaultSupabaseAnonKey = "sb_publishable_MxhFj8kE4GVqERetpPU2tA_G3wOYtFY"
  static let defaultSupabaseBucket = "openvitals-debug"
  static let defaultSupabaseDeviceAlias = "dev-device"
  static let supabaseNoBundleUploadText = "Not uploaded yet"
  static let supabaseNoManifestUploadText = "Not uploaded yet"
  static let supabaseNoDatabaseRowText = "Not inserted yet"

  struct RawExportArtifactValidationResult {
    let bundleValidation: String
    let zipValidation: String
    let privacyLint: String
    let sanitizedPrivacy: String
  }

  struct RawValidationSidecarResult {
    let manifestStatus: String
    let manifestURL: URL?
    let reviewStatus: String
    let reviewURL: URL?
    let runbookStatus: String
    let runbookURL: URL?
  }
  var debugSessionID = "swift-more-\(UUID().uuidString)"
  var automaticStreamProbeStopWorkItem: DispatchWorkItem?
  var automaticStreamProbeCatchUpWorkItem: DispatchWorkItem?
  var guidedReferenceProbeWorkItem: DispatchWorkItem?
  lazy var rrReferenceCapture = OpenVitalsRRReferenceCapture(databasePath: databasePath)

  init(databasePath: String? = nil) {
    let appDirectory = MoreDataStore.applicationDirectory()
    let documentsDirectory = MoreDataStore.documentsApplicationDirectory()
    self.databasePath = databasePath ?? appDirectory.appendingPathComponent("open_vitals.sqlite").path
    outputDirectory = documentsDirectory.appendingPathComponent("Exports", isDirectory: true).path
    supportBundlePath = documentsDirectory.appendingPathComponent("Support", isDirectory: true).path
    supabaseProjectURL = Self.supabaseDefaultedValue(
      UserDefaults.standard.string(forKey: Self.supabaseProjectURLDefaultsKey),
      fallback: Self.defaultSupabaseProjectURL
    )
    supabaseAnonKey = Self.supabaseDefaultedValue(
      UserDefaults.standard.string(forKey: Self.supabaseAnonKeyDefaultsKey),
      fallback: Self.defaultSupabaseAnonKey
    )
    supabaseBucket = Self.supabaseDefaultedValue(
      UserDefaults.standard.string(forKey: Self.supabaseBucketDefaultsKey),
      fallback: Self.defaultSupabaseBucket
    )
    supabaseDeviceAlias = Self.supabaseDefaultedValue(
      UserDefaults.standard.string(forKey: Self.supabaseDeviceAliasDefaultsKey),
      fallback: Self.defaultSupabaseDeviceAlias
    )

    let now = Date()
    let start = Self.fullExportStart
    let end = now.moreISO8601String()
    healthBackfillStart = start
    healthBackfillEnd = end
    rawExportStart = start
    rawExportEnd = end
    streamProbeStart = start
    streamProbeEnd = end
    if supabaseUploadIsConfigured {
      supabaseUploadStatus = "Ready to upload debug bundle"
    }
  }

  func routeStatus(ble: OpenVitalsBLEClient, model: OpenVitalsAppModel) -> MoreRouteStatus {
    MoreRouteStatus(
      profile: OnboardingProfileSnapshot().hasRequiredDetails ? .ready : .pending,
      device: ble.connectionState == "ready" ? .ready : .pending,
      connectionLab: model.helloSummary.hasPrefix("GET_HELLO") ? .ready : .pending,
      capture: captureSessionID == nil ? .notRun : .listening,
      localStore: databaseExists ? .ready : .unavailable,
      healthSync: healthSyncBackfillWindowIssueSummary() == nil ? .pending : .blocked,
      rawExport: rawExportRouteStatus,
      streamProbePlan: streamProbeRouteStatus,
      algorithms: .ready,
      debug: coreVersionStatus.hasPrefix("Rust core") ? .ready : .pending,
      appearance: .ready,
      privacy: privacyLintStatus == "Not linted" ? .pending : .ready,
      support: .pending,
      about: .ready,
      developer: .ready
    )
  }

  private var rawExportRouteStatus: MoreStatusKind {
    if rawExportWindowIssueSummary() != nil {
      return .blocked
    }
    guard databaseExists else {
      return .unavailable
    }
    if rawExportInProgress || localExportInProgress || supabaseUploadInProgress {
      return .inProgress
    }
    return rawBundlePath == "No bundle" ? .notRun : .ready
  }

  private var streamProbeRouteStatus: MoreStatusKind {
    if guidedReferenceProbeInProgress || automaticStreamProbeInProgress || streamProbePlanInProgress || streamProbeDeltaInProgress || k20ChannelScanInProgress || k20WaveformScanInProgress || beatEvidenceInProgress || k18ExportReadinessInProgress || debugDataClearInProgress {
      return .inProgress
    }
    if streamProbePlanStatus.localizedCaseInsensitiveContains("blocked")
      || streamProbeDeltaStatus.localizedCaseInsensitiveContains("blocked")
      || k20ChannelScanStatus.localizedCaseInsensitiveContains("blocked")
      || k20WaveformScanStatus.localizedCaseInsensitiveContains("blocked")
      || beatEvidenceStatus.localizedCaseInsensitiveContains("blocked")
      || k18ExportReadinessStatus.localizedCaseInsensitiveContains("blocked")
      || debugDataClearStatus.localizedCaseInsensitiveContains("blocked")
      || streamProbePlanStatus.localizedCaseInsensitiveContains("failed")
      || streamProbeDeltaStatus.localizedCaseInsensitiveContains("failed")
      || k20ChannelScanStatus.localizedCaseInsensitiveContains("failed")
      || k20WaveformScanStatus.localizedCaseInsensitiveContains("failed")
      || beatEvidenceStatus.localizedCaseInsensitiveContains("failed")
      || k18ExportReadinessStatus.localizedCaseInsensitiveContains("failed")
      || debugDataClearStatus.localizedCaseInsensitiveContains("failed")
    {
      return .blocked
    }
    if !streamProbePacketDeltas.isEmpty || !k20ChannelCandidates.isEmpty || !k20WaveformCandidates.isEmpty || !beatEvidenceNextActions.isEmpty || k18ExportReadinessStatus.localizedCaseInsensitiveContains("ready to export") {
      return .ready
    }
    return streamProbeSteps.isEmpty ? .notRun : .pending
  }

  func refreshBridgeStatus(model: OpenVitalsAppModel) {
    coreVersionStatus = model.rustStatus
    guard schemaVersion == "Unknown" || coreVersionStatus == "Rust bridge not checked" else {
      return
    }
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(method: "core.version")
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
        let version = value["core_version"] as? String ?? "unknown"
        let schema = value["storage_schema_version"].map(Self.stringValue) ?? "unknown"
        coreVersionStatus = "Rust core \(version)"
        schemaVersion = schema
      case .failure:
        coreVersionStatus = "Rust bridge unavailable"
      }
    }
  }

  func refreshHealthAdapter() {
#if canImport(HealthKit)
    healthAdapterStatus = HKHealthStore.isHealthDataAvailable() ? "Apple Health profile autofill available" : "Apple Health unavailable on this device"
#else
    healthAdapterStatus = "HealthKit framework unavailable"
#endif
    healthAuthorizationStatus = "Reads body mass only for profile autofill"
  }

  func refreshRecentCaptureSessions() {
    let nowMs = Self.unixMilliseconds(Date())
    let thirtyDaysMs: Int64 = 30 * 24 * 60 * 60 * 1_000
    let databasePath = databasePath
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "capture.list_sessions",
        args: [
          "database_path": databasePath,
          "start_unix_ms": nowMs - thirtyDaysMs,
          "end_unix_ms": nowMs,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
        recentCaptureSessions = Self.captureSessionSummaries(from: value)
      case .failure:
      if recentCaptureSessions.isEmpty {
        recentCaptureSessions = ["No stored capture sessions"]
      }
      }
    }
  }

  func captureSessionSummary() -> String {
    if let captureSessionID, let captureSessionStartedAt {
      return "Active \(captureSessionID.prefix(8)) since \(captureSessionStartedAt.formatted(date: .omitted, time: .shortened)); \(captureFrameCount) frames"
    }
    return captureStatus
  }

  func liveNotificationCaptureSummary(ble: OpenVitalsBLEClient) -> String {
    if ble.connectionState == "ready" {
      return "Ready; notifications are mirrored through the app BLE client"
    }
    if ble.isScanning {
      return "Scanning; capture starts after connection"
    }
    return liveCaptureStatus
  }

  func startCapture(ble: OpenVitalsBLEClient) {
    guard captureSessionID == nil else {
      captureStatus = "Capture already active"
      return
    }

    let sessionID = "swift-capture-\(UUID().uuidString)"
    let now = Date()
    var args: [String: Any] = [
        "database_path": databasePath,
        "session_id": sessionID,
        "source": "ios_swift_more",
        "started_at_unix_ms": Self.unixMilliseconds(now),
        "device_model": ble.modelNumber ?? ble.activeDeviceName,
        "provenance": [
          "surface": "MoreCaptureView",
          "connection_state": ble.connectionState,
        ],
      ]
    if let activeDeviceID = ble.activeDeviceIdentifier?.uuidString {
      args["active_device_id"] = activeDeviceID
    }

    captureStatus = "Starting capture..."
    OpenVitalsRustBridge.performInBackground(qos: .userInitiated, {
      try OpenVitalsRustBridge().request(
        method: "capture.start_session",
        args: args
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
      captureSessionID = sessionID
      captureSessionStartedAt = now
      captureFrameCount = 0
      captureStatus = "Started \(Self.shortBridgeSummary(value))"
      refreshRecentCaptureSessions()
      case .failure(let error):
      captureStatus = "Start failed: \(Self.errorSummary(error))"
      }
    }
  }

  func stopCapture() {
    guard let sessionID = captureSessionID else {
      captureStatus = "No capture session to stop"
      return
    }

    let frameCount = captureFrameCount
    let databasePath = databasePath
    captureStatus = "Finishing capture..."
    OpenVitalsRustBridge.performInBackground(qos: .userInitiated, {
      try OpenVitalsRustBridge().request(
        method: "capture.finish_session",
        args: [
          "database_path": databasePath,
          "session_id": sessionID,
          "ended_at_unix_ms": Self.unixMilliseconds(Date()),
          "frame_count": frameCount,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
      captureStatus = "Finished \(Self.shortBridgeSummary(value))"
      captureSessionID = nil
      captureSessionStartedAt = nil
      captureFrameCount = 0
      refreshRecentCaptureSessions()
      case .failure(let error):
      captureStatus = "Finish failed: \(Self.errorSummary(error))"
      }
    }
  }

  func markFileActionUnavailable(_ kind: MoreFileActionKind) {
    switch kind {
    case .captureFile:
      captureImportStatus = "Document picker bridge is not wired in Swift yet"
    case .commandEvidence:
      commandEvidenceStatus = "Command evidence import requires a selected JSON file"
      commandEvidenceImportStatus = "Blocked until a file picker provides evidence JSON"
    case .emulatorLog:
      emulatorLogStatus = "Emulator log import requires a selected log file"
    case .localFrameMatch:
      localFrameMatchStatus = "Blocked until imported frames exist in the local store"
    case .validatedCommand:
      validatedCommandStatus = "Blocked until command validation records are imported"
    }
  }

  func storageCheckStatusSummary() -> String {
    storageStatus
  }

  func storageCheckNextActionSummary() -> String {
    storageNextAction
  }

  var databaseExists: Bool {
    FileManager.default.fileExists(atPath: databasePath)
  }

  func runStorageCheck() {
    guard databaseExists else {
      storageStatus = "Unavailable; no database at path"
      storageNextAction = "Start capture or run another bridge flow that creates the local database"
      existingOpenVitalsRecordsStatus = "No OpenVitals records"
      return
    }

    storageStatus = "Checking local store..."
    storageNextAction = "Running Rust storage checks"
    let databasePath = databasePath
    OpenVitalsRustBridge.performInBackground(qos: .userInitiated, {
      try OpenVitalsRustBridge().request(
        method: "storage.check",
        args: [
          "database_path": databasePath,
          "self_test": true,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
      storageStatus = Self.passSummary(value, fallback: Self.shortBridgeSummary(value))
      storageNextAction = Self.nextActionSummary(value, fallback: "Review any failed checks before exporting")
      if let schema = value["schema_version"].map(Self.stringValue) {
        schemaVersion = schema
      }
      existingOpenVitalsRecordsStatus = Self.recordCountSummary(value)
      case .failure(let error):
      storageStatus = "Check failed: \(Self.errorSummary(error))"
      storageNextAction = "Inspect the local database path and rerun Check"
      }
    }
  }

  var canWipeLocalAppData: Bool {
    !rawExportInProgress && !localExportInProgress && !supabaseUploadInProgress
  }

  var canClearDeviceDebugData: Bool {
    canWipeLocalAppData
      && !debugDataClearInProgress
      && !guidedReferenceProbeInProgress
      && !automaticStreamProbeInProgress
      && !streamProbePlanInProgress
      && !streamProbeDeltaInProgress
      && !k20ChannelScanInProgress
      && !k20WaveformScanInProgress
      && !beatEvidenceInProgress
      && !k18ExportReadinessInProgress
  }

  func clearDeviceDebugData() {
    guard canClearDeviceDebugData else {
      debugDataClearStatus = "Clear blocked while debug work is running"
      return
    }

    debugDataClearInProgress = true
    debugDataClearStatus = "Clearing stored debug data..."
    let databasePath = databasePath
    let outputDirectory = outputDirectory
    OpenVitalsRustBridge.performInBackground(qos: .userInitiated, {
      let result: [String: Any]
      if FileManager.default.fileExists(atPath: databasePath) {
        result = try OpenVitalsRustBridge().request(
          method: "debug.clear_data",
          args: ["database_path": databasePath]
        )
      } else {
        result = ["schema": "open_vitals.debug-data-clear-result.v1"]
      }
      let removedExportFolders = Self.removeLocalDataDirectories([
        URL(fileURLWithPath: outputDirectory, isDirectory: true),
      ])
      return (result, removedExportFolders)
    }) { [weak self] result in
      guard let self else {
        return
      }
      debugDataClearInProgress = false
      switch result {
      case .success(let clearResult):
        resetStateAfterDebugDataClear()
        debugDataClearStatus = Self.debugDataClearSummary(
          clearResult.0,
          removedExportFolders: clearResult.1
        )
      case .failure(let error):
        debugDataClearStatus = "Clear failed: \(Self.errorSummary(error))"
      }
    }
  }

  func wipeLocalAppData() {
    guard canWipeLocalAppData else {
      deletionStatus = "Wipe blocked while export is running"
      return
    }

    deletionStatus = "Wiping local app data..."
    HeartRateSeriesStore.shared.removeAllPersistedSamples()
    HRVSeriesStore.shared.removeAllPersistedSamples()
    OnboardingProfilePersistence.deletePersistedState()

    let defaultsRemoved = Self.removeOpenVitalsDefaultsPreservingRememberedDevice()
    let appDirectory = URL(fileURLWithPath: databasePath).deletingLastPathComponent()
    let documentsDirectory = URL(fileURLWithPath: outputDirectory).deletingLastPathComponent()
    let removedPaths = Self.removeLocalDataDirectories([appDirectory, documentsDirectory])
    resetStateAfterLocalDataWipe()
    deletionStatus = "Wiped local app data | removed \(removedPaths) folders | cleared \(defaultsRemoved) defaults | remembered BLE device kept"
  }

  private func resetStateAfterLocalDataWipe() {
    storageStatus = "Not checked"
    storageNextAction = "Run Check after OpenVitals has created the local database"
    schemaVersion = "Unknown"
    captureSessionID = nil
    captureSessionStartedAt = nil
    captureFrameCount = 0
    captureStatus = "No capture session"
    liveCaptureStatus = "Connect a device to mirror notifications into capture"
    recentCaptureSessions = []
    existingOpenVitalsRecordsStatus = "No local database checked"
    importedSleepHistoryStatus = "No imported sleep history loaded"
    healthSyncReports = ["No dry run yet"]
    rawExportStatus = "No export yet"
    rawBundlePath = "No bundle"
    rawZipPath = "No zip"
    rawZipURL = nil
    rawRowCounts = "No rows"
    rawValidationManifestStatus = "No validation manifest"
    rawValidationManifestURL = nil
    rawValidationReviewStatus = "No validation review"
    rawValidationReviewURL = nil
    rawValidationRunbookStatus = "No validation runbook"
    rawValidationRunbookURL = nil
    rawBundleValidation = "Not validated"
    rawZipValidation = "Not validated"
    privacyLintStatus = "Not linted"
    sanitizedPrivacyStatus = "No sanitized copy"
    automaticStreamProbeStatus = "No automatic stream probe run"
    automaticStreamProbeInProgress = false
    automaticStreamProbeStartedAt = nil
    automaticStreamProbeStopWorkItem?.cancel()
    automaticStreamProbeStopWorkItem = nil
    automaticStreamProbeCatchUpWorkItem?.cancel()
    automaticStreamProbeCatchUpWorkItem = nil
    guidedReferenceProbeStatus = "No guided reference probe run"
    guidedReferenceProbeInProgress = false
    guidedReferenceProbeWorkItem?.cancel()
    guidedReferenceProbeWorkItem = nil
    localExportStatus = "No local export"
    localExportProgress = nil
    localExportURL = nil
    localExportManifestURL = nil
    k18ExportReadinessStatus = "K18 export readiness not checked"
    k18ExportReadinessInProgress = false
    k18ExportReadinessNextActions = []
    supabaseUploadStatus = supabaseUploadIsConfigured ? "Ready to upload debug bundle" : "Not configured"
    supabaseUploadInProgress = false
    supabaseLastBundlePath = Self.supabaseNoBundleUploadText
    supabaseLastManifestPath = Self.supabaseNoManifestUploadText
    supabaseLastDatabaseRow = Self.supabaseNoDatabaseRowText
    debugWebSocketStatus = "Not started"
    debugNextAction = "Start a local debug session"
    debugSessionID = "swift-more-\(UUID().uuidString)"
  }

  private func resetStateAfterDebugDataClear() {
    captureSessionID = nil
    captureSessionStartedAt = nil
    captureFrameCount = 0
    captureStatus = "No capture session"
    liveCaptureStatus = "Connect a device to mirror notifications into capture"
    recentCaptureSessions = []
    rawExportStatus = "No export yet"
    rawBundlePath = "No bundle"
    rawZipPath = "No zip"
    rawZipURL = nil
    rawRowCounts = "No rows"
    rawValidationManifestStatus = "No validation manifest"
    rawValidationManifestURL = nil
    rawValidationReviewStatus = "No validation review"
    rawValidationReviewURL = nil
    rawValidationRunbookStatus = "No validation runbook"
    rawValidationRunbookURL = nil
    rawBundleValidation = "Not validated"
    rawZipValidation = "Not validated"
    privacyLintStatus = "Not linted"
    sanitizedPrivacyStatus = "No sanitized copy"
    streamProbeCaptureSessions = ""
    streamProbePacketDeltas = []
    streamProbeNextActions = []
    streamProbeDeltaStatus = "No packet delta analysis"
    k20ChannelCandidates = []
    k20ChannelNextActions = []
    k20ChannelScanStatus = "No K20 channel scan"
    k20WaveformCandidates = []
    k20WaveformNextActions = []
    k20WaveformScanStatus = "No K20 waveform transform scan"
    beatEvidenceNextActions = []
    beatEvidenceStatus = "No beat evidence report"
    k18ExportReadinessStatus = "K18 export readiness not checked"
    k18ExportReadinessInProgress = false
    k18ExportReadinessNextActions = []
    automaticStreamProbeStatus = "No automatic stream probe run"
    automaticStreamProbeInProgress = false
    automaticStreamProbeStartedAt = nil
    automaticStreamProbeStopWorkItem?.cancel()
    automaticStreamProbeStopWorkItem = nil
    automaticStreamProbeCatchUpWorkItem?.cancel()
    automaticStreamProbeCatchUpWorkItem = nil
    guidedReferenceProbeStatus = "No guided reference probe run"
    guidedReferenceProbeInProgress = false
    guidedReferenceProbeWorkItem?.cancel()
    guidedReferenceProbeWorkItem = nil
    localExportStatus = "No local export"
    localExportProgress = nil
    localExportURL = nil
    localExportManifestURL = nil
    debugWebSocketStatus = "Not started"
    debugNextAction = "Start a local debug session"
    debugSessionID = "swift-more-\(UUID().uuidString)"
    rrReferenceCapture.resetAfterStoredDebugClear()
  }

  private static func debugDataClearSummary(_ result: [String: Any], removedExportFolders: Int) -> String {
    let rowKeys = [
      "deleted_debug_events",
      "deleted_debug_commands",
      "deleted_debug_sessions",
      "deleted_metric_debug_features",
      "deleted_rr_reference_samples",
      "deleted_decoded_frames",
      "deleted_raw_evidence",
      "deleted_capture_sessions",
    ]
    let deletedRows = rowKeys.reduce(0) { total, key in
      total + (Int(stringValue(result[key] ?? 0)) ?? 0)
    }
    return "Cleared \(deletedRows) stored debug rows | removed \(removedExportFolders) export folders"
  }

  nonisolated private static func removeLocalDataDirectories(_ directories: [URL]) -> Int {
    var removed = 0
    let fileManager = FileManager.default
    for directory in directories {
      guard fileManager.fileExists(atPath: directory.path) else {
        continue
      }
      do {
        try fileManager.removeItem(at: directory)
        removed += 1
      } catch {
        NSLog("OpenVitals local data wipe failed for \(directory.path): \(String(describing: error))")
      }
    }
    return removed
  }

  private static func removeOpenVitalsDefaultsPreservingRememberedDevice() -> Int {
    let defaults = UserDefaults.standard
    let preservedKeys: Set<String> = [
      OpenVitalsBLEClient.DefaultsKey.rememberedDeviceID,
      OpenVitalsBLEClient.DefaultsKey.rememberedDeviceName,
      OpenVitalsBLEClient.DefaultsKey.rememberedDeviceValidated,
      OpenVitalsBLEClient.LegacyDefaultsKey.rememberedDeviceID,
      OpenVitalsBLEClient.LegacyDefaultsKey.rememberedDeviceName,
      OpenVitalsBLEClient.LegacyDefaultsKey.rememberedDeviceValidated,
    ]
    let keys = defaults.dictionaryRepresentation().keys.filter { key in
      !preservedKeys.contains(key)
        && (key.hasPrefix("open_vitals.") || key.hasPrefix("openVitals.") || key.hasPrefix("goose.swift."))
    }
    for key in keys {
      defaults.removeObject(forKey: key)
    }
    defaults.synchronize()
    return keys.count
  }

  func healthSyncBackfillWindowSummary() -> String {
    "\(healthBackfillStart) to \(healthBackfillEnd)"
  }

  func healthSyncBackfillWindowIssueSummary() -> String? {
    guard let start = Self.parseISO8601(healthBackfillStart) else {
      return "Start must be ISO-8601"
    }
    guard let end = Self.parseISO8601(healthBackfillEnd) else {
      return "End must be ISO-8601"
    }
    guard start < end else {
      return "Start must be before end"
    }
    return nil
  }

  func healthSyncMetricFamilySummary() -> String {
    "No metric families: Apple Health is profile-only"
  }

  func healthSyncMetricSourceSummary(_ family: String) -> String {
    switch family {
    case "weight": "Apple Health bodyMass profile autofill"
    default: "No source registered"
    }
  }

  func unavailableHealthSyncMetricSummary() -> String {
    Self.unavailableHealthFamilies.joined(separator: ", ")
  }

  func setHealthFamily(_ family: String, enabled: Bool) {
    if enabled {
      selectedHealthFamilies.insert(family)
    } else {
      selectedHealthFamilies.remove(family)
    }
  }

  var canRunAppleHealthDryRun: Bool {
    false
  }

  func runAppleHealthDryRun() {
    healthSyncReports = ["Apple Health metric sync disabled; OpenVitals metrics must come from local BLE packets or local estimates."]
  }

  func markHealthConnectUnavailable() {
    healthSyncReports = ["Health Connect dry run is unavailable in the iOS Swift target"]
  }

  func rawExportWindowSummary() -> String {
    "\(rawExportStart) to \(rawExportEnd)"
  }

  func rawExportWindowIssueSummary() -> String? {
    guard let start = Self.parseISO8601(rawExportStart) else {
      return "Start must be ISO-8601"
    }
    guard let end = Self.parseISO8601(rawExportEnd) else {
      return "End must be ISO-8601"
    }
    guard start < end else {
      return "Start must be before end"
    }
    return nil
  }

  func rawExportScopeSummary() -> String {
    if selectedRawFamilies.isEmpty {
      return "No data families selected"
    }
    return selectedRawFamilies.sorted().joined(separator: ", ")
  }

  func setRawFamily(_ family: String, enabled: Bool) {
    if enabled {
      selectedRawFamilies.insert(family)
    } else {
      selectedRawFamilies.remove(family)
    }
  }

  var canRunRawExport: Bool {
    databaseExists && rawExportWindowIssueSummary() == nil && !selectedRawFamilies.isEmpty
  }

  func runRawExport() {
    guard canRunRawExport else {
      rawExportStatus = rawExportWindowIssueSummary() ?? "No database or data family selected"
      return
    }

    guard !rawExportInProgress else {
      rawExportStatus = "Export already running"
      return
    }

    do {
      try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
    } catch {
      rawExportStatus = "Export failed: \(Self.errorSummary(error))"
      return
    }

    let zipPath = URL(fileURLWithPath: outputDirectory)
      .appendingPathComponent("open-vitals-raw-export-\(Int(Date().timeIntervalSince1970)).zip")
      .path
    let args: [String: Any] = [
      "database_path": databasePath,
      "output_dir": outputDirectory,
      "zip_output_path": zipPath,
      "start": rawExportStart,
      "end": rawExportEnd,
      "app_version": Self.appVersion,
      "core_version": coreVersionStatus,
      "include_sqlite": selectedRawFamilies.contains("sqlite"),
      "data_families": Array(selectedRawFamilies).sorted(),
      "include_raw_bytes": includeRawBytes,
      "capture_session_ids": Self.csvValues(rawCaptureSessions),
      "packet_type_names": Self.csvValues(rawPacketTypes),
      "sensor_source_signals": Self.csvValues(rawSensorSignals),
      "metric_families": Self.csvValues(rawMetricFamilies),
      "algorithm_ids": Self.csvValues(rawAlgorithmIDs),
      "algorithm_versions": Self.csvValues(rawAlgorithmVersions),
    ]
    let validationManifestBaseArgs: [String: Any] = [
      "database_path": databasePath,
      "manifest_id": "local-health-\(Int(Date().timeIntervalSince1970))",
      "timezone": TimeZone.current.identifier,
      "start": rawExportStart,
      "end": rawExportEnd,
    ]

    rawExportInProgress = true
    rawExportStatus = "Saving export..."
    rawZipPath = zipPath
    rawZipURL = nil
    rawValidationManifestStatus = "Generating after export..."
    rawValidationManifestURL = nil
    rawValidationReviewStatus = "Reviewing after export..."
    rawValidationReviewURL = nil
    rawValidationRunbookStatus = "Generating after export..."
    rawValidationRunbookURL = nil
    rawBundleValidation = "Not validated"
    rawZipValidation = "Not validated"
    privacyLintStatus = "Not linted"
    sanitizedPrivacyStatus = "No sanitized copy"

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let bridge = OpenVitalsRustBridge()
        let value = try bridge.request(method: "export.raw_timeframe", args: args)
        let bundlePath = Self.firstString(value, keys: ["bundle_path", "output_dir", "path"]) ?? self.outputDirectory
        let finishedZipPath = Self.firstString(value, keys: ["zip_output_path", "zip_path"]) ?? zipPath
        let rowCounts = Self.rowCountSummary(value)
        let validationSidecars: RawValidationSidecarResult
        do {
          var validationManifestArgs = validationManifestBaseArgs
          validationManifestArgs["database_source_kind"] = "raw_export_directory"
          validationManifestArgs["window_source"] = "raw_export_manifest"
          validationManifestArgs["raw_export_bundle_path"] = bundlePath
          let manifest = try bridge.request(method: "validation.local_health_manifest_scaffold", args: validationManifestArgs)
          let review = try bridge.request(
            method: "validation.local_health_manifest_review",
            args: ["manifest": manifest]
          )
          let runbookMarkdown = try Self.rawValidationRunbookMarkdown(
            bridge: bridge,
            manifest: manifest
          )
          validationSidecars = try Self.writeRawValidationSidecars(
            manifest,
            review: review,
            reviewStatus: Self.rawValidationReviewSummary(review),
            runbookMarkdown: runbookMarkdown,
            bundlePath: bundlePath,
            outputDirectory: self.outputDirectory
          )
        } catch {
          let message = Self.errorSummary(error)
          validationSidecars = RawValidationSidecarResult(
            manifestStatus: "Manifest failed: \(message)",
            manifestURL: nil,
            reviewStatus: "Review failed: \(message)",
            reviewURL: nil,
            runbookStatus: "Runbook failed: \(message)",
            runbookURL: nil
          )
        }
        let artifactValidation = Self.validateRawExportArtifacts(
          bridge: bridge,
          bundlePath: bundlePath,
          zipPath: finishedZipPath
        )
        DispatchQueue.main.async {
          let status = Self.passSummary(value, fallback: "Export completed")
          self.rawExportInProgress = false
          self.rawExportStatus = status
          self.rawBundlePath = bundlePath
          self.rawZipPath = finishedZipPath
          self.rawZipURL = URL(fileURLWithPath: finishedZipPath)
          self.rawRowCounts = rowCounts
          self.rawValidationManifestStatus = validationSidecars.manifestStatus
          self.rawValidationManifestURL = validationSidecars.manifestURL
          self.rawValidationReviewStatus = validationSidecars.reviewStatus
          self.rawValidationReviewURL = validationSidecars.reviewURL
          self.rawValidationRunbookStatus = validationSidecars.runbookStatus
          self.rawValidationRunbookURL = validationSidecars.runbookURL
          self.rawBundleValidation = artifactValidation.bundleValidation
          self.rawZipValidation = artifactValidation.zipValidation
          self.privacyLintStatus = artifactValidation.privacyLint
          self.sanitizedPrivacyStatus = artifactValidation.sanitizedPrivacy
        }
      } catch {
        DispatchQueue.main.async {
          let message = Self.errorSummary(error)
          self.rawExportInProgress = false
          self.rawExportStatus = "Export failed: \(message)"
          self.rawValidationManifestStatus = "No validation manifest"
          self.rawValidationReviewStatus = "No validation review"
          self.rawValidationRunbookStatus = "No validation runbook"
        }
      }
    }
  }

}
