import SwiftUI

struct MoreStreamProbeStep: Identifiable, Equatable {
  let sequence: Int
  let command: String
  let phase: String
  let riskGate: String
  let directSendAllowed: Bool
  let missingRequirements: [String]
  let captureWindowSeconds: Int
  let expectedPacketFamilies: [String]
  let expectedOutcome: String
  let validationRule: String
  let operatorAction: String

  var id: String { "\(sequence)-\(command)" }

  var status: MoreStatusKind {
    directSendAllowed ? .ready : .blocked
  }

  var phaseTitle: String {
    phase.replacingOccurrences(of: "_", with: " ").capitalized
  }

  var detail: String {
    let families = expectedPacketFamilies.isEmpty ? "No packet-family target" : expectedPacketFamilies.joined(separator: ", ")
    let requirements = missingRequirements.isEmpty ? "Gate ready" : "Missing \(missingRequirements.joined(separator: ", "))"
    return "\(phaseTitle) | \(families) | \(requirements)"
  }

  init(row: [String: Any]) {
    sequence = MoreStreamProbeStep.intValue(row["sequence"])
    command = MoreStreamProbeStep.stringValue(row["command"])
    phase = MoreStreamProbeStep.stringValue(row["phase"])
    riskGate = MoreStreamProbeStep.stringValue(row["risk_gate"])
    directSendAllowed = MoreStreamProbeStep.boolValue(row["direct_send_allowed"])
    missingRequirements = MoreStreamProbeStep.stringArray(row["missing_requirements"])
    captureWindowSeconds = MoreStreamProbeStep.intValue(row["capture_window_seconds"])
    expectedPacketFamilies = MoreStreamProbeStep.stringArray(row["expected_packet_families"])
    expectedOutcome = MoreStreamProbeStep.stringValue(row["expected_outcome"])
    validationRule = MoreStreamProbeStep.stringValue(row["validation_rule"])
    operatorAction = MoreStreamProbeStep.stringValue(row["operator_action"])
  }

  private static func stringValue(_ value: Any?) -> String {
    guard let value else { return "" }
    return MoreDataStore.stringValue(value)
  }

  private static func intValue(_ value: Any?) -> Int {
    if let value = value as? Int {
      return value
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    if let value = value as? String, let intValue = Int(value) {
      return intValue
    }
    return 0
  }

  private static func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
      return value
    }
    if let value = value as? NSNumber {
      return value.boolValue
    }
    if let value = value as? String {
      return value == "true" || value == "1"
    }
    return false
  }

  private static func stringArray(_ value: Any?) -> [String] {
    if let values = value as? [String] {
      return values
    }
    if let values = value as? [Any] {
      return values.map(MoreDataStore.stringValue).filter { !$0.isEmpty }
    }
    return []
  }
}

struct MoreStreamProbePacketDelta: Identifiable, Equatable {
  let family: String
  let expected: Bool
  let baselineCount: Int
  let probeCount: Int
  let deltaCount: Int
  let present: Bool
  let increased: Bool
  let firstSeen: String
  let lastSeen: String

  var id: String { family }

  var status: MoreStatusKind {
    if expected && !present {
      return .blocked
    }
    if expected && !increased {
      return .stale
    }
    if present {
      return .ready
    }
    return .notRun
  }

  var detail: String {
    let window = [firstSeen, lastSeen].filter { !$0.isEmpty }.joined(separator: " to ")
    let suffix = window.isEmpty ? "" : " | \(window)"
    return "probe \(probeCount) | baseline \(baselineCount) | delta \(deltaCount)\(suffix)"
  }

  init(row: [String: Any]) {
    family = MoreDataStore.firstString(row, keys: ["family"]) ?? "packet_family"
    expected = MoreStreamProbeStep.boolValueForDelta(row["expected"])
    baselineCount = MoreStreamProbeStep.intValueForDelta(row["baseline_count"])
    probeCount = MoreStreamProbeStep.intValueForDelta(row["probe_count"])
    deltaCount = MoreStreamProbeStep.intValueForDelta(row["delta_count"])
    present = MoreStreamProbeStep.boolValueForDelta(row["present"])
    increased = MoreStreamProbeStep.boolValueForDelta(row["increased"])
    firstSeen = MoreDataStore.firstString(row, keys: ["first_seen"]) ?? ""
    lastSeen = MoreDataStore.firstString(row, keys: ["last_seen"]) ?? ""
  }
}

struct MoreK20ChannelCandidate: Identifiable, Equatable {
  let rank: Int
  let channelId: String
  let offset: Int
  let polarity: String
  let matchedSegmentCount: Int
  let usableSegmentCount: Int
  let withinToleranceFraction: Double
  let meanAbsoluteErrorBPM: Double?
  let medianCandidateRRMS: Double?
  let rrReferenceMatchedSegmentCount: Int
  let rrReferenceWithinToleranceFraction: Double?
  let meanAbsoluteErrorRRMS: Double?
  let medianRMSSDMS: Double?
  let medianIntervalCount: Double?

