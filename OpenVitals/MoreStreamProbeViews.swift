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
  let probeFirstSeen: String
  let probeLastSeen: String
  let baselineFirstSeen: String
  let baselineLastSeen: String
  let presenceAttribution: String

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
    let probeWindow = [probeFirstSeen, probeLastSeen].filter { !$0.isEmpty }.joined(separator: " to ")
    let baselineWindow = [baselineFirstSeen, baselineLastSeen].filter { !$0.isEmpty }.joined(separator: " to ")
    let timing: String
    if !probeWindow.isEmpty && !baselineWindow.isEmpty {
      timing = " | probe \(probeWindow) | baseline \(baselineWindow)"
    } else if !probeWindow.isEmpty {
      timing = " | probe \(probeWindow)"
    } else {
      let window = [firstSeen, lastSeen].filter { !$0.isEmpty }.joined(separator: " to ")
      timing = window.isEmpty ? "" : " | \(window)"
    }
    return "\(presenceAttribution.replacingOccurrences(of: "_", with: " ")) | probe \(probeCount) | baseline \(baselineCount) | delta \(deltaCount)\(timing)"
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
    probeFirstSeen = MoreDataStore.firstString(row, keys: ["probe_first_seen"]) ?? ""
    probeLastSeen = MoreDataStore.firstString(row, keys: ["probe_last_seen"]) ?? ""
    baselineFirstSeen = MoreDataStore.firstString(row, keys: ["baseline_first_seen"]) ?? ""
    baselineLastSeen = MoreDataStore.firstString(row, keys: ["baseline_last_seen"]) ?? ""
    presenceAttribution = MoreDataStore.firstString(row, keys: ["presence_attribution"]) ?? "unknown"
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

  fileprivate static func format(_ value: Double) -> String {
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return String(format: "%.1f", value)
  }
}

struct MoreK20WaveformCandidate: Identifiable, Equatable {
  let rank: Int
  let channelId: String
  let offset: Int
  let polarity: String
  let sampleRateHz: Double
  let minPeakSpacingSamples: Int
  let smoothingWindowSamples: Int
  let thresholdStddevMultiplier: Double
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

  var id: String { "\(rank)-\(channelId)-\(polarity)-\(sampleRateHz)-\(thresholdStddevMultiplier)" }

  var status: MoreStatusKind {
    if rrReferenceWithinToleranceFraction ?? 0 >= 0.8 {
      return .ready
    }
    if withinToleranceFraction >= 0.8 {
      return .stale
    }
    return matchedSegmentCount > 0 ? .blocked : .notRun
  }

  var detail: String {
    let percent = Int((withinToleranceFraction * 100).rounded())
    let rrReference = rrReferenceWithinToleranceFraction.map {
      let referencePercent = Int(($0 * 100).rounded())
      let referenceError = meanAbsoluteErrorRRMS.map { "MAE \(MoreK20ChannelCandidate.format($0)) ms" } ?? "MAE --"
      return "RR ref \(rrReferenceMatchedSegmentCount) | \(referencePercent)% | \(referenceError)"
    } ?? "RR ref --"
    let error = meanAbsoluteErrorBPM.map { "MAE \(MoreK20ChannelCandidate.format($0)) bpm" } ?? "No HR match"
    let rr = medianCandidateRRMS.map { "RR \(MoreK20ChannelCandidate.format($0)) ms" } ?? "RR --"
    let rmssd = medianRMSSDMS.map { "RMSSD \(MoreK20ChannelCandidate.format($0)) ms" } ?? "RMSSD --"
    let intervals = medianIntervalCount.map { "intervals \(MoreK20ChannelCandidate.format($0))" } ?? "intervals --"
    return "\(polarity) | \(MoreK20ChannelCandidate.format(sampleRateHz)) Hz | smooth \(smoothingWindowSamples) | threshold \(MoreK20ChannelCandidate.format(thresholdStddevMultiplier)) | \(matchedSegmentCount)/\(usableSegmentCount) matched | \(percent)% within | \(error) | \(rr) | \(rrReference) | \(rmssd) | \(intervals)"
  }

