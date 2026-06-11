import SwiftUI

struct MoreDebugView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @EnvironmentObject private var packetMonitor: PacketMonitorModel
  @ObservedObject var healthStore: HealthDataStore
  @ObservedObject var store: MoreDataStore
  @AppStorage(OnboardingStorage.onboardingComplete) private var onboardingComplete = false
  @AppStorage(OnboardingStorage.onboardingRedoRequested) private var onboardingRedoRequested = false
  @State private var showDestructiveConfirmation = false
  @State private var showLocalDataWipeConfirmation = false

  var body: some View {
    List {
      Section("Rust And Parser") {
        MoreInfoRow(title: "Rust Bridge/Core", value: store.coreVersionStatus, systemImage: "shippingbox", status: rustBridgeStatus)
        MoreInfoRow(title: "Frame Parse", value: store.frameParseStatus, systemImage: "curlybraces.square", status: parserProbeStatus(store.frameParseStatus))
        MoreInfoRow(title: "CRC", value: store.frameCRCStatus, systemImage: "checkmark.seal", status: parserProbeStatus(store.frameCRCStatus))
        MoreInfoRow(title: "Payload", value: store.framePayloadStatus, systemImage: "doc.text.magnifyingglass", status: parserProbeStatus(store.framePayloadStatus))
        MoreInfoRow(title: "Warnings", value: store.frameWarningsStatus, systemImage: "exclamationmark.triangle", status: parserWarningStatus(store.frameWarningsStatus))
        MoreInfoRow(title: "Timeline", value: store.frameTimelineStatus, systemImage: "timeline.selection", status: parserProbeStatus(store.frameTimelineStatus))
        Button {
          store.runFrameParseProbe()
        } label: {
          Label("Run Parser Probe", systemImage: "play.circle")
        }
      }

      Section("Debug Session") {
        MoreInfoRow(title: "WebSocket", value: store.debugWebSocketStatus, systemImage: "network", status: debugSessionStatus(store.debugWebSocketStatus))
        MoreInfoRow(title: "Next Action", value: store.debugNextAction, systemImage: "arrow.forward.circle", status: debugSessionStatus(store.debugNextAction))
        Button {
          store.startDebugSession()
        } label: {
          Label("Start Debug Session", systemImage: "play.circle")
        }
        Button {
          store.refreshDebugSnapshot()
        } label: {
          Label("Refresh Snapshot", systemImage: "arrow.clockwise")
        }
      }

      Section("Health Packet Capture") {
        MoreInfoRow(
          title: "Connection",
          value: "\(model.ble.connectionState) | \(model.ble.activeDeviceName)",
          systemImage: "sensor.tag.radiowaves.forward",
          status: model.ble.connectionState == "ready" ? .ready : .blocked
        )
        MoreInfoRow(
          title: "Session",
          value: model.healthPacketCaptureStatus,
          systemImage: "record.circle",
          status: self.healthPacketCaptureStatus
        )
        MoreInfoRow(
          title: "Targets",
          value: model.healthPacketCaptureTargetSummary,
          systemImage: "scope",
          status: model.healthPacketCaptureFamilyRows.isEmpty ? healthPacketCaptureStatus : .ready
        )
        MoreInfoRow(
          title: "Last Packet",
          value: model.healthPacketCaptureLastPacketSummary,
          systemImage: "waveform.path.ecg.rectangle",
          status: model.healthPacketCaptureLastPacketSummary == "No packets captured" ? waitingOrNotRunForCapture : .ready
        )
        MoreInfoRow(
          title: "Live Data",
          value: packetMonitor.liveDeviceDataSummary,
          systemImage: "dot.radiowaves.left.and.right",
          status: packetMonitor.recentDeviceSignalPoints.isEmpty ? .waiting : .ready
        )
        MoreInfoRow(
          title: "Historical",
          value: "\(model.ble.historicalSyncStatus) | packets \(model.ble.historicalPacketCount)",
          systemImage: "arrow.triangle.2.circlepath",
          status: historicalSyncStatusKind
        )
        MoreInfoRow(
          title: "RR Watch",
          value: model.respiratoryPacketWatchStatus,
          systemImage: "lungs",
          status: self.respiratoryPacketWatchStatus
        )
        MoreActionRow(
          title: model.healthPacketCaptureSessionID == nil ? "Start Capture" : "Stop Capture",
          detail: model.healthPacketCaptureSessionID == nil ? "Collects movement, HR, optical/RR candidates, pulse, recovery sensor history, and metadata" : model.healthPacketCaptureTargetSummary,
          systemImage: model.healthPacketCaptureSessionID == nil ? "record.circle" : "stop.circle",
          status: self.healthPacketCaptureActionStatus,
          disabled: model.healthPacketCaptureSessionID == nil && model.ble.connectionState != "ready"
        ) {
          if model.healthPacketCaptureSessionID == nil {
            model.startDiagnosticPacketCapture()
          } else {
            model.stopHealthPacketCapture()
          }
        }
        MoreActionRow(
          title: model.respiratoryPacketWatchActive ? "Stop RR Packet Watch" : "Watch K18 RR Packets",
          detail: model.respiratoryPacketWatchStatus,
          systemImage: "lungs",
          status: self.respiratoryPacketWatchStatus,
          disabled: !model.respiratoryPacketWatchActive && model.ble.connectionState != "ready"
        ) {
          if model.respiratoryPacketWatchActive {
            model.stopRespiratoryPacketWatch()
          } else {
            model.startRespiratoryPacketWatch()
          }
        }
        if model.healthPacketCaptureFamilyRows.isEmpty {
          MoreInfoRow(
            title: "Families",
            value: "No decoded packet families in this capture yet",
            systemImage: "list.bullet.rectangle",
            status: waitingOrNotRunForCapture
          )
        } else {
          ForEach(model.healthPacketCaptureFamilyRows.prefix(10)) { family in
            MoreInfoRow(
              title: "\(family.title) x\(family.count)",
              value: family.detail,
              systemImage: self.healthPacketFamilyIcon(family),
              status: self.healthPacketFamilyStatus(family)
            )
          }
        }
      }

      Section("Movement Test") {
        MoreInfoRow(
          title: "Connection",
          value: "\(model.ble.connectionState) | \(model.ble.activeDeviceName)",
          systemImage: "sensor.tag.radiowaves.forward",
          status: model.ble.connectionState == "ready" ? .ready : .blocked
        )
        MoreInfoRow(
          title: "Last Packet",
          value: packetMonitor.movementPacketStatus,
          systemImage: "waveform.path.ecg",
          status: packetMonitor.movementPacketStatus == "No movement packets" ? .waiting : .ready
        )
        MoreInfoRow(
          title: "Detector",
          value: model.activityDetectionStatus,
          systemImage: "figure.run.circle",
          status: activityDetectorStatus
        )
        MoreActionRow(
          title: model.movementPacketValidationIsRunning ? "Listening For Movement" : "Run Movement Packet Test",
          detail: model.movementPacketValidationStatus,
          systemImage: "dot.radiowaves.left.and.right",
          status: movementPacketTestStatus,
          disabled: model.movementPacketValidationIsRunning
        ) {
          model.startMovementPacketValidationTest()
        }
      }

      Section("Device Event Signals") {
        MoreInfoRow(
          title: "Latest Event",
          value: packetMonitor.latestWhoopEventStatus,
          systemImage: "waveform.path",
          status: packetMonitor.latestWhoopEventStatus == "No device events" ? .waiting : .ready
        )
        MoreInfoRow(
          title: "Skin Temp Candidate",
          value: packetMonitor.latestSkinTemperatureCandidateStatus,
          systemImage: "thermometer",
          status: packetMonitor.latestSkinTemperatureCandidateStatus == "No skin temperature events" ? .waiting : .stale
        )
        MoreInfoRow(
          title: "Latest Data Packet",
          value: packetMonitor.latestWhoopDataPacketStatus,
          systemImage: "waveform.path.ecg.rectangle",
          status: packetMonitor.latestWhoopDataPacketStatus == "No device data packets" ? .waiting : .ready
        )
        MoreInfoRow(
          title: "Capture",
          value: "\(model.ble.physiologyCaptureStatus) | \(model.ble.lastPhysiologyCommandSummary)",
          systemImage: "dot.radiowaves.left.and.right",
          status: physiologyCaptureStatusKind
        )
        MoreInfoRow(
          title: "High Frequency Sync",
          value: "\(model.ble.highFrequencyHistorySyncDisplaySummary) | \(model.ble.lastHighFrequencyHistorySyncResponse)",
          systemImage: "bolt.horizontal",
          status: model.ble.highFrequencyHistorySyncActive ? .ready : .notRun
        )
        MoreInfoRow(
          title: "History Temp",
          value: packetMonitor.latestHistoryTemperatureCandidateStatus,
          systemImage: "thermometer.medium",
          status: packetMonitor.latestHistoryTemperatureCandidateStatus == "No history temperature packets" ? .waiting : .stale
        )
        MoreInfoRow(
          title: "History RR",
          value: packetMonitor.latestRespiratoryRateCandidateStatus,
          systemImage: "lungs",
          status: packetMonitor.latestRespiratoryRateCandidateStatus == "No respiratory rate candidates" ? .waiting : .stale
        )
        MoreInfoRow(
          title: "Pulse Info",
          value: packetMonitor.latestPulseInformationPacketStatus,
          systemImage: "lungs",
          status: packetMonitor.latestPulseInformationPacketStatus == "No pulse information packets" ? .waiting : .stale
        )
        MoreInfoRow(
          title: "Optical",
          value: packetMonitor.latestOpticalPacketStatus,
          systemImage: "waveform",
          status: packetMonitor.latestOpticalPacketStatus == "No optical packets" ? .waiting : .stale
        )
        MoreInfoRow(
          title: "Raw/Research K20",
          value: packetMonitor.latestRawResearchPacketStatus,
          systemImage: "waveform.path.ecg",
          status: packetMonitor.latestRawResearchPacketStatus == "No raw/research packets" ? .waiting : .ready
        )
        MoreInfoRow(
          title: "Realtime Status K2",
          value: packetMonitor.latestRealtimeStatusPacketStatus,
          systemImage: "dot.radiowaves.left.and.right",
          status: packetMonitor.latestRealtimeStatusPacketStatus == "No realtime status packets" ? .waiting : .ready
        )
        if !packetMonitor.recentDeviceSignalPoints.isEmpty {
          ForEach(packetMonitor.recentDeviceSignalPoints.prefix(8)) { point in
            MoreInfoRow(
              title: "\(point.family) | \(point.value)",
              value: "\(point.capturedAt.formatted(date: .omitted, time: .standard)) | \(point.detail)",
              systemImage: self.deviceSignalIcon(point.family),
              status: .ready
            )
          }
        }
        MoreActionRow(
          title: "Start Movement + HR Capture",
          detail: "Requests live HR plus K10/K11 movement streams",
          systemImage: "play.circle",
          status: model.ble.connectionState == "ready" ? .notRun : .blocked,
          disabled: model.ble.connectionState != "ready"
        ) {
          model.startMovementHeartRateCapture()
        }
        MoreActionRow(
          title: "Stop Movement + HR Capture",
          detail: "Turns live HR plus K10/K11 streams off",
          systemImage: "stop.circle",
          status: model.ble.connectionState == "ready" ? .notRun : .blocked,
          disabled: model.ble.connectionState != "ready"
        ) {
          model.stopMovementHeartRateCapture()
        }
        MoreActionRow(
          title: model.ble.highFrequencyHistorySyncActive ? "Exit High Frequency Sync" : "Enter High Frequency Sync",
          detail: "Band smart-alarm history-sync mode: 180s interval for 2h",
          systemImage: "bolt.horizontal",
          status: model.ble.canWriteHighFrequencyHistorySync ? .notRun : .blocked,
          disabled: !model.ble.canWriteHighFrequencyHistorySync
        ) {
          if model.ble.highFrequencyHistorySyncActive {
            model.exitHighFrequencyHistorySync()
          } else {
            model.enterHighFrequencyHistorySync()
          }
        }
      }

      Section("Research BT Commands") {
        MoreInfoRow(
          title: "Connection",
          value: "\(model.ble.connectionState) | \(model.ble.activeDeviceName)",
          systemImage: "sensor.tag.radiowaves.forward",
          status: model.ble.connectionState == "ready" ? .ready : .blocked
        )
        MoreInfoRow(
          title: "Last Result",
          value: model.ble.debugCommandStatus,
          systemImage: "terminal",
          status: self.debugCommandStatusKind
        )
        MoreInfoRow(
          title: "Remote Calls",
          value: "openvitals://debug-command/<id>?payload=<hex>",
          systemImage: "link",
          status: .ready
        )
        ForEach(model.ble.debugResearchCommands) { command in
          if command.canSendFromButton {
            MoreActionRow(
              title: "Send \(command.title)",
              detail: self.debugCommandDetail(command),
              systemImage: self.debugCommandIcon(command),
              status: self.debugCommandActionStatus(command),
              disabled: model.ble.connectionState != "ready"
            ) {
              _ = model.ble.sendDebugResearchCommand(id: command.id)
            }
          } else {
            MoreInfoRow(
              title: command.title,
              value: "\(self.debugCommandDetail(command)) | \(command.remoteURLExample)",
              systemImage: self.debugCommandIcon(command),
              status: .unavailable
            )
          }
        }
        if model.ble.debugCommandResponses.isEmpty {
          MoreInfoRow(
            title: "Responses",
            value: "No debug command responses yet",
            systemImage: "list.bullet.rectangle",
            status: .waiting
          )
        } else {
          ForEach(Array(model.ble.debugCommandResponses.prefix(12))) { response in
            MoreInfoRow(
              title: response.title,
              value: self.debugCommandResponseDetail(response),
              systemImage: response.status == "ok" ? "checkmark.circle" : "exclamationmark.triangle",
              status: response.status == "ok" ? .ready : .stale
            )
          }
        }
      }

      Section("Diagnostics") {
        MoreInfoRow(title: "UI Coverage", value: store.uiCoverageStatus, systemImage: "rectangle.3.group", status: diagnosticStatus(store.uiCoverageStatus))
        MoreInfoRow(title: "Deferred Surfaces", value: store.deferredSurfaceStatus, systemImage: "rectangle.badge.plus", status: diagnosticStatus(store.deferredSurfaceStatus))
        MoreInfoRow(title: "Property Suite", value: store.propertySuiteStatus, systemImage: "checklist", status: diagnosticStatus(store.propertySuiteStatus))
        MoreInfoRow(title: "Perf Budget", value: store.perfBudgetStatus, systemImage: "speedometer", status: diagnosticStatus(store.perfBudgetStatus))
        Button {
          store.runUICoverageAudit()
        } label: {
          Label("Run UI Coverage", systemImage: "rectangle.3.group")
        }
        Button {
          store.runPropertySuite()
        } label: {
          Label("Run Property Suite", systemImage: "checklist")
        }
        Button {
          store.runPerfBudget()
        } label: {
          Label("Run Perf Budget", systemImage: "speedometer")
        }
      }

      Section("Command Evidence") {
        MoreInfoRow(title: "Evidence Import", value: store.commandEvidenceImportStatus, systemImage: "doc.text.magnifyingglass", status: .unavailable)
        MoreInfoRow(title: "Gate Sweep", value: store.commandGateSweepStatus, systemImage: "checkmark.shield", status: diagnosticStatus(store.commandGateSweepStatus))
        MoreInfoRow(title: "Capture Plan", value: store.commandCapturePlanStatus, systemImage: "scope", status: commandCapturePlanStatus)
        Button {
          store.loadCommandDefinitions()
        } label: {
          Label("Load Command Definitions", systemImage: "list.bullet.rectangle")
        }
        Button {
          store.runCaptureArrivalPlan()
        } label: {
          Label("Run Capture Arrival Plan", systemImage: "scope")
        }
      }

      Section("Command Shortcuts") {
        ForEach(store.commandGroups) { group in
          MoreCommandGroupRow(group: group)
        }
      }

      Section("Protected Controls") {
        Button {
          showDestructiveConfirmation = true
        } label: {
          Label("Destructive Commands Locked", systemImage: "lock.shield")
        }
        MoreInfoRow(title: "Gate", value: store.destructiveGateStatus, systemImage: "lock", status: .blocked)
        MoreInfoRow(title: "Local Data", value: store.deletionStatus, systemImage: "externaldrive.badge.xmark", status: localDataWipeStatus)
        MoreActionRow(
          title: "Wipe Local App Data",
          detail: localDataWipeDetail,
          systemImage: "trash",
          status: localDataWipeActionStatus,
          disabled: localDataWipeDisabled
        ) {
          showLocalDataWipeConfirmation = true
        }
      }

#if DEBUG
      Section("Developer") {
        Button {
          model.ble.previewHelloWorldToast()
        } label: {
          Label("Hello World Toast", systemImage: "bell.badge")
        }

        Button {
          model.recordUIAction("ui.debug.redo_onboarding")
          OnboardingProfilePersistence.requestRedoFromDefaults()
          model.onboardingComplete = false
          onboardingComplete = false
          onboardingRedoRequested = true
        } label: {
          Label("Re-do Onboarding", systemImage: "arrow.counterclockwise.circle")
        }
      }
#endif
    }
    .openVitalsListBackground()
    .navigationTitle("Debug")
    .onAppear {
      model.recordUIAction("page.opened", detail: "More Debug")
      store.refreshBridgeStatus(model: model)
    }
    .alert("Destructive commands are locked", isPresented: $showDestructiveConfirmation) {
      Button("Keep Locked", role: .cancel) {
        store.showDestructiveGate()
      }
    } message: {
      Text("This surface records the gate only. No haptics, firmware, config, or reboot command is sent from this tap.")
    }
    .alert("Wipe local app data?", isPresented: $showLocalDataWipeConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Wipe Local Data", role: .destructive) {
        model.recordUIAction("ui.debug.local_data_wipe")
        store.wipeLocalAppData()
        healthStore.resetAfterLocalDataWipe()
        model.markLocalAppDataWiped()
      }
    } message: {
      Text("Deletes OpenVitals local SQLite data, captures, exports, cached scores, profile, and local app defaults on this device. The remembered BLE device is kept, and no erase command is sent to your wearable.")
    }
  }

  private var rustBridgeStatus: MoreStatusKind {
    if store.coreVersionStatus.hasPrefix("Rust core") {
      return .ready
    }
    if store.coreVersionStatus.localizedCaseInsensitiveContains("unavailable") {
      return .blocked
    }
    return .waiting
  }

  private var waitingOrNotRunForCapture: MoreStatusKind {
    model.healthPacketCaptureSessionID == nil ? .notRun : .waiting
  }

  private var historicalSyncStatusKind: MoreStatusKind {
    if model.ble.isHistoricalSyncing {
      return .inProgress
    }
    if model.ble.historicalSyncStatus == "failed" {
      return .stale
    }
    if model.ble.lastHistoricalSyncCompletedAt == nil {
      return .notRun
    }
    return .ready
  }

  private var physiologyCaptureStatusKind: MoreStatusKind {
    let normalized = model.ble.physiologyCaptureStatus.lowercased()
    if normalized == "not started" {
      return .notRun
    }
    if normalized.contains("failed") || normalized.contains("blocked") {
      return .blocked
    }
    return .listening
  }

  private var commandCapturePlanStatus: MoreStatusKind {
    let status = diagnosticStatus(store.commandCapturePlanStatus)
    if status != .waiting {
      return status
    }
    let validationStatus = store.validationStatusKind(store.commandCapturePlanStatus)
    return validationStatus == .pending ? .waiting : validationStatus
  }

  private var localDataWipeDisabled: Bool {
    !store.canWipeLocalAppData
      || model.healthPacketCaptureSessionID != nil
      || model.overnightGuardActive
  }

  private var localDataWipeDetail: String {
    if model.healthPacketCaptureSessionID != nil {
      return "Stop health packet capture before wiping local app data"
    }
    if model.overnightGuardActive {
      return "Stop Overnight Guard before wiping local app data"
    }
    if !store.canWipeLocalAppData {
      return "Wait for export work to finish before wiping local app data"
    }
    return "Deletes local evidence and cached health data; remembered BLE device is kept"
  }

  private var localDataWipeStatus: MoreStatusKind {
    if store.deletionStatus.localizedCaseInsensitiveContains("wiped") {
      return .ready
    }
    if store.deletionStatus.localizedCaseInsensitiveContains("blocked") {
      return .blocked
    }
    return .notRun
  }

  private var localDataWipeActionStatus: MoreStatusKind {
    localDataWipeDisabled ? .blocked : .notRun
  }

  private func parserProbeStatus(_ status: String) -> MoreStatusKind {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.contains("parsing") {
      return .inProgress
    }
    if normalized.contains("failed") {
      return .blocked
    }
    if normalized.contains("pending") || normalized.contains("not run") || normalized.contains("not checked") {
      return .notRun
    }
    if normalized.contains("waits") || normalized.contains("waiting") {
      return .waiting
    }
    return .ready
  }

  private func parserWarningStatus(_ status: String) -> MoreStatusKind {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "no warnings" {
      return .ready
    }
    if normalized.contains("pending") || normalized.contains("not run") {
      return .notRun
    }
    if normalized.contains("failed") {
      return .blocked
    }
    return .stale
  }

  private func debugSessionStatus(_ status: String) -> MoreStatusKind {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.contains("starting") || normalized.contains("creating") || normalized.contains("refreshing") {
      return .inProgress
    }
    if normalized.contains("failed") || normalized.contains("check database") {
      return .blocked
    }
    if normalized.contains("started") {
      return .ready
    }
    if normalized.contains("not started") || normalized.contains("start a local") {
      return .notRun
    }
    return .waiting
  }

  private func diagnosticStatus(_ status: String) -> MoreStatusKind {
    let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.contains("running")
      || normalized.contains("loading")
      || normalized.contains("generating")
      || normalized.contains("refreshing")
    {
      return .inProgress
    }
    if normalized.hasPrefix("no ") || normalized.contains("unknown") {
      return .notRun
    }
    if normalized.contains("failed") || normalized.contains("blocked") || normalized.contains("unavailable") {
      return .blocked
    }
    if normalized.contains("passed")
      || normalized.contains("within budget")
      || normalized.contains("loaded")
      || normalized.contains("definitions loaded")
    {
      return .ready
    }
    if normalized.contains("deferred") {
      return .stale
    }
    return .waiting
  }

  private var movementPacketTestStatus: MoreStatusKind {
    if model.movementPacketValidationIsRunning {
      return .listening
    }
    if model.movementPacketValidationStatus.hasPrefix("Passed") {
      return .ready
    }
    if model.movementPacketValidationStatus.hasPrefix("Failed") || model.movementPacketValidationStatus.hasPrefix("Connect device") {
      return .blocked
    }
    return .notRun
  }

  private var activityDetectorStatus: MoreStatusKind {
    if model.activityDetectionStatus.contains("Candidate") || model.activityDetectionStatus.contains("Movement") {
      return .ready
    }
    return packetMonitor.movementPacketStatus == "No movement packets" ? .waiting : .ready
  }

  private var healthPacketCaptureStatus: MoreStatusKind {
    if model.healthPacketCaptureSessionID != nil {
      return .listening
    }
    if model.healthPacketCaptureStatus.hasPrefix("Stopped") {
      return .ready
    }
    if model.healthPacketCaptureStatus.contains("failed") || model.healthPacketCaptureStatus.hasPrefix("Connect device") {
      return .blocked
    }
    return .notRun
  }

  private var healthPacketCaptureActionStatus: MoreStatusKind {
    if model.healthPacketCaptureSessionID != nil {
      return .listening
    }
    return model.ble.connectionState == "ready" ? .notRun : .blocked
  }

  private var temperatureCaptureActionStatus: MoreStatusKind {
    if model.healthPacketCaptureSessionID != nil {
      return .blocked
    }
    if model.ble.connectionState != "ready" {
      return .blocked
    }
    return model.ble.isHistoricalSyncing ? .inProgress : (model.ble.canSyncHistorical ? .notRun : .stale)
  }

  private var respiratoryPacketWatchStatus: MoreStatusKind {
    if model.respiratoryPacketWatchActive {
      return .listening
    }
    if model.respiratoryPacketWatchStatus.hasPrefix("Found K18") {
      return .ready
    }
    if model.respiratoryPacketWatchStatus.hasPrefix("Connect device") {
      return .blocked
    }
    if model.respiratoryPacketWatchStatus.hasPrefix("Timed out") {
      return .stale
    }
    return model.ble.connectionState == "ready" ? .notRun : .blocked
  }

  private var debugCommandStatusKind: MoreStatusKind {
    if model.ble.debugCommandStatus.hasPrefix("No debug command") {
      return .notRun
    }
    if model.ble.debugCommandStatus.contains("SUCCESS") || model.ble.debugCommandStatus.contains("ok:") {
      return .ready
    }
    if model.ble.debugCommandStatus.contains("blocked") {
      return .blocked
    }
    if model.ble.debugCommandStatus.contains("Unknown")
        || model.ble.debugCommandStatus.contains("failed")
        || model.ble.debugCommandStatus.contains("timeout") {
      return .stale
    }
    return model.ble.connectionState == "ready" ? .notRun : .blocked
  }

  private func debugCommandActionStatus(_ command: OpenVitalsDebugCommandDefinition) -> MoreStatusKind {
    if model.ble.connectionState != "ready" {
      return .blocked
    }
    return command.risk == "read" ? .notRun : .stale
  }

  private func debugCommandDetail(_ command: OpenVitalsDebugCommandDefinition) -> String {
    "id \(command.id) | cmd \(command.commandNumber) | \(command.payloadHint) | \(command.risk)"
  }

  private func debugCommandResponseDetail(_ response: OpenVitalsDebugCommandResponse) -> String {
    let body = response.responseBodyHex.isEmpty
      ? "no body"
      : "body \(String(response.responseBodyHex.prefix(96)))"
    let payload = response.responsePayloadHex.isEmpty
      ? "no payload"
      : "payload \(String(response.responsePayloadHex.prefix(64)))"
    return "\(response.status) | \(response.result) | seq \(response.sequence) | \(body) | \(payload) | src \(response.source)"
  }

  private func debugCommandIcon(_ command: OpenVitalsDebugCommandDefinition) -> String {
    switch command.family {
    case "battery":
      return "battery.100"
    case "optical":
      return "waveform.path.ecg"
    case "movement":
      return "figure.walk.motion"
    case "config":
      return "slider.horizontal.3"
    default:
      return "antenna.radiowaves.left.and.right"
    }
  }

  private func healthPacketFamilyStatus(_ family: HealthPacketCaptureFamily) -> MoreStatusKind {
    switch family.status {
    case .target:
      return .ready
    case .expected:
      return .waiting
    case .unresolved:
      return .stale
    case .unknown:
      return .blocked
    }
  }

  private func healthPacketFamilyIcon(_ family: HealthPacketCaptureFamily) -> String {
    switch family.status {
    case .target:
      return "scope"
    case .expected:
      return "waveform.path.ecg"
    case .unresolved:
      return "questionmark.diamond"
    case .unknown:
      return "questionmark.circle"
    }
  }

  private func deviceSignalIcon(_ family: String) -> String {
    switch family {
    case "HR":
      return "heart"
    case "Motion", "R21 IMU":
      return "figure.walk.motion"
    case "K2":
      return "dot.radiowaves.left.and.right"
    case "K16", "K20", "K11":
      return "waveform.path.ecg"
    case "Optical":
      return "waveform.path.ecg"
    case "Pulse":
      return "lungs"
    case "Skin Temp":
      return "thermometer.medium"
    default:
      return "waveform.path"
    }
  }
}