  var id: String { "\(rank)-\(channelId)-\(polarity)" }

  var status: MoreStatusKind {
    if withinToleranceFraction >= 0.8 {
      return .ready
    }
    return matchedSegmentCount > 0 ? .blocked : .notRun
  }

  var detail: String {
    let percent = Int((withinToleranceFraction * 100).rounded())
    let error = meanAbsoluteErrorBPM.map { "MAE \(Self.format($0)) bpm" } ?? "No HR match"
    let rr = medianCandidateRRMS.map { "RR \(Self.format($0)) ms" } ?? "RR --"
    let rrReference = rrReferenceWithinToleranceFraction.map {
      let referencePercent = Int(($0 * 100).rounded())
      let referenceError = meanAbsoluteErrorRRMS.map { "MAE \(Self.format($0)) ms" } ?? "MAE --"
      return "RR ref \(rrReferenceMatchedSegmentCount) | \(referencePercent)% | \(referenceError)"
    } ?? "RR ref --"
    let intervals = medianIntervalCount.map { "intervals \(Self.format($0))" } ?? "intervals --"
    return "\(polarity) | \(matchedSegmentCount)/\(usableSegmentCount) matched | \(percent)% within | \(error) | \(rr) | \(rrReference) | \(intervals)"
  }

  init(row: [String: Any]) {
    rank = MoreStreamProbeStep.intValueForDelta(row["rank"])
    channelId = MoreDataStore.firstString(row, keys: ["channel_id"]) ?? "k20_channel"
    offset = MoreStreamProbeStep.intValueForDelta(row["offset"])
    polarity = MoreDataStore.firstString(row, keys: ["polarity"]) ?? "unknown"
    matchedSegmentCount = MoreStreamProbeStep.intValueForDelta(row["matched_segment_count"])
    usableSegmentCount = MoreStreamProbeStep.intValueForDelta(row["usable_segment_count"])
    withinToleranceFraction = MoreStreamProbeStep.doubleValueForDelta(row["within_tolerance_fraction"])
    meanAbsoluteErrorBPM = MoreStreamProbeStep.optionalDoubleValueForDelta(row["mean_absolute_error_bpm"])
    medianCandidateRRMS = MoreStreamProbeStep.optionalDoubleValueForDelta(row["median_candidate_rr_ms"])
    rrReferenceMatchedSegmentCount = MoreStreamProbeStep.intValueForDelta(row["rr_reference_matched_segment_count"])
    rrReferenceWithinToleranceFraction = MoreStreamProbeStep.optionalDoubleValueForDelta(row["rr_reference_within_tolerance_fraction"])
    meanAbsoluteErrorRRMS = MoreStreamProbeStep.optionalDoubleValueForDelta(row["mean_absolute_error_rr_ms"])
    medianRMSSDMS = MoreStreamProbeStep.optionalDoubleValueForDelta(row["median_rmssd_ms"])
    medianIntervalCount = MoreStreamProbeStep.optionalDoubleValueForDelta(row["median_interval_count"])
  }

  private static func format(_ value: Double) -> String {
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return String(format: "%.1f", value)
  }
}

private extension MoreStreamProbeStep {
  static func intValueForDelta(_ value: Any?) -> Int {
    intValue(value)
  }

  static func boolValueForDelta(_ value: Any?) -> Bool {
    boolValue(value)
  }

  static func doubleValueForDelta(_ value: Any?) -> Double {
    optionalDoubleValueForDelta(value) ?? 0
  }

  static func optionalDoubleValueForDelta(_ value: Any?) -> Double? {
    if let value = value as? Double {
      return value
    }
    if let value = value as? NSNumber {
      return value.doubleValue
    }
    if let value = value as? String {
      return Double(value)
    }
    return nil
  }
}

extension MoreDataStore {
  static let streamProbeCommands = [
    "get_led_drive",
    "get_tia_gain",
    "get_bias_offset",
    "get_research_packet",
    "toggle_realtime_hr",
    "send_r10_r11_realtime",
    "start_raw_data",
    "enable_optical_data",
    "toggle_optical_mode",
    "toggle_labrador_data_generation",
    "toggle_labrador_raw_save",
    "toggle_labrador_filtered",
    "toggle_imu_mode",
    "toggle_imu_mode_historical",
    "set_research_packet",
    "toggle_persistent_r20",
    "toggle_persistent_r21",
    "stop_raw_data",
  ]