  init(row: [String: Any]) {
    rank = MoreStreamProbeStep.intValueForDelta(row["rank"])
    channelId = MoreDataStore.firstString(row, keys: ["channel_id"]) ?? "k20_waveform"
    offset = MoreStreamProbeStep.intValueForDelta(row["offset"])
    polarity = MoreDataStore.firstString(row, keys: ["polarity"]) ?? "unknown"
    sampleRateHz = MoreStreamProbeStep.doubleValueForDelta(row["sample_rate_hz"])
    minPeakSpacingSamples = MoreStreamProbeStep.intValueForDelta(row["min_peak_spacing_samples"])
    smoothingWindowSamples = MoreStreamProbeStep.intValueForDelta(row["smoothing_window_samples"])
    thresholdStddevMultiplier = MoreStreamProbeStep.doubleValueForDelta(row["threshold_stddev_multiplier"])
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

  func runK20WaveformTransformScan() {
    guard streamProbeWindowIssueSummary() == nil else {
      k20WaveformScanStatus = streamProbeWindowIssueSummary() ?? "Window blocked"
      return
    }

    k20WaveformScanInProgress = true
    k20WaveformScanStatus = "Sweeping K20 waveform transforms..."
    k20WaveformCandidates = []
    k20WaveformNextActions = []
    let databasePath = databasePath
    let start = streamProbeStart
    let end = streamProbeEnd
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "metrics.k20_waveform_transform_scan",
        args: [
          "database_path": databasePath,
          "start": start,
          "end": end,
          "min_owned_captures": 1,
          "max_hr_match_lag_seconds": 10.0,
          "hr_tolerance_bpm": 8.0,
          "min_matching_segments": 2,
          "max_ranked_transforms": 12,
          "max_segment_summaries": 8,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      k20WaveformScanInProgress = false
      switch result {
      case .success(let value):
        applyK20WaveformTransformScan(value)
      case .failure(let error):
        k20WaveformScanStatus = "K20 waveform scan failed: \(Self.errorSummary(error))"
      }
    }
  }

  func runBeatEvidenceReport() {
    guard streamProbeWindowIssueSummary() == nil else {
      beatEvidenceStatus = streamProbeWindowIssueSummary() ?? "Window blocked"
      return
    }

    beatEvidenceInProgress = true
    beatEvidenceStatus = "Building beat evidence report..."
    beatEvidenceNextActions = []
    let databasePath = databasePath
    let expected = streamProbeExpectedPacketFamilies.isEmpty ? Self.defaultStreamProbeExpectedPacketFamilies : streamProbeExpectedPacketFamilies
    var args: [String: Any] = [
      "database_path": databasePath,
      "start": streamProbeStart,
      "end": streamProbeEnd,
      "expected_packet_families": expected,
      "capture_session_ids": Self.csvValues(streamProbeCaptureSessions),
      "min_owned_captures": 1,
      "max_hr_match_lag_seconds": 10.0,
      "hr_tolerance_bpm": 8.0,
      "min_matching_segments": 2,
      "min_matching_frames": 20,
      "max_ranked_transforms": 12,
      "max_ranked_channels": 8,
      "max_ranked_fields": 12,
      "max_ranked_candidates": 12,
      "max_segment_summaries": 8,
      "max_frame_summaries": 8,
      "max_analyzed_frames": 600,
    ]
    if !streamProbeBaselineStart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !streamProbeBaselineEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      args["baseline_start"] = streamProbeBaselineStart
      args["baseline_end"] = streamProbeBaselineEnd
    }

    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "metrics.beat_evidence_report",
        args: args
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      beatEvidenceInProgress = false
      switch result {
      case .success(let value):
        applyBeatEvidenceReport(value)
      case .failure(let error):
        beatEvidenceStatus = "Beat evidence failed: \(Self.errorSummary(error))"
      }
    }
  }

  func runK18ExportReadinessCheck(completion: ((Bool) -> Void)? = nil) {
    guard streamProbeWindowIssueSummary() == nil else {
      k18ExportReadinessStatus = streamProbeWindowIssueSummary() ?? "Window blocked"
      k18ExportReadinessIssues = ["stream_probe_window_invalid"]
      k18ExportReadinessLatestLagSeconds = nil
      completion?(false)
      return
    }

    k18ExportReadinessInProgress = true
    k18ExportReadinessStatus = "Checking K18 catch-up..."
    k18ExportReadinessNextActions = []
    k18ExportReadinessIssues = []
    k18ExportReadinessLatestLagSeconds = nil
    let databasePath = databasePath
    let start = streamProbeStart
    let end = streamProbeEnd
    let observedEnd = Date().moreISO8601String()
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "metrics.k18_export_readiness",
        args: [
          "database_path": databasePath,
          "start": start,
          "end": end,
          "observed_end": observedEnd,
          "catch_up_grace_seconds": 30,
          "min_k18_rr_frames": 10,
          "min_k18_rr_intervals": 10,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      k18ExportReadinessInProgress = false
      switch result {
      case .success(let value):
        applyK18ExportReadiness(value)
        completion?((value["pass"] as? Bool) == true)
      case .failure(let error):
        k18ExportReadinessStatus = "K18 readiness failed: \(Self.errorSummary(error))"
        k18ExportReadinessIssues = ["bridge_request_failed"]
        k18ExportReadinessLatestLagSeconds = nil
        completion?(false)
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

  private func applyK20WaveformTransformScan(_ value: [String: Any]) {
    let candidates = value["ranked_transforms"] as? [[String: Any]] ?? []
    k20WaveformCandidates = candidates.map(MoreK20WaveformCandidate.init(row:))
    let nextActions = value["next_actions"] as? [[String: Any]] ?? []
    k20WaveformNextActions = nextActions.map { row in
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
    let transforms = Self.firstString(value, keys: ["tested_transform_count"]) ?? "0"
    let pass = (value["pass"] as? Bool) == true
    k20WaveformScanStatus = "\(status) | K20 \(k20Frames) | realtime \(realtimeFrames) | transforms \(transforms) | HR \(matched) | RR ref \(rrMatched)/\(rrSamples) | \(pass ? "passed" : "blocked")"
  }

  private func applyBeatEvidenceReport(_ value: [String: Any]) {
    let nextActions = value["next_actions"] as? [[String: Any]] ?? []
    beatEvidenceNextActions = nextActions.map { row in
      let reason = Self.firstString(row, keys: ["reason"]) ?? "next_action"
      let action = Self.firstString(row, keys: ["action"]) ?? Self.shortBridgeSummary(row)
      return "\(reason): \(action)"
    }
    if let waveform = value["k20_waveform_transform_scan"] as? [String: Any] {
      applyK20WaveformTransformScan(waveform)
    }
    if let channel = value["k20_optical_channel_scan"] as? [String: Any] {
      applyK20ChannelScan(channel)
    }
    if let packetDelta = value["packet_delta"] as? [String: Any] {
      applyStreamProbeDelta(packetDelta)
    }
    let status = Self.firstString(value, keys: ["validation_status"]) ?? "unknown"
    let rrSamples = Self.firstString(value, keys: ["rr_reference_sample_count"]) ?? "0"
    let pass = (value["pass"] as? Bool) == true
    let summary = value["summary"] as? [String: Any] ?? [:]
    let k20Frames = Self.firstString(summary, keys: ["k20_frame_count"]) ?? "0"
    let k26Frames = Self.firstString(summary, keys: ["k26_frame_count"]) ?? "0"
    beatEvidenceStatus = "\(status) | K20 \(k20Frames) | K26 \(k26Frames) | RR ref \(rrSamples) | \(pass ? "passed" : "blocked")"
  }

  private func applyK18ExportReadiness(_ value: [String: Any]) {
    k18ExportReadinessIssues = Self.stringArray(value["issues"])
    k18ExportReadinessLatestLagSeconds = Self.firstInt(
      value,
      keys: [
        "latest_quality_gated_k18_rr_sample_lag_seconds",
        "latest_k18_rr_sample_lag_seconds",
        "latest_k18_sample_lag_seconds",
      ]
    )

    let nextActions = value["next_actions"] as? [[String: Any]] ?? []
    k18ExportReadinessNextActions = nextActions.map { row in
      let reason = Self.firstString(row, keys: ["reason"]) ?? "next_action"
      let action = Self.firstString(row, keys: ["action"]) ?? Self.shortBridgeSummary(row)
      return "\(reason): \(action)"
    }

    let status = Self.firstString(value, keys: ["readiness_status"]) ?? "unknown"
    let pass = (value["pass"] as? Bool) == true
    let target = Self.firstString(value, keys: ["target_time"]) ?? "target --"
    let latest = Self.firstString(value, keys: ["latest_quality_gated_k18_rr_sample_time"])
      ?? Self.firstString(value, keys: ["latest_k18_rr_sample_time"])
      ?? "K18 RR --"
    let lag = Self.firstString(value, keys: ["latest_quality_gated_k18_rr_sample_lag_seconds"])
      ?? Self.firstString(value, keys: ["latest_k18_rr_sample_lag_seconds"])
      ?? "--"
    let rrFrames = Self.firstString(value, keys: ["quality_gated_k18_rr_frame_count"]) ?? "0"
    let rrIntervals = Self.firstString(value, keys: ["quality_gated_k18_rr_interval_count"]) ?? "0"
    let rrReference = Self.firstString(value, keys: ["rr_reference_sample_count"]) ?? "0"
    let label = pass ? "Ready to export" : status.replacingOccurrences(of: "_", with: " ")
    k18ExportReadinessStatus = "\(label) | K18 RR \(latest) | target \(target) | lag \(lag)s | gated \(rrFrames)/\(rrIntervals) | RR ref \(rrReference)"
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

  private static func firstInt(_ dictionary: [String: Any], keys: [String]) -> Int? {
    for key in keys {
      if let value = dictionary[key],
         let intValue = intValue(value) {
        return intValue
      }
    }
    return nil
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
      return value
    }
    if let value = value as? NSNumber {
      return value.intValue
    }
    if let value = value as? String {
      return Int(value)
    }
    return nil
  }

  static let automaticStreamProbeDuration: TimeInterval = 15 * 60
  static let automaticStreamProbeWindowPadding: TimeInterval = 30
  static let automaticStreamProbeStartRetryDelay: TimeInterval = 1
  static let automaticStreamProbeK18CatchUpBaseTimeout: TimeInterval = 10 * 60
  static let automaticStreamProbeK18CatchUpExtendedTimeout: TimeInterval = 25 * 60
  static let automaticStreamProbeK18CatchUpPollDelay: TimeInterval = 15
  static let automaticStreamProbeBandCaptureFailSafePadding: TimeInterval = 60
  static var automaticStreamProbeBandCaptureFailSafeDuration: TimeInterval {
    automaticStreamProbeDuration
      + automaticStreamProbeK18CatchUpExtendedTimeout
      + automaticStreamProbeBandCaptureFailSafePadding
  }
  static let guidedReferenceProbePollDelay: TimeInterval = 1
  static let guidedReferenceProbeTimeout: TimeInterval = 90

  func startGuidedReferenceProbe(model: OpenVitalsAppModel) {
    guard !guidedReferenceProbeInProgress else {
      guidedReferenceProbeStatus = "Guided reference probe already starting"
      return
    }
    guard !automaticStreamProbeInProgress else {
      guidedReferenceProbeStatus = "Automatic probe is already running"
      return
    }
    guard model.ble.connectionState == "ready" else {
      guidedReferenceProbeStatus = "Connect the band first. Current state: \(model.ble.connectionState)"
      return
    }

    guidedReferenceProbeWorkItem?.cancel()
    guidedReferenceProbeWorkItem = nil
    guidedReferenceProbeInProgress = true
    guidedReferenceProbeStatus = "Starting RR reference, then automatic probe..."
    if !rrReferenceCapture.isCapturing, !rrReferenceCapture.isScanning {
      rrReferenceCapture.startScanning()
    }
    advanceGuidedReferenceProbe(model: model, startedAt: Date())
  }

  func cancelGuidedReferenceProbe() {
    guidedReferenceProbeWorkItem?.cancel()
    guidedReferenceProbeWorkItem = nil
    guidedReferenceProbeInProgress = false
    guidedReferenceProbeStatus = "Guided reference probe canceled"
    if rrReferenceCapture.isScanning, !rrReferenceCapture.isCapturing {
      rrReferenceCapture.stopScanning()
    }
  }

  private func advanceGuidedReferenceProbe(model: OpenVitalsAppModel, startedAt: Date) {
    guard guidedReferenceProbeInProgress else {
      return
    }
    guard model.ble.connectionState == "ready" else {
      guidedReferenceProbeInProgress = false
      guidedReferenceProbeStatus = "Band disconnected before probe start. Current state: \(model.ble.connectionState)"
      return
    }
    guard !automaticStreamProbeInProgress else {
      guidedReferenceProbeInProgress = false
      guidedReferenceProbeStatus = "RR reference ready; automatic probe is running"
      return
    }

    if rrReferenceCapture.hasLiveRRSamples {
      guidedReferenceProbeInProgress = false
      guidedReferenceProbeWorkItem = nil
      guidedReferenceProbeStatus = "RR reference ready with \(rrReferenceCapture.sampleCount) samples. Starting automatic probe."
      startAutomaticStreamProbe(model: model)
      return
    }

    let elapsed = Date().timeIntervalSince(startedAt)
    if elapsed > Self.guidedReferenceProbeTimeout {
      guidedReferenceProbeInProgress = false
      guidedReferenceProbeStatus = "No RR samples yet. Check strap contact, then use Start Automatic Probe once RR samples appear."
      return
    }

    if rrReferenceCapture.isCapturing {
      guidedReferenceProbeStatus = "Waiting for RR samples from \(rrReferenceCapture.activeDeviceName)..."
    } else if !rrReferenceCapture.discoveredDevices.isEmpty {
      let deviceName = rrReferenceCapture.discoveredDevices.first?.name ?? "reference device"
      guidedReferenceProbeStatus = "Connecting to \(deviceName)..."
      _ = rrReferenceCapture.startCaptureFromBestDevice()
    } else {
      guidedReferenceProbeStatus = rrReferenceCapture.isScanning
        ? "Scanning for RR reference device..."
        : "Starting RR reference scan..."
      if !rrReferenceCapture.isScanning {
        rrReferenceCapture.startScanning()
      }
    }

    let workItem = DispatchWorkItem { [weak self, weak model] in
      guard let self, let model else {
        return
      }
      self.advanceGuidedReferenceProbe(model: model, startedAt: startedAt)
    }
    guidedReferenceProbeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.guidedReferenceProbePollDelay, execute: workItem)
  }

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
    automaticStreamProbeCatchUpWorkItem?.cancel()
    automaticStreamProbeCatchUpWorkItem = nil
    guidedReferenceProbeWorkItem?.cancel()
    guidedReferenceProbeWorkItem = nil
    guidedReferenceProbeInProgress = false
    automaticStreamProbeInProgress = true
    automaticStreamProbeStartedAt = nil
    model.cancelPendingPassiveActivityCapture(reason: "stream_probe_auto_start")
    automaticStreamProbeStatus = "Starting diagnostic packet capture..."
    streamProbeBaselineStart = ""
    streamProbeBaselineEnd = ""
    streamProbeCaptureSessions = ""
    streamProbePacketDeltas = []
    streamProbeNextActions = []
    k20ChannelCandidates = []
    k20ChannelNextActions = []
    k20WaveformCandidates = []
    k20WaveformNextActions = []
    beatEvidenceNextActions = []
    k18ExportReadinessNextActions = []
    k18ExportReadinessStatus = "K18 export readiness not checked"
    k20WaveformScanStatus = "No K20 waveform transform scan"
    beatEvidenceStatus = "No beat evidence report"
    localExportURL = nil
    localExportManifestURL = nil
    k18ExportReadinessIssues = []
    k18ExportReadinessLatestLagSeconds = nil

    refreshStreamProbePlan()

    continueAutomaticStreamProbeStart(model: model)
  }

  private func continueAutomaticStreamProbeStart(model: OpenVitalsAppModel) {
    guard automaticStreamProbeInProgress else {
      return
    }

    if model.healthPacketCaptureStartInProgress {
      automaticStreamProbeStatus = "Waiting for the current capture start to finish..."
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.automaticStreamProbeStartRetryDelay) { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        self.continueAutomaticStreamProbeStart(model: model)
      }
      return
    }

    if model.healthPacketCaptureSessionID != nil {
      automaticStreamProbeStatus = "Stopping existing packet capture before starting automatic probe..."
      model.stopHealthPacketCapture(reason: "stream_probe_auto_replace_existing_capture") { [weak self, weak model] stopped in
        guard let self, let model else {
          return
        }
        guard stopped else {
          self.automaticStreamProbeInProgress = false
          self.automaticStreamProbeStatus = "Could not stop the existing capture: \(model.healthPacketCaptureStatus)"
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
      duration: Self.automaticStreamProbeBandCaptureFailSafeDuration,
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
      if let sessionID = model.healthPacketCaptureSessionID {
        self.streamProbeCaptureSessions = sessionID
        self.rawCaptureSessions = sessionID
      }
      self.streamProbeStart = startedAt.addingTimeInterval(-Self.automaticStreamProbeWindowPadding).moreISO8601String()
      self.streamProbeEnd = startedAt.addingTimeInterval(Self.automaticStreamProbeDuration + Self.automaticStreamProbeWindowPadding).moreISO8601String()
      self.rawExportStart = self.streamProbeStart
      self.rawExportEnd = self.streamProbeEnd
      self.automaticStreamProbeStatus = "Capturing \(Self.automaticProbeDurationText) probe window. Band capture can stay open afterward for K18 catch-up."

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
    automaticStreamProbeCatchUpWorkItem?.cancel()
    automaticStreamProbeCatchUpWorkItem = nil

    guard automaticStreamProbeInProgress else {
      automaticStreamProbeStatus = "No automatic stream probe is running"
      return
    }

    if reason == "timer elapsed" {
      finishAutomaticStreamProbeReferenceWindow(model: model)
      return
    }

    stopAutomaticStreamProbeBandCapture(
      model: model,
      reason: reason,
      finalStatus: "Probe stopped. Ready to create export bundle."
    )
  }

  private func finishAutomaticStreamProbeReferenceWindow(model: OpenVitalsAppModel) {
    let endedAt = Date()
    if automaticStreamProbeStartedAt == nil {
      automaticStreamProbeStartedAt = endedAt
      streamProbeStart = endedAt.addingTimeInterval(-Self.automaticStreamProbeDuration - Self.automaticStreamProbeWindowPadding).moreISO8601String()
    }
    streamProbeEnd = endedAt.moreISO8601String()
    rawExportStart = streamProbeStart
    rawExportEnd = streamProbeEnd
    refreshRecentCaptureSessions()

    if rrReferenceCapture.isCapturing {
      automaticStreamProbeStatus = "Probe window complete. Stopping RR reference and keeping band capture open for K18 catch-up..."
      rrReferenceCapture.stopCapture()
      waitForReferenceStorageBeforeExport(startedAt: Date()) { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        self.continueAutomaticStreamProbeK18CatchUp(model: model, startedAt: Date())
      }
    } else if rrReferenceCapture.sampleCount > 0 && !rrReferenceCapture.storageReadyForExport {
      automaticStreamProbeStatus = "Probe window complete. Waiting for RR storage before K18 catch-up..."
      waitForReferenceStorageBeforeExport(startedAt: Date()) { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        self.continueAutomaticStreamProbeK18CatchUp(model: model, startedAt: Date())
      }
    } else {
      automaticStreamProbeStatus = "Probe window complete. Keeping band capture open for K18 catch-up..."
      continueAutomaticStreamProbeK18CatchUp(model: model, startedAt: Date())
    }
  }

  private func continueAutomaticStreamProbeK18CatchUp(model: OpenVitalsAppModel, startedAt: Date) {
    guard automaticStreamProbeInProgress else {
      return
    }
    guard model.healthPacketCaptureSessionID != nil else {
      automaticStreamProbeInProgress = false
      automaticStreamProbeStatus = "Band capture already stopped. Ready to create export bundle."
      return
    }
    let elapsed = Date().timeIntervalSince(startedAt)
    let timeout = automaticStreamProbeK18CatchUpTimeoutForCurrentReadiness()
    if elapsed > timeout {
      let timeoutMinutes = Int((timeout / 60).rounded())
      stopAutomaticStreamProbeBandCapture(
        model: model,
        reason: "k18_catch_up_timeout",
        finalStatus: "K18 catch-up timed out after \(timeoutMinutes) min. Export is available with readiness warning.",
        updateProbeWindowEnd: false
      )
      return
    }

    automaticStreamProbeStatus = "Checking K18 catch-up while band capture stays open..."
    runK18ExportReadinessCheck { [weak self, weak model] ready in
      guard let self, let model else {
        return
      }
      guard self.automaticStreamProbeInProgress else {
        return
      }
      if ready {
        self.stopAutomaticStreamProbeBandCapture(
          model: model,
          reason: "k18_catch_up_ready",
          finalStatus: "K18 caught up. Ready to create export bundle.",
          updateProbeWindowEnd: false
        )
        return
      }

      let nextTimeout = self.automaticStreamProbeK18CatchUpTimeoutForCurrentReadiness()
      let remaining = max(0, nextTimeout - Date().timeIntervalSince(startedAt))
      let waitText = self.automaticStreamProbeK18WaitText(remaining)
      self.automaticStreamProbeStatus = "K18 catch-up pending. \(self.k18ExportReadinessStatus) \(waitText)"
      let workItem = DispatchWorkItem { [weak self, weak model] in
        guard let self, let model else {
          return
        }
        self.continueAutomaticStreamProbeK18CatchUp(model: model, startedAt: startedAt)
      }
      self.automaticStreamProbeCatchUpWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.automaticStreamProbeK18CatchUpPollDelay, execute: workItem)
    }
  }

  private func automaticStreamProbeK18CatchUpTimeoutForCurrentReadiness() -> TimeInterval {
    k18ExportReadinessCanContinueWaiting
      ? Self.automaticStreamProbeK18CatchUpExtendedTimeout
      : Self.automaticStreamProbeK18CatchUpBaseTimeout
  }

  private var k18ExportReadinessCanContinueWaiting: Bool {
    guard !k18ExportReadinessIssues.isEmpty else {
      return false
    }
    let waitableIssues: Set<String> = [
      "k18_sample_time_behind_target",
      "quality_gated_k18_rr_sample_time_behind_target",
      "not_enough_k18_rr_frames_observed",
      "not_enough_quality_gated_k18_rr_intervals_observed",
      "no_k18_frames_observed",
      "no_k18_sample_time_observed",
      "no_k18_rr_sample_time_observed",
      "no_quality_gated_k18_rr_sample_time_observed",
    ]
    return k18ExportReadinessIssues.allSatisfy { waitableIssues.contains($0) }
  }

  private func automaticStreamProbeK18WaitText(_ remaining: TimeInterval) -> String {
    let minutes = max(0, Int(ceil(remaining / 60)))
    if k18ExportReadinessCanContinueWaiting {
      return "Waiting up to \(minutes) more min because K18 evidence is still catching up."
    }
    return "Timing out in \(minutes) min if readiness stays blocked."
  }

  private func stopAutomaticStreamProbeBandCapture(
    model: OpenVitalsAppModel,
    reason: String,
    finalStatus: String,
    updateProbeWindowEnd: Bool = true
  ) {
    automaticStreamProbeCatchUpWorkItem?.cancel()
    automaticStreamProbeCatchUpWorkItem = nil
    automaticStreamProbeStatus = "Stopping band capture and preparing analysis..."
    model.stopHealthPacketCapture(reason: "stream_probe_auto_\(reason.replacingOccurrences(of: " ", with: "_"))") { [weak self, weak model] stopped in
      guard let self, let model else {
        return
      }
      let endedAt = Date()
      if self.automaticStreamProbeStartedAt == nil {
        self.automaticStreamProbeStartedAt = endedAt
        self.streamProbeStart = endedAt.addingTimeInterval(-Self.automaticStreamProbeDuration - Self.automaticStreamProbeWindowPadding).moreISO8601String()
      }
      if updateProbeWindowEnd {
        self.streamProbeEnd = endedAt.addingTimeInterval(Self.automaticStreamProbeWindowPadding).moreISO8601String()
      }
      self.rawExportStart = self.streamProbeStart
      self.rawExportEnd = endedAt.moreISO8601String()
      self.refreshRecentCaptureSessions()
      guard stopped else {
        self.automaticStreamProbeInProgress = false
        self.automaticStreamProbeStatus = "Could not stop capture: \(model.healthPacketCaptureStatus). Wait a few seconds, then start the automatic probe again."
        return
      }
      self.automaticStreamProbeInProgress = false
      if self.rrReferenceCapture.isCapturing {
        self.automaticStreamProbeStatus = "Probe stopped. Stopping RR reference and storing samples..."
        self.rrReferenceCapture.stopCapture()
        self.waitForReferenceStorageBeforeExport(startedAt: Date())
      } else if self.rrReferenceCapture.sampleCount > 0 && !self.rrReferenceCapture.storageReadyForExport {
        self.automaticStreamProbeStatus = "Probe stopped. Waiting for RR storage before export..."
        self.waitForReferenceStorageBeforeExport(startedAt: Date())
      } else {
        self.automaticStreamProbeStatus = finalStatus
      }
    }
  }

  private func waitForReferenceStorageBeforeExport(startedAt: Date, completion: (() -> Void)? = nil) {
    if rrReferenceCapture.storageReadyForExport {
      automaticStreamProbeStatus = completion == nil
        ? "RR samples stored. Ready to create export bundle."
        : "RR samples stored. Checking K18 catch-up..."
      completion?()
      return
    }
    if Date().timeIntervalSince(startedAt) > Self.guidedReferenceProbeTimeout {
      automaticStreamProbeStatus = "RR storage still not ready: \(rrReferenceCapture.lastFlushStatus). Wait or retry export after storage catches up."
      completion?()
      return
    }
    automaticStreamProbeStatus = "Waiting for RR storage: \(rrReferenceCapture.lastFlushStatus)"
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.guidedReferenceProbePollDelay) { [weak self] in
      self?.waitForReferenceStorageBeforeExport(startedAt: startedAt, completion: completion)
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
  @State private var clearDebugDataStopInProgress = false

  var body: some View {
    List {
      Section("Automatic Probe") {
        MoreActionRow(
          title: store.guidedReferenceProbeInProgress ? "Cancel RR + Probe Start" : "Start RR + Probe",
          detail: store.guidedReferenceProbeStatus,
          systemImage: store.guidedReferenceProbeInProgress ? "xmark.circle" : "waveform.path.ecg.rectangle",
          status: guidedProbeStatus,
          disabled: guidedProbeDisabled
        ) {
          if store.guidedReferenceProbeInProgress {
            store.cancelGuidedReferenceProbe()
          } else {
            store.startGuidedReferenceProbe(model: model)
          }
        }
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
        MoreActionRow(
          title: "Check K18 Export Readiness",
          detail: store.k18ExportReadinessStatus,
          systemImage: "clock.badge.checkmark",
          status: k18ReadinessStatus,
          disabled: k18ReadinessDisabled
        ) {
          store.runK18ExportReadinessCheck()
        }
        MoreActionRow(
          title: "Create Export Bundle",
          detail: exportBundleDetail,
          systemImage: "externaldrive.badge.plus",
          status: exportBundleStatus,
          disabled: exportBundleDisabled
        ) {
          store.saveLocalDataBundle()
        }
        MoreActionRow(
          title: "Clear Debug Data",
          detail: clearDebugDataDetail,
          systemImage: "trash",
          status: clearDebugDataStatus,
          disabled: clearDebugDataDisabled
        ) {
          clearDebugData()
        }
        if store.automaticStreamProbeInProgress {
          ProgressView(store.automaticStreamProbeStatus)
        }
        if store.debugDataClearInProgress {
          ProgressView(store.debugDataClearStatus)
        }
        if store.k18ExportReadinessInProgress {
          ProgressView(store.k18ExportReadinessStatus)
        }
        if store.localExportInProgress {
          MoreLocalExportProgressView(
            progress: store.localExportProgress,
            fallback: store.localExportStatus
          )
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

      Section("Bedtime Export") {
        MoreInfoRow(
          title: "Guard",
          value: model.overnightGuardStatus,
          systemImage: "moon",
          status: bedtimeGuardStatus
        )
        MoreInfoRow(
          title: "Readiness",
          value: model.overnightGuardReadinessSummary,
          systemImage: "bed.double",
          status: bedtimeReadinessStatus
        )
        MoreInfoRow(
          title: "Targets",
          value: model.overnightGuardTargetSummary,
          systemImage: "scope",
          status: bedtimeTargetStatus
        )
        MoreInfoRow(
          title: "Spool",
          value: "\(model.overnightGuardSpoolSizeSummary) | \(model.overnightGuardSpoolPath)",
          systemImage: "folder",
          status: model.overnightGuardSpoolPath == "No overnight spool" ? .pending : .ready
        )
        MoreInfoRow(
          title: "Final Export",
          value: model.overnightGuardExportStatus,
          systemImage: "square.and.arrow.up",
          status: bedtimeExportStatus
        )
        MoreActionRow(
          title: "Start Bedtime Guard",
          detail: bedtimeStartDetail,
          systemImage: "moon.stars",
          status: bedtimeStartStatus,
          disabled: bedtimeStartDisabled
        ) {
          model.startLeanOvernightGuard()
        }
        MoreActionRow(
          title: "Final Sync + Export",
          detail: bedtimeFinalSyncDetail,
          systemImage: "arrow.triangle.2.circlepath",
          status: bedtimeFinalSyncStatus,
          disabled: bedtimeFinalSyncDisabled
        ) {
          model.requestOvernightGuardFinalSync()
        }
        if model.overnightGuardCanExportLastSession {
          MoreActionRow(
            title: "Export Last Bedtime Guard",
            detail: bedtimeExportLastDetail,
            systemImage: "externaldrive.badge.plus",
            status: bedtimeExportStatus,
            disabled: bedtimeExportLastDisabled
          ) {
            model.exportLastOvernightGuardBundle()
          }
        }
        MoreActionRow(
          title: "Stop Bedtime Guard",
          detail: "Stops collection without final sync. Use only when you do not want the morning historical drain.",
          systemImage: "stop.circle",
          status: model.overnightGuardActive ? .stale : .notRun,
          disabled: !model.overnightGuardActive || model.overnightGuardExportInProgress
        ) {
          model.stopOvernightGuard()
        }
        if model.overnightGuardExportInProgress {
          ProgressView("Saving bedtime bundle")
        }
        if let exportURL = model.overnightGuardExportURL {
          ShareLink(item: exportURL) {
            Label("AirDrop Bedtime Bundle", systemImage: "square.and.arrow.up")
          }
        }
        if let exportManifestURL = model.overnightGuardExportManifestURL {
          ShareLink(item: exportManifestURL) {
            Label("AirDrop Bedtime Manifest", systemImage: "list.bullet.rectangle")
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

      Section("Beat Evidence") {
        MoreActionRow(
          title: "Run Beat Evidence Report",
          detail: store.beatEvidenceStatus,
          systemImage: "heart.text.square",
          status: beatEvidenceStatus,
          disabled: store.beatEvidenceInProgress || store.streamProbeWindowIssueSummary() != nil
        ) {
          store.runBeatEvidenceReport()
        }
        if store.beatEvidenceInProgress {
          ProgressView(store.beatEvidenceStatus)
        }
        MoreInfoRow(
          title: "Status",
          value: store.beatEvidenceStatus,
          systemImage: "heart.text.square",
          status: beatEvidenceStatus
        )
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

      Section("K20 Waveform Transform") {
        MoreActionRow(
          title: "Run K20 Waveform Transform Scan",
          detail: store.k20WaveformScanStatus,
          systemImage: "waveform.path.ecg",
          status: k20WaveformStatus,
          disabled: store.k20WaveformScanInProgress || store.streamProbeWindowIssueSummary() != nil
        ) {
          store.runK20WaveformTransformScan()
        }
        if store.k20WaveformScanInProgress {
          ProgressView(store.k20WaveformScanStatus)
        }
        MoreInfoRow(
          title: "Status",
          value: store.k20WaveformScanStatus,
          systemImage: "waveform.path.ecg",
          status: k20WaveformStatus
        )
        if store.k20WaveformCandidates.isEmpty {
          MoreInfoRow(
            title: "Transforms",
            value: "Run K20 waveform transform scan",
            systemImage: "chart.xyaxis.line",
            status: .notRun
          )
        } else {
          ForEach(store.k20WaveformCandidates.prefix(8)) { candidate in
            MoreInfoRow(
              title: "\(candidate.rank). offset \(candidate.offset)",
              value: candidate.detail,
              systemImage: "waveform.path.ecg",
              status: candidate.status
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

      if !store.beatEvidenceNextActions.isEmpty || !store.k20WaveformNextActions.isEmpty || !store.k20ChannelNextActions.isEmpty || !store.k18ExportReadinessNextActions.isEmpty {
        Section("Beat Evidence Next Actions") {
          ForEach((store.beatEvidenceNextActions + store.k20WaveformNextActions + store.k20ChannelNextActions + store.k18ExportReadinessNextActions).prefix(8), id: \.self) { action in
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
    if store.localExportInProgress || store.streamProbeDeltaInProgress || store.k20ChannelScanInProgress || store.k20WaveformScanInProgress || store.beatEvidenceInProgress || store.k18ExportReadinessInProgress {
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

  private var bedtimeGuardStatus: MoreStatusKind {
    if model.overnightGuardActive {
      return .listening
    }
    if model.overnightGuardExportURL != nil {
      return .ready
    }
    if model.overnightGuardCanExportLastSession {
      return .pending
    }
    if model.overnightGuardStatus.localizedCaseInsensitiveContains("failed")
      || model.overnightGuardStatus.localizedCaseInsensitiveContains("blocked") {
      return .blocked
    }
    if model.ble.connectionState != "ready" {
      return .blocked
    }
    return .notRun
  }

  private var bedtimeReadinessStatus: MoreStatusKind {
    switch model.overnightGuardReadinessStatus {
    case "ready":
      return .ready
    case "blocked":
      return .blocked
    case "unavailable":
      return .unavailable
    case "stale":
      return .stale
    default:
      return .pending
    }
  }

  private var bedtimeTargetStatus: MoreStatusKind {
    model.overnightGuardTargetSummary.contains("K18 0 | K24 0 | K25 0 | K26 0 | packet47 0 | event17 0 | event29 0 | metadata49 0 | metadata56 0") ? .pending : .ready
  }

  private var bedtimeExportStatus: MoreStatusKind {
    if model.overnightGuardExportInProgress {
      return .inProgress
    }
    if model.overnightGuardExportStatus.localizedCaseInsensitiveContains("failed")
      || model.overnightGuardExportStatus.localizedCaseInsensitiveContains("issue")
      || model.overnightGuardExportStatus.localizedCaseInsensitiveContains("missing") {
      return .stale
    }
    return model.overnightGuardExportURL == nil ? .pending : .ready
  }

  private var bedtimeStartStatus: MoreStatusKind {
    if model.overnightGuardActive {
      return .listening
    }
    if bedtimeStartDisabled {
      return .blocked
    }
    return .ready
  }

  private var bedtimeStartDisabled: Bool {
    model.overnightGuardActive
      || model.ble.connectionState != "ready"
      || store.automaticStreamProbeInProgress
      || store.guidedReferenceProbeInProgress
      || store.localExportInProgress
      || model.overnightGuardExportInProgress
  }

  private var bedtimeStartDetail: String {
    if model.overnightGuardActive {
      return "Guard is recording. In the morning, run Final Sync + Export before opening other device apps."
    }
    if model.ble.connectionState != "ready" {
      return "Connect the device before starting bedtime collection."
    }
    if store.automaticStreamProbeInProgress || store.guidedReferenceProbeInProgress {
      return "Wait for the active probe to finish before starting bedtime collection."
    }
    if store.localExportInProgress || model.overnightGuardExportInProgress {
      return "Wait for the current export to finish before starting bedtime collection."
    }
    return "Starts the lean guard for tonight: raw spool, range polls, watchdog, and final sync/export without the heavy decoded packet capture."
  }

  private var bedtimeFinalSyncStatus: MoreStatusKind {
    if model.overnightGuardExportInProgress {
      return .inProgress
    }
    if !model.overnightGuardActive {
      return model.overnightGuardExportURL == nil ? .notRun : .ready
    }
    return model.ble.canSyncHistorical ? .ready : .blocked
  }

  private var bedtimeFinalSyncDisabled: Bool {
    !model.overnightGuardActive
      || model.ble.isHistoricalSyncing
      || !model.ble.canSyncHistorical
      || model.overnightGuardExportInProgress
      || store.localExportInProgress
  }

  private var bedtimeFinalSyncDetail: String {
    if model.overnightGuardExportInProgress {
      return model.overnightGuardExportStatus
    }
    if model.overnightGuardActive {
      if model.ble.isHistoricalSyncing {
        return "Historical sync is already running. Keep the app open until the final bundle appears."
      }
      if !model.ble.canSyncHistorical {
        return "Final sync blocked: \(model.ble.historicalSyncStatus)"
      }
      return "Morning action: pauses live capture, drains historical data, then creates the bedtime-scoped bundle."
    }
    if model.overnightGuardExportURL != nil {
      return "Bundle ready. Share the bedtime bundle and manifest below."
    }
    if model.overnightGuardCanExportLastSession {
      return "Guard is stopped. Use Export Last Bedtime Guard to package the stored evidence."
    }
    return "Available while Bedtime Guard is recording."
  }

  private var bedtimeExportLastDisabled: Bool {
    model.overnightGuardActive
      || model.overnightGuardExportInProgress
      || store.localExportInProgress
      || !model.overnightGuardCanExportLastSession
  }

  private var bedtimeExportLastDetail: String {
    if model.overnightGuardExportInProgress {
      return model.overnightGuardExportStatus
    }
    if model.overnightGuardActive {
      return "Run Final Sync + Export while the guard is active."
    }
    if model.overnightGuardExportURL != nil {
      return "Rebuilds the latest bedtime-scoped bundle if you need a fresh share file."
    }
    return "Packages the latest stopped or recovered bedtime guard session."
  }

  private var guidedProbeStatus: MoreStatusKind {
    if store.guidedReferenceProbeInProgress {
      return .inProgress
    }
    if store.guidedReferenceProbeStatus.localizedCaseInsensitiveContains("ready")
      || store.rrReferenceCapture.hasLiveRRSamples {
      return .ready
    }
    if store.guidedReferenceProbeStatus.localizedCaseInsensitiveContains("connect the band")
      || store.guidedReferenceProbeStatus.localizedCaseInsensitiveContains("disconnected")
      || store.guidedReferenceProbeStatus.localizedCaseInsensitiveContains("no rr samples") {
      return .blocked
    }
    return .notRun
  }

  private var guidedProbeDisabled: Bool {
    if store.guidedReferenceProbeInProgress {
      return false
    }
    return store.automaticStreamProbeInProgress
      || store.localExportInProgress
      || model.ble.connectionState != "ready"
  }

  private var exportBundleDetail: String {
    if store.localExportInProgress {
      return store.localExportStatus
    }
    if store.k18ExportReadinessInProgress {
      return store.k18ExportReadinessStatus
    }
    if store.automaticStreamProbeInProgress || store.guidedReferenceProbeInProgress {
      return "Wait for the probe to finish before exporting."
    }
    if k18ReadinessShouldWait {
      return "\(store.k18ExportReadinessStatus) Export is still available for captured evidence."
    }
    if store.rrReferenceCapture.sampleCount > 0 && !store.rrReferenceCapture.storageReadyForExport {
      return "Wait for RR storage: \(store.rrReferenceCapture.lastFlushStatus)"
    }
    if store.localExportURL != nil {
      return "Bundle ready. Share the local data file and manifest below."
    }
    return "Creates the local bundle that includes band packets and stored RR reference samples."
  }

  private var exportBundleStatus: MoreStatusKind {
    if store.localExportInProgress {
      return .inProgress
    }
    if store.k18ExportReadinessInProgress {
      return .inProgress
    }
    if store.localExportURL != nil {
      return .ready
    }
    if store.automaticStreamProbeInProgress || store.guidedReferenceProbeInProgress || k18ReadinessShouldWait {
      return .waiting
    }
    if store.rrReferenceCapture.sampleCount > 0 && !store.rrReferenceCapture.storageReadyForExport {
      return .waiting
    }
    return .pending
  }

  private var exportBundleDisabled: Bool {
    store.localExportInProgress
      || store.k18ExportReadinessInProgress
      || store.automaticStreamProbeInProgress
      || store.guidedReferenceProbeInProgress
      || (store.rrReferenceCapture.sampleCount > 0 && !store.rrReferenceCapture.storageReadyForExport)
  }

  private var k18ReadinessDisabled: Bool {
    store.k18ExportReadinessInProgress
      || store.localExportInProgress
      || store.automaticStreamProbeInProgress
      || store.guidedReferenceProbeInProgress
      || store.streamProbeWindowIssueSummary() != nil
  }

  private var k18ReadinessShouldWait: Bool {
    let status = store.k18ExportReadinessStatus
    return status.localizedCaseInsensitiveContains("waiting for k18 catch")
      || status.localizedCaseInsensitiveContains("k18 sample time behind")
      || status.localizedCaseInsensitiveContains("quality gated k18")
      || status.localizedCaseInsensitiveContains("no k18")
      || status.localizedCaseInsensitiveContains("not enough")
  }

  private var k18ReadinessStatus: MoreStatusKind {
    if store.k18ExportReadinessInProgress {
      return .inProgress
    }
    if store.k18ExportReadinessStatus.localizedCaseInsensitiveContains("ready to export") {
      return .ready
    }
    if k18ReadinessShouldWait {
      return .waiting
    }
    if store.k18ExportReadinessStatus.localizedCaseInsensitiveContains("failed")
      || store.k18ExportReadinessStatus.localizedCaseInsensitiveContains("blocked")
    {
      return .blocked
    }
    return .notRun
  }

  private var clearDebugDataDetail: String {
    if clearDebugDataStopInProgress {
      return store.debugDataClearStatus
    }
    if store.rrReferenceCapture.isCapturing {
      return "Stop RR reference capture before clearing stored debug data."
    }
    if store.rrReferenceCapture.sampleCount > 0 && !store.rrReferenceCapture.storageReadyForExport {
      return "Wait for RR storage: \(store.rrReferenceCapture.lastFlushStatus)"
    }
    if !store.canClearDeviceDebugData {
      return "Wait for probe, analysis, upload, or export work to finish."
    }
    if model.healthPacketCaptureSessionID != nil {
      return "Stops active health packet capture, then clears stored debug data."
    }
    return store.debugDataClearStatus
  }

  private var clearDebugDataDisabled: Bool {
    clearDebugDataStopInProgress
      || store.rrReferenceCapture.isCapturing
      || (store.rrReferenceCapture.sampleCount > 0 && !store.rrReferenceCapture.storageReadyForExport)
      || !store.canClearDeviceDebugData
  }

  private var clearDebugDataStatus: MoreStatusKind {
    if clearDebugDataStopInProgress {
      return .inProgress
    }
    if store.debugDataClearInProgress {
      return .inProgress
    }
    if clearDebugDataDisabled {
      return .blocked
    }
    if model.healthPacketCaptureSessionID != nil {
      return .pending
    }
    if store.debugDataClearStatus.localizedCaseInsensitiveContains("cleared") {
      return .ready
    }
    if store.debugDataClearStatus.localizedCaseInsensitiveContains("failed")
      || store.debugDataClearStatus.localizedCaseInsensitiveContains("blocked")
    {
      return .blocked
    }
    return .notRun
  }

  private func clearDebugData() {
    guard model.healthPacketCaptureSessionID != nil else {
      store.clearDeviceDebugData()
      return
    }

    clearDebugDataStopInProgress = true
    store.debugDataClearStatus = "Stopping health packet capture before clearing..."
    model.stopHealthPacketCapture(reason: "stream_probe_clear_debug_data") { stopped in
      clearDebugDataStopInProgress = false
      guard stopped else {
        store.debugDataClearStatus = "Clear blocked: \(model.healthPacketCaptureStatus)"
        return
      }
      store.clearDeviceDebugData()
    }
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
    if store.beatEvidenceInProgress {
      return store.beatEvidenceStatus
    }
    if store.k18ExportReadinessInProgress {
      return store.k18ExportReadinessStatus
    }
    if store.k20WaveformScanInProgress {
      return store.k20WaveformScanStatus
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

  private var k20WaveformStatus: MoreStatusKind {
    if store.k20WaveformScanInProgress {
      return .inProgress
    }
    if store.k20WaveformScanStatus.localizedCaseInsensitiveContains("passed") {
      return .ready
    }
    if store.k20WaveformScanStatus.localizedCaseInsensitiveContains("blocked")
      || store.k20WaveformScanStatus.localizedCaseInsensitiveContains("failed")
    {
      return .blocked
    }
    return store.k20WaveformCandidates.isEmpty ? .notRun : .stale
  }

  private var beatEvidenceStatus: MoreStatusKind {
    if store.beatEvidenceInProgress {
      return .inProgress
    }
    if store.beatEvidenceStatus.localizedCaseInsensitiveContains("passed") {
      return .ready
    }
    if store.beatEvidenceStatus.localizedCaseInsensitiveContains("blocked")
      || store.beatEvidenceStatus.localizedCaseInsensitiveContains("failed")
    {
      return .blocked
    }
    return store.beatEvidenceNextActions.isEmpty ? .notRun : .stale
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