  static let defaultStreamProbeExpectedPacketFamilies = [
    "K10_raw_stream",
    "K11_raw_stream",
    "K16_raw_ecg_labrador",
    "K17_R17_optical_or_filtered",
    "K18_trusted_heart_rate",
    "K20_raw_or_research_stream",
    "K21_raw_motion_stream",
    "K26_pulse_information",
  ]

  func refreshStreamProbePlan() {
    streamProbePlanInProgress = true
    streamProbePlanStatus = "Loading stream probe plan..."
    let databasePath = databasePath
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "commands.capture_plan",
        args: [
          "database_path": databasePath,
          "commands": Self.streamProbeCommands,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      streamProbePlanInProgress = false
      switch result {
      case .success(let value):
        applyStreamProbePlan(value)
      case .failure(let error):
        streamProbePlanStatus = "Plan failed: \(Self.errorSummary(error))"
        streamProbeSteps = []
        streamProbeExpectedPacketFamilies = []
      }
    }
  }

  func runStreamProbePacketDelta() {
    guard streamProbeWindowIssueSummary() == nil else {
      streamProbeDeltaStatus = streamProbeWindowIssueSummary() ?? "Window blocked"
      return
    }

    streamProbeDeltaInProgress = true
    streamProbeDeltaStatus = "Analyzing packet deltas..."
    streamProbePacketDeltas = []
    streamProbeNextActions = []
    let databasePath = databasePath
    let expected = streamProbeExpectedPacketFamilies.isEmpty ? Self.defaultStreamProbeExpectedPacketFamilies : streamProbeExpectedPacketFamilies
    var args: [String: Any] = [
      "database_path": databasePath,
      "start": streamProbeStart,
      "end": streamProbeEnd,
      "expected_packet_families": expected,
      "capture_session_ids": Self.csvValues(streamProbeCaptureSessions),
    ]
    if !streamProbeBaselineStart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !streamProbeBaselineEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      args["baseline_start"] = streamProbeBaselineStart
      args["baseline_end"] = streamProbeBaselineEnd
    }

    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "commands.stream_probe_packet_delta",
        args: args
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      streamProbeDeltaInProgress = false
      switch result {
      case .success(let value):
        applyStreamProbeDelta(value)
      case .failure(let error):
        streamProbeDeltaStatus = "Delta failed: \(Self.errorSummary(error))"
      }
    }
  }

  func runK20ChannelScan() {
    guard streamProbeWindowIssueSummary() == nil else {
      k20ChannelScanStatus = streamProbeWindowIssueSummary() ?? "Window blocked"
      return
    }

    k20ChannelScanInProgress = true
    k20ChannelScanStatus = "Scanning K20 optical channels..."
    k20ChannelCandidates = []
    k20ChannelNextActions = []
    let databasePath = databasePath
    let start = streamProbeStart
    let end = streamProbeEnd
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "metrics.k20_optical_channel_scan",
        args: [
          "database_path": databasePath,
          "start": start,
          "end": end,
          "min_owned_captures": 1,
          "sample_rate_hz": 25.0,
          "min_peak_spacing_samples": 8,
          "max_hr_match_lag_seconds": 10.0,
          "hr_tolerance_bpm": 8.0,
          "min_matching_segments": 2,
          "max_ranked_channels": 12,
          "max_segment_summaries": 8,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      k20ChannelScanInProgress = false
      switch result {
      case .success(let value):
        applyK20ChannelScan(value)
      case .failure(let error):
        k20ChannelScanStatus = "K20 scan failed: \(Self.errorSummary(error))"
      }
    }
  }

  func streamProbeWindowIssueSummary() -> String? {
    guard let start = Self.parseISO8601(streamProbeStart) else {
      return "Start must be ISO-8601 UTC"
    }
    guard let end = Self.parseISO8601(streamProbeEnd) else {
      return "End must be ISO-8601 UTC"
    }
    guard end > start else {
      return "End must be after start"
    }
    let baselineStart = streamProbeBaselineStart.trimmingCharacters(in: .whitespacesAndNewlines)
    let baselineEnd = streamProbeBaselineEnd.trimmingCharacters(in: .whitespacesAndNewlines)
    if baselineStart.isEmpty != baselineEnd.isEmpty {
      return "Baseline needs both start and end"
    }
    if !baselineStart.isEmpty {
      guard let parsedBaselineStart = Self.parseISO8601(baselineStart),
            let parsedBaselineEnd = Self.parseISO8601(baselineEnd),
            parsedBaselineEnd > parsedBaselineStart else {
        return "Baseline window is invalid"
      }
    }
    return nil
  }

  private func applyStreamProbePlan(_ value: [String: Any]) {
    guard let plan = value["stream_probe_plan"] as? [String: Any] else {
      streamProbePlanStatus = "Plan missing stream probe details"
      streamProbeSteps = []
      streamProbeExpectedPacketFamilies = []
      return
    }
    streamProbeExpectedPacketFamilies = Self.stringArray(plan["expected_packet_families"])
    let rows = plan["steps"] as? [[String: Any]] ?? []
    streamProbeSteps = rows.map(MoreStreamProbeStep.init(row:))
    let stepCount = Self.firstString(plan, keys: ["step_count"]) ?? "\(streamProbeSteps.count)"
    let allReady = (plan["all_stream_gates_ready"] as? Bool) == true
    let lockedCount = Self.firstString(value, keys: ["locked_count"]) ?? "0"
    let criticalLocked = Self.firstString(value, keys: ["critical_locked_count"]) ?? "0"
    streamProbePlanStatus = allReady
      ? "\(stepCount) steps ready"
      : "\(stepCount) steps | \(lockedCount) locked | \(criticalLocked) critical locked"
  }

  private func applyStreamProbeDelta(_ value: [String: Any]) {
    let deltas = value["family_deltas"] as? [[String: Any]] ?? []
    streamProbePacketDeltas = deltas.map(MoreStreamProbePacketDelta.init(row:))
    let nextActions = value["next_actions"] as? [[String: Any]] ?? []
    streamProbeNextActions = nextActions.map { row in
      let family = Self.firstString(row, keys: ["family"]) ?? "packet family"
      let action = Self.firstString(row, keys: ["action"]) ?? Self.shortBridgeSummary(row)
      return "\(family): \(action)"
    }
    let expected = Self.firstString(value, keys: ["expected_family_count"]) ?? "0"
    let present = Self.firstString(value, keys: ["present_expected_count"]) ?? "0"
    let increased = Self.firstString(value, keys: ["increased_expected_count"]) ?? "0"
    let frames = Self.firstString(value, keys: ["total_probe_frames"]) ?? "0"
    let pass = (value["pass"] as? Bool) == true
    streamProbeDeltaStatus = "\(present)/\(expected) present | \(increased) increased | \(frames) frames | \(pass ? "passed" : "blocked")"
  }

  private func applyK20ChannelScan(_ value: [String: Any]) {
    let candidates = value["ranked_channels"] as? [[String: Any]] ?? []
    k20ChannelCandidates = candidates.map(MoreK20ChannelCandidate.init(row:))
    let nextActions = value["next_actions"] as? [[String: Any]] ?? []
    k20ChannelNextActions = nextActions.map { row in
      let reason = Self.firstString(row, keys: ["reason"]) ?? "next_action"
      let action = Self.firstString(row, keys: ["action"]) ?? Self.shortBridgeSummary(row)
      return "\(reason): \(action)"
    }
    let status = Self.firstString(value, keys: ["validation_status"]) ?? "unknown"
    let k20Frames = Self.firstString(value, keys: ["k20_frame_count"]) ?? "0"
    let realtimeFrames = Self.firstString(value, keys: ["realtime_k20_frame_count"]) ?? "0"
    let matched = Self.firstString(value, keys: ["matched_segment_count"]) ?? "0"
    let rrMatched = Self.firstString(value, keys: ["rr_reference_matched_segment_count"]) ?? "0"
    let rrSamples = Self.firstString(value, keys: ["rr_reference_sample_count"]) ?? "0"
    let candidatesCount = Self.firstString(value, keys: ["candidate_segment_count"]) ?? "0"
    let pass = (value["pass"] as? Bool) == true
    k20ChannelScanStatus = "\(status) | K20 \(k20Frames) | realtime \(realtimeFrames) | HR \(matched)/\(candidatesCount) | RR ref \(rrMatched)/\(rrSamples) | \(pass ? "passed" : "blocked")"
  }

  private static func stringArray(_ value: Any?) -> [String] {
    if let values = value as? [String] {
      return values
    }
    if let values = value as? [Any] {
      return values.map(stringValue).filter { !$0.isEmpty }
    }
    return []
  }

  static let automaticStreamProbeDuration: TimeInterval = 30 * 60
  static let automaticStreamProbeWindowPadding: TimeInterval = 30

  func startAutomaticStreamProbe(model: OpenVitalsAppModel) {
    guard !automaticStreamProbeInProgress else {
      automaticStreamProbeStatus = "Automatic stream probe already running"
      return
    }
    guard model.ble.connectionState == "ready" else {
      automaticStreamProbeStatus = "Connect the band first. Current state: \(model.ble.connectionState)"
      return
    }

    automaticStreamProbeStopWorkItem?.cancel()
    automaticStreamProbeStopWorkItem = nil
    automaticStreamProbeInProgress = true
    automaticStreamProbeStartedAt = nil
    automaticStreamProbeStatus = "Starting diagnostic packet capture..."
    streamProbeBaselineStart = ""
    streamProbeBaselineEnd = ""
    streamProbeCaptureSessions = ""
    streamProbePacketDeltas = []
    streamProbeNextActions = []
    k20ChannelCandidates = []
    k20ChannelNextActions = []
    localExportURL = nil
    localExportManifestURL = nil

    refreshStreamProbePlan()

    if model.healthPacketCaptureSessionID != nil {
      automaticStreamProbeStatus = "Stopping existing packet capture before starting automatic probe..."
      model.stopHealthPacketCapture(reason: "stream_probe_auto_replace_existing_capture") { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        guard model.healthPacketCaptureSessionID == nil else {
          self.automaticStreamProbeInProgress = false
          self.automaticStreamProbeStatus = "Existing capture is still active: \(model.healthPacketCaptureStatus)"
          return
        }
        self.beginAutomaticStreamProbeCapture(model: model)
      }
      return
    }

    beginAutomaticStreamProbeCapture(model: model)
  }

  private func beginAutomaticStreamProbeCapture(model: OpenVitalsAppModel) {
    automaticStreamProbeStatus = "Starting diagnostic packet capture..."
    model.startHealthPacketCapture(
      mode: .diagnostic,
      duration: Self.automaticStreamProbeDuration,
      source: "stream_probe.auto"
    ) { [weak self, weak model] started in
      guard let self, let model else {
        return
      }
      guard started else {
        self.automaticStreamProbeInProgress = false
        self.automaticStreamProbeStatus = "Could not start capture: \(model.healthPacketCaptureStatus)"
        return
      }

      let startedAt = model.healthPacketCaptureStartedAt ?? Date()
      self.automaticStreamProbeStartedAt = startedAt
      self.streamProbeStart = startedAt.addingTimeInterval(-Self.automaticStreamProbeWindowPadding).moreISO8601String()
      self.streamProbeEnd = startedAt.addingTimeInterval(Self.automaticStreamProbeDuration + Self.automaticStreamProbeWindowPadding).moreISO8601String()
      self.rawExportStart = self.streamProbeStart
      self.rawExportEnd = self.streamProbeEnd
      self.automaticStreamProbeStatus = "Capturing diagnostic packets for \(Self.automaticProbeDurationText). Keep the app open and the band connected."

      let workItem = DispatchWorkItem { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        self.finishAutomaticStreamProbe(model: model, reason: "timer elapsed")
      }
      self.automaticStreamProbeStopWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.automaticStreamProbeDuration, execute: workItem)
    }
  }

  func finishAutomaticStreamProbe(model: OpenVitalsAppModel, reason: String = "manual stop") {
    automaticStreamProbeStopWorkItem?.cancel()
    automaticStreamProbeStopWorkItem = nil

    guard automaticStreamProbeInProgress else {
      automaticStreamProbeStatus = "No automatic stream probe is running"
      return
    }

    automaticStreamProbeStatus = "Stopping capture and preparing analysis..."
    model.stopHealthPacketCapture(reason: "stream_probe_auto_\(reason.replacingOccurrences(of: " ", with: "_"))") { [weak self] in
      guard let self else {
        return
      }
      let endedAt = Date()
      if self.automaticStreamProbeStartedAt == nil {
        self.automaticStreamProbeStartedAt = endedAt
        self.streamProbeStart = endedAt.addingTimeInterval(-Self.automaticStreamProbeDuration - Self.automaticStreamProbeWindowPadding).moreISO8601String()
      }
      self.streamProbeEnd = endedAt.addingTimeInterval(Self.automaticStreamProbeWindowPadding).moreISO8601String()
      self.rawExportStart = self.streamProbeStart
      self.rawExportEnd = self.streamProbeEnd
      self.refreshRecentCaptureSessions()
      self.automaticStreamProbeStatus = "Capture stopped. Running packet delta and K20 channel analysis, then creating the AirDrop bundle."
      self.runStreamProbePacketDelta()
      self.runK20ChannelScan()
      self.saveLocalDataBundle()
      self.automaticStreamProbeInProgress = false
    }
  }

  private static var automaticProbeDurationText: String {
    let minutes = Int((automaticStreamProbeDuration / 60).rounded())
    return "\(minutes) min"
  }
}

private struct MoreRRReferenceCaptureSection: View {
  @ObservedObject var referenceCapture: OpenVitalsRRReferenceCapture

  var body: some View {
    Section("RR Reference") {
      MoreActionRow(
        title: referenceCapture.isScanning ? "Stop Reference Scan" : "Scan For RR Reference",
        detail: referenceCapture.isScanning ? "Scanning for standard BLE heart-rate devices" : referenceCapture.status,
        systemImage: referenceCapture.isScanning ? "stop.circle" : "dot.radiowaves.left.and.right",
        status: referenceCapture.isScanning ? .listening : .pending,
        disabled: referenceCapture.isCapturing
      ) {
        if referenceCapture.isScanning {
          referenceCapture.stopScanning()
        } else {
          referenceCapture.startScanning()
        }
      }

      if referenceCapture.discoveredDevices.isEmpty {
        MoreInfoRow(
          title: "Reference Devices",
          value: referenceCapture.isScanning ? "Listening for Heart Rate Service devices" : "Run scan with the reference strap awake and nearby",
          systemImage: "sensor.tag.radiowaves.forward",
          status: referenceCapture.isScanning ? .listening : .notRun
        )
      } else {
        ForEach(referenceCapture.discoveredDevices) { device in
          MoreActionRow(
            title: referenceCapture.isCapturing && referenceCapture.activeDeviceID == device.id.uuidString ? "Capturing From \(device.name)" : device.name,
            detail: "RSSI \(device.rssi) | \(device.id.uuidString)",
            systemImage: "heart.text.square",
            status: referenceCapture.isCapturing && referenceCapture.activeDeviceID == device.id.uuidString ? .listening : .ready,
            disabled: referenceCapture.isCapturing
          ) {
            referenceCapture.startCapture(deviceID: device.id)
          }
        }
      }

      if referenceCapture.isCapturing {
        MoreActionRow(
          title: "Stop RR Reference Capture",
          detail: referenceCapture.status,
          systemImage: "stop.circle",
          status: .listening,
          disabled: false
        ) {
          referenceCapture.stopCapture()
        }
      }

      MoreInfoRow(
        title: "Status",
        value: referenceCapture.status,
        systemImage: "waveform.path.ecg",
        status: referenceStatus
      )
      MoreInfoRow(
        title: "Samples",
        value: sampleDetail,
        systemImage: "list.number",
        status: referenceCapture.sampleCount > 0 ? .ready : .pending
      )
      MoreInfoRow(
        title: "Storage",
        value: referenceCapture.lastFlushStatus,
        systemImage: "externaldrive",
        status: storageStatus
      )
      MoreActionRow(
        title: "Refresh RR Summary",
        detail: referenceCapture.summaryStatus,
        systemImage: "chart.xyaxis.line",
        status: referenceCapture.sampleCount > 0 ? .ready : .pending,
        disabled: referenceCapture.sessionID == nil
      ) {
        referenceCapture.refreshSummary()
      }
    }
  }

  private var sampleDetail: String {
    let heartRate = referenceCapture.lastHeartRateBPM.map { "\($0) bpm" } ?? "-- bpm"
    let rr = referenceCapture.lastRRIntervalMS.map { "\(Int($0.rounded())) ms" } ?? "-- ms"
    let capturedAt = referenceCapture.lastCapturedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "no sample"
    return "\(referenceCapture.sampleCount) RR samples | \(referenceCapture.notificationCount) notifications | HR \(heartRate) | RR \(rr) | \(capturedAt)"
  }

  private var referenceStatus: MoreStatusKind {
    if referenceCapture.isCapturing {
      return .listening
    }
    if referenceCapture.status.localizedCaseInsensitiveContains("failed") {
      return .blocked
    }
    return referenceCapture.sampleCount > 0 ? .ready : .pending
  }

  private var storageStatus: MoreStatusKind {
    if referenceCapture.lastFlushStatus.localizedCaseInsensitiveContains("failed") {
      return .blocked
    }
    return referenceCapture.sampleCount > 0 ? .ready : .pending
  }
}

struct MoreStreamProbePlanView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section("Automatic Probe") {
        MoreActionRow(
          title: store.automaticStreamProbeInProgress ? "Stop And Analyze Now" : "Start Automatic Probe",
          detail: automaticProbeDetail,
          systemImage: store.automaticStreamProbeInProgress ? "stop.circle" : "play.circle",
          status: automaticProbeStatus,
          disabled: !store.automaticStreamProbeInProgress && model.ble.connectionState != "ready"
        ) {
          if store.automaticStreamProbeInProgress {
            store.finishAutomaticStreamProbe(model: model)
          } else {
            store.startAutomaticStreamProbe(model: model)
          }
        }
        MoreInfoRow(
          title: "Capture",
          value: model.healthPacketCaptureStatus,
          systemImage: "record.circle",
          status: model.healthPacketCaptureSessionID == nil ? .pending : .listening
        )
        MoreInfoRow(
          title: "Output",
          value: store.localExportStatus,
          systemImage: "doc",
          status: store.localExportInProgress ? .inProgress : (store.localExportURL == nil ? .pending : .ready)
        )
        if store.automaticStreamProbeInProgress || store.localExportInProgress {
          ProgressView(store.automaticStreamProbeInProgress ? store.automaticStreamProbeStatus : store.localExportStatus)
        }
        if let localExportURL = store.localExportURL {
          ShareLink(item: localExportURL) {
            Label("AirDrop Local Data File", systemImage: "square.and.arrow.up")
          }
        }
        if let localExportManifestURL = store.localExportManifestURL {
          ShareLink(item: localExportManifestURL) {
            Label("AirDrop Manifest", systemImage: "list.bullet.rectangle")
          }
        }
      }

      MoreRRReferenceCaptureSection(referenceCapture: store.rrReferenceCapture)

      Section("Plan") {
        MoreActionRow(
          title: "Refresh Stream Probe Plan",
          detail: store.streamProbePlanStatus,
          systemImage: "scope",
          status: planStatus,
          disabled: store.streamProbePlanInProgress
        ) {
          store.refreshStreamProbePlan()
        }
        if store.streamProbePlanInProgress {
          ProgressView(store.streamProbePlanStatus)
        }
        MoreInfoRow(
          title: "Gate State",
          value: store.streamProbePlanStatus,
          systemImage: "lock.shield",
          status: planStatus
        )
      }

      Section("Analysis Window") {
        MoreInfoRow(
          title: "Window",
          value: store.streamProbeWindowIssueSummary() ?? "\(store.streamProbeStart) to \(store.streamProbeEnd)",
          systemImage: "calendar",
          status: store.streamProbeWindowIssueSummary() == nil ? .ready : .blocked
        )
        TextField("Start", text: $store.streamProbeStart)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
        TextField("End", text: $store.streamProbeEnd)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
        TextField("Baseline start", text: $store.streamProbeBaselineStart)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
        TextField("Baseline end", text: $store.streamProbeBaselineEnd)
          .textInputAutocapitalization(.never)
          .keyboardType(.numbersAndPunctuation)
        TextField("Capture sessions", text: $store.streamProbeCaptureSessions)
          .textInputAutocapitalization(.never)
        ForEach(store.recentCaptureSessions, id: \.self) { session in
          Button {
            store.streamProbeCaptureSessions = session.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? store.streamProbeCaptureSessions
          } label: {
            Label(session, systemImage: "clock.arrow.circlepath")
          }
        }
        MoreActionRow(
          title: "Run Packet Delta Analysis",
          detail: store.streamProbeDeltaStatus,
          systemImage: "waveform.path.ecg.rectangle",
          status: deltaStatus,
          disabled: store.streamProbeDeltaInProgress || store.streamProbeWindowIssueSummary() != nil
        ) {
          store.runStreamProbePacketDelta()
        }
        if store.streamProbeDeltaInProgress {
          ProgressView(store.streamProbeDeltaStatus)
        }
      }

      Section("Expected Families") {
        let families = store.streamProbeExpectedPacketFamilies.isEmpty ? MoreDataStore.defaultStreamProbeExpectedPacketFamilies : store.streamProbeExpectedPacketFamilies
        ForEach(families, id: \.self) { family in
          MoreInfoRow(
            title: family,
            value: "Packet delta target",
            systemImage: "target",
            status: .pending
          )
        }
      }

      Section("Probe Steps") {
        if store.streamProbeSteps.isEmpty {
          MoreInfoRow(
            title: "Steps",
            value: "Refresh the stream probe plan",
            systemImage: "list.number",
            status: .notRun
          )
        } else {
          ForEach(store.streamProbeSteps) { step in
            MoreInfoRow(
              title: "\(step.sequence). \(step.command)",
              value: step.detail,
              systemImage: icon(for: step),
              status: step.status,
              statusTitle: step.directSendAllowed ? "Ready" : "Locked"
            )
          }
        }
      }

      Section("Packet Delta") {
        MoreInfoRow(
          title: "Status",
          value: store.streamProbeDeltaStatus,
          systemImage: "chart.bar.xaxis",
          status: deltaStatus
        )
        if store.streamProbePacketDeltas.isEmpty {
          MoreInfoRow(
            title: "Families",
            value: "Run packet delta analysis",
            systemImage: "waveform",
            status: .notRun
          )
        } else {
          ForEach(store.streamProbePacketDeltas.prefix(16)) { delta in
            MoreInfoRow(
              title: delta.family,
              value: delta.detail,
              systemImage: delta.expected ? "target" : "waveform",
              status: delta.status
            )
          }
        }
      }

      Section("K20 Channel Scan") {
        MoreActionRow(
          title: "Run K20 Channel Scan",
          detail: store.k20ChannelScanStatus,
          systemImage: "waveform.path",
          status: k20Status,
          disabled: store.k20ChannelScanInProgress || store.streamProbeWindowIssueSummary() != nil
        ) {
          store.runK20ChannelScan()
        }
        if store.k20ChannelScanInProgress {
          ProgressView(store.k20ChannelScanStatus)
        }
        MoreInfoRow(
          title: "Status",
          value: store.k20ChannelScanStatus,
          systemImage: "waveform.path.ecg",
          status: k20Status
        )
        if store.k20ChannelCandidates.isEmpty {
          MoreInfoRow(
            title: "Channels",
            value: "Run K20 channel scan",
            systemImage: "chart.bar",
            status: .notRun
          )
        } else {
          ForEach(store.k20ChannelCandidates.prefix(8)) { candidate in
            MoreInfoRow(
              title: "\(candidate.rank). offset \(candidate.offset)",
              value: candidate.detail,
              systemImage: "waveform.path",
              status: candidate.status
            )
          }
        }
      }

      if !store.streamProbeNextActions.isEmpty {
        Section("Next Actions") {
          ForEach(store.streamProbeNextActions.prefix(8), id: \.self) { action in
            MoreInfoRow(
              title: "Action",
              value: action,
              systemImage: "arrow.forward.circle",
              status: .blocked
            )
          }
        }
      }

      if !store.k20ChannelNextActions.isEmpty {
        Section("K20 Next Actions") {
          ForEach(store.k20ChannelNextActions.prefix(6), id: \.self) { action in
            MoreInfoRow(
              title: "Action",
              value: action,
              systemImage: "arrow.forward.circle",
              status: .blocked
            )
          }
        }
      }
    }
    .openVitalsListBackground()
    .navigationTitle("Stream Probe Plan")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      store.refreshRecentCaptureSessions()
      if store.streamProbeSteps.isEmpty {
        store.refreshStreamProbePlan()
      }
    }
  }

  private var automaticProbeStatus: MoreStatusKind {
    if store.automaticStreamProbeInProgress {
      return .listening
    }
    if store.localExportInProgress || store.streamProbeDeltaInProgress || store.k20ChannelScanInProgress {
      return .inProgress
    }
    if store.automaticStreamProbeStatus.localizedCaseInsensitiveContains("could not start")
      || store.automaticStreamProbeStatus.localizedCaseInsensitiveContains("connect the band")
      || store.automaticStreamProbeStatus.localizedCaseInsensitiveContains("already active")
    {
      return .blocked
    }
    if store.localExportURL != nil {
      return .ready
    }
    return .notRun
  }

  private var automaticProbeDetail: String {
    if store.automaticStreamProbeInProgress {
      return store.automaticStreamProbeStatus
    }
    if store.localExportInProgress {
      return store.localExportStatus
    }
    if store.localExportURL != nil {
      return "AirDrop bundle ready. Share the local data file and manifest below."
    }
    if store.streamProbeDeltaInProgress {
      return store.streamProbeDeltaStatus
    }
    if store.k20ChannelScanInProgress {
      return store.k20ChannelScanStatus
    }
    return store.automaticStreamProbeStatus
  }

  private var planStatus: MoreStatusKind {
    if store.streamProbePlanInProgress {
      return .inProgress
    }
    if store.streamProbePlanStatus.localizedCaseInsensitiveContains("failed") {
      return .blocked
    }
    if store.streamProbePlanStatus.localizedCaseInsensitiveContains("locked") {
      return .blocked
    }
    return store.streamProbeSteps.isEmpty ? .notRun : .ready
  }

  private var deltaStatus: MoreStatusKind {
    if store.streamProbeDeltaInProgress {
      return .inProgress
    }
    if store.streamProbeDeltaStatus.localizedCaseInsensitiveContains("passed") {
      return .ready
    }
    if store.streamProbeDeltaStatus.localizedCaseInsensitiveContains("blocked")
      || store.streamProbeDeltaStatus.localizedCaseInsensitiveContains("failed")
    {
      return .blocked
    }
    return store.streamProbePacketDeltas.isEmpty ? .notRun : .stale
  }

  private var k20Status: MoreStatusKind {
    if store.k20ChannelScanInProgress {
      return .inProgress
    }
    if store.k20ChannelScanStatus.localizedCaseInsensitiveContains("passed") {
      return .ready
    }
    if store.k20ChannelScanStatus.localizedCaseInsensitiveContains("blocked")
      || store.k20ChannelScanStatus.localizedCaseInsensitiveContains("failed")
    {
      return .blocked
    }
    return store.k20ChannelCandidates.isEmpty ? .notRun : .stale
  }

  private func icon(for step: MoreStreamProbeStep) -> String {
    switch step.phase {
    case "baseline_read":
      return "doc.text.magnifyingglass"
    case "temporary_stream_toggle":
      return "dot.radiowaves.left.and.right"
    case "persistent_config":
      return "lock.shield"
    case "shutdown":
      return "stop.circle"
    default:
      return "scope"
    }
  }
}
