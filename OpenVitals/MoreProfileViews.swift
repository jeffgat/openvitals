import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

struct MoreGreetingHeader: View {
  let firstName: String
  let profileSummary: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      OpenVitalsLogoMark(size: 44, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 3) {
        Text(greeting)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(OpenVitalsTheme.textSecondary)
        Text(displayName)
          .font(.headline)
          .foregroundStyle(OpenVitalsTheme.textPrimary)
        Text(profileSummary)
          .font(.caption)
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Image(systemName: "person.crop.circle.badge.pencil")
        .font(.title3.weight(.semibold))
        .foregroundStyle(OpenVitalsTheme.accent)
        .frame(width: 32, height: 32)
    }
    .padding(.vertical, 5)
  }

  private var displayName: String {
    let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "there" : trimmed
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<12:
      return "Good morning,"
    case 12..<17:
      return "Good afternoon,"
    default:
      return "Good evening,"
    }
  }
}

struct MoreDeveloperView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @ObservedObject var store: MoreDataStore
  let routes: [MoreRoute]
  let routeStatus: MoreRouteStatus
  @State private var advancedToolsExpanded = false

  var body: some View {
    List {
      Section("Mac Stream") {
        MoreInfoRow(
          title: "Status",
          value: macStreamSummary,
          systemImage: "network",
          status: macStreamStatus
        )
        Toggle(
          isOn: Binding(
            get: { model.mobileCaptureStreamEnabled },
            set: { model.setMobileCaptureStreamEnabled($0) }
          )
        ) {
          Label("Enable Mac Stream", systemImage: "dot.radiowaves.left.and.right")
        }
      }

      Section("Live Data") {
        MoreActionRow(
          title: liveDataActionTitle,
          detail: liveDataDetail,
          systemImage: liveDataActionIcon,
          status: liveDataStatus,
          disabled: liveDataDisabled
        ) {
          if liveDataShouldStartOrReplace {
            model.startDataCollectionLiveCapture()
          } else {
            model.stopHealthPacketCapture(reason: "data_collection_live_stop")
          }
        }
        MoreInfoRow(
          title: "Live Frames",
          value: model.healthPacketCaptureTargetSummary,
          systemImage: "waveform.path.ecg",
          status: model.healthPacketCaptureSessionID == nil ? .notRun : .listening
        )
      }

      Section("Historical Data") {
        MoreActionRow(
          title: historicalActionTitle,
          detail: historicalActionDetail,
          systemImage: historicalActionIcon,
          status: historicalActionStatus,
          disabled: historicalActionDisabled
        ) {
          if model.overnightGuardActive {
            model.requestOvernightGuardFinalSync()
          } else {
            model.startLeanOvernightGuard()
          }
        }
        if model.overnightGuardActive {
          MoreActionRow(
            title: "Stop Historical Collection",
            detail: "Stops the guard without running another historical drain.",
            systemImage: "stop.circle",
            status: .stale,
            disabled: model.ble.isHistoricalSyncing || model.overnightGuardExportInProgress
          ) {
            model.stopOvernightGuard()
          }
        }
        MoreInfoRow(
          title: "Backlog",
          value: model.overnightGuardTargetSummary,
          systemImage: "clock.arrow.circlepath",
          status: historicalTargetStatus
        )
        MoreInfoRow(
          title: "Guard",
          value: model.overnightGuardStatus,
          systemImage: "moon",
          status: historicalGuardStatus
        )
      }

      Section("Reference Data") {
        MoreActionRow(
          title: store.guidedReferenceProbeInProgress ? "Cancel Reference Run" : "Start Reference Run",
          detail: store.guidedReferenceProbeStatus,
          systemImage: store.guidedReferenceProbeInProgress ? "xmark.circle" : "waveform.path.ecg.rectangle",
          status: referenceRunStatus,
          disabled: referenceRunDisabled
        ) {
          if store.guidedReferenceProbeInProgress {
            store.cancelGuidedReferenceProbe()
          } else {
            store.startGuidedReferenceProbe(model: model)
          }
        }
        MoreInfoRow(
          title: "Reference Strap",
          value: referenceSummary,
          systemImage: "heart.circle",
          status: referenceStatus
        )
      }

      Section("Export Fallback") {
        MoreActionRow(
          title: "Create Local Export",
          detail: exportDetail,
          systemImage: "externaldrive.badge.plus",
          status: exportStatus,
          disabled: store.localExportInProgress || model.overnightGuardExportInProgress
        ) {
          store.saveLocalDataBundle()
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

      Section("Advanced") {
        DisclosureGroup(isExpanded: $advancedToolsExpanded) {
          ForEach(routes) { route in
            NavigationLink(value: route) {
              MoreRouteRow(route: route, status: routeStatus[keyPath: route.statusKeyPath], showsStatus: true)
            }
            .accessibilityLabel(route.title)
          }
        } label: {
          Label("Advanced Tools", systemImage: "slider.horizontal.3")
        }
      }
    }
    .listStyle(.insetGrouped)
    .openVitalsListBackground()
    .navigationTitle("Data Collection")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }

  private var macStreamStatus: MoreStatusKind {
    if !model.mobileCaptureStreamEnabled {
      return .pending
    }
    if !model.mobileCaptureStreamReady {
      return .blocked
    }
    if model.mobileCaptureStreamStatus.localizedCaseInsensitiveContains("failed")
      || model.mobileCaptureStreamStatus.localizedCaseInsensitiveContains("dropped") {
      return .stale
    }
    return .ready
  }

  private var macStreamSummary: String {
    "\(model.mobileCaptureStreamStatus) | queued \(model.mobileCaptureStreamQueuedFrameCount) | sent \(model.mobileCaptureStreamSentFrameCount) | imported \(model.mobileCaptureStreamImportedFrameCount) | raw \(model.mobileCaptureStreamRawInsertedCount)"
  }

  private var liveDataStatus: MoreStatusKind {
    if model.healthPacketCaptureSessionID != nil, !passiveCaptureOccupiesLiveSlot {
      return .listening
    }
    if !model.mobileCaptureStreamReady {
      return .blocked
    }
    return model.ble.connectionState == "ready" ? .notRun : .blocked
  }

  private var liveDataDisabled: Bool {
    liveDataShouldStartOrReplace
      && (!model.mobileCaptureStreamReady || model.ble.connectionState != "ready")
  }

  private var liveDataDetail: String {
    if passiveCaptureOccupiesLiveSlot {
      return "Replaces the passive activity capture with a diagnostic live stream to the Mac."
    }
    if model.healthPacketCaptureSessionID != nil {
      return model.healthPacketCaptureTargetSummary
    }
    if !model.mobileCaptureStreamReady {
      return "Enable Mac Stream before starting long live collection."
    }
    if model.ble.connectionState != "ready" {
      return "Connect the device before starting live collection."
    }
    return "Streams live movement, heart, optical, pulse, temperature/history, and metadata frames to the Mac."
  }

  private var passiveCaptureOccupiesLiveSlot: Bool {
    model.activeHealthPacketCapture?.source == "auto.passive_activity_detection"
  }

  private var liveDataShouldStartOrReplace: Bool {
    model.healthPacketCaptureSessionID == nil || passiveCaptureOccupiesLiveSlot
  }

  private var liveDataActionTitle: String {
    liveDataShouldStartOrReplace ? "Start Live Data" : "Stop Live Data"
  }

  private var liveDataActionIcon: String {
    liveDataShouldStartOrReplace ? "record.circle" : "stop.circle"
  }

  private var historicalActionTitle: String {
    if model.ble.isHistoricalSyncing {
      return "Historical Sync Running"
    }
    if model.overnightGuardActive {
      return model.mobileCaptureStreamReady ? "Drain History to Mac" : "Drain History + Export"
    }
    return "Start Historical Collection"
  }

  private var historicalActionIcon: String {
    model.overnightGuardActive ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath"
  }

  private var historicalActionStatus: MoreStatusKind {
    if model.ble.isHistoricalSyncing {
      return .inProgress
    }
    if model.overnightGuardActive {
      return .listening
    }
    if model.ble.connectionState != "ready" {
      return .blocked
    }
    return .notRun
  }

  private var historicalActionDisabled: Bool {
    model.ble.isHistoricalSyncing
      || model.overnightGuardExportInProgress
      || (!model.overnightGuardActive && model.ble.connectionState != "ready")
      || (model.overnightGuardActive && !model.ble.canSyncHistorical)
  }

  private var historicalActionDetail: String {
    if model.ble.isHistoricalSyncing {
      return "Historical packets are draining now. Keep the app foregrounded."
    }
    if model.overnightGuardActive {
      if !model.ble.canSyncHistorical {
        return "Historical drain blocked: \(model.ble.historicalSyncStatus)"
      }
      if model.mobileCaptureStreamReady {
        return "Pulls delayed historical frames from the device and streams them to the Mac database."
      }
      return "Pulls delayed historical frames and falls back to a phone-side export."
    }
    if model.ble.connectionState != "ready" {
      return "Connect the device before starting historical collection."
    }
    return "Starts the lean historical guard. Run the drain action when you are ready to catch up."
  }

  private var historicalTargetStatus: MoreStatusKind {
    model.overnightGuardTargetSummary.contains("K18 0 | K24 0 | K25 0 | K26 0") ? .pending : .ready
  }

  private var historicalGuardStatus: MoreStatusKind {
    if model.overnightGuardActive {
      return .listening
    }
    if model.overnightGuardStatus.localizedCaseInsensitiveContains("failed")
      || model.overnightGuardStatus.localizedCaseInsensitiveContains("blocked") {
      return .blocked
    }
    if model.overnightGuardStatus.hasPrefix("Stopped") {
      return .stale
    }
    return .notRun
  }

  private var referenceRunStatus: MoreStatusKind {
    if store.guidedReferenceProbeInProgress {
      return .inProgress
    }
    if store.rrReferenceCapture.hasLiveRRSamples || store.rrReferenceCapture.sampleCount > 0 {
      return .ready
    }
    if model.ble.connectionState != "ready" {
      return .blocked
    }
    return .notRun
  }

  private var referenceRunDisabled: Bool {
    if store.guidedReferenceProbeInProgress {
      return false
    }
    return store.automaticStreamProbeInProgress
      || store.localExportInProgress
      || model.ble.connectionState != "ready"
  }

  private var referenceStatus: MoreStatusKind {
    if store.rrReferenceCapture.isCapturing {
      return .listening
    }
    if store.rrReferenceCapture.sampleCount > 0 {
      return .ready
    }
    return .pending
  }

  private var referenceSummary: String {
    let capture = store.rrReferenceCapture
    let heartRate = capture.lastHeartRateBPM.map { "\($0) bpm" } ?? "-- bpm"
    let rr = capture.lastRRIntervalMS.map { "\(Int($0.rounded())) ms" } ?? "-- ms"
    return "\(capture.sampleCount) RR samples | \(capture.notificationCount) notifications | HR \(heartRate) | RR \(rr)"
  }

  private var exportStatus: MoreStatusKind {
    if store.localExportInProgress || model.overnightGuardExportInProgress {
      return .inProgress
    }
    if store.localExportURL != nil || model.overnightGuardExportURL != nil {
      return .ready
    }
    return .pending
  }

  private var exportDetail: String {
    if model.overnightGuardExportInProgress {
      return model.overnightGuardExportStatus
    }
    if store.localExportInProgress {
      return store.localExportStatus
    }
    if store.localExportURL != nil {
      return "Bundle ready. Share the local data file and manifest below."
    }
    if model.mobileCaptureStreamReady {
      return "Fallback only. The Mac database should already be receiving streamed frames."
    }
    return "Creates a local bundle when Mac Stream is unavailable or you need a portable evidence file."
  }
}

struct MoreProfileView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @AppStorage(OnboardingStorage.firstName) private var firstName = ""
  @AppStorage(OnboardingStorage.dateOfBirth) private var dateOfBirthString = ""
  @AppStorage(OnboardingStorage.unitSystem) private var unitSystemRaw = MoreProfileUnitSystem.imperial.rawValue
  @AppStorage(OnboardingStorage.heightInput) private var heightInput = ""
  @AppStorage(OnboardingStorage.heightFeetInput) private var heightFeetInput = ""
  @AppStorage(OnboardingStorage.heightInchesInput) private var heightInchesInput = ""
  @AppStorage(OnboardingStorage.weightInput) private var weightInput = ""
  @AppStorage(OnboardingStorage.gender) private var genderRaw = ""
  @AppStorage(OnboardingStorage.heightMm) private var heightMm = 0
  @AppStorage(OnboardingStorage.weightGrams) private var weightGrams = 0
  @AppStorage(OnboardingStorage.createdAtUnixMs) private var createdAtUnixMs = 0
  @AppStorage(OnboardingStorage.timezoneID) private var timezoneID = ""
  @State private var dateOfBirth = MoreProfileDate.defaultDateOfBirth()
  @State private var statusMessage: String?
  @State private var healthKitImporting = false
  @FocusState private var focusedField: MoreProfileField?

  private var unitSystem: MoreProfileUnitSystem {
    MoreProfileUnitSystem(rawValue: unitSystemRaw) ?? .imperial
  }

  var body: some View {
    List {
      Section("Personal") {
        HStack {
          Text("First name")
          TextField("First name", text: $firstName)
            .multilineTextAlignment(.trailing)
            .textContentType(.givenName)
            .focused($focusedField, equals: .firstName)
        }

        DatePicker(
          "Date of birth",
          selection: $dateOfBirth,
          in: MoreProfileDate.minimumDateOfBirth()...MoreProfileDate.maximumDateOfBirth(),
          displayedComponents: .date
        )

        Picker("Gender", selection: $genderRaw) {
          Text("Select").tag("")
          ForEach(MoreProfileGender.allCases) { gender in
            Text(gender.title).tag(gender.rawValue)
          }
        }
      }

      Section("Measurements") {
        Picker("Units", selection: $unitSystemRaw) {
          ForEach(MoreProfileUnitSystem.allCases) { unit in
            Text(unit.title).tag(unit.rawValue)
          }
        }

        if unitSystem == .metric {
          MoreProfileTextFieldRow(
            label: "Height",
            text: $heightInput,
            prompt: "cm",
            suffix: "cm",
            field: .heightCentimeters,
            focusedField: $focusedField
          )
        } else {
          MoreProfileTextFieldRow(
            label: "Height",
            text: $heightFeetInput,
            prompt: "ft",
            suffix: "ft",
            keyboardType: .numberPad,
            field: .heightFeet,
            focusedField: $focusedField
          )
          MoreProfileTextFieldRow(
            label: "Inches",
            text: $heightInchesInput,
            prompt: "in",
            suffix: "in",
            field: .heightInches,
            focusedField: $focusedField
          )
        }

        MoreProfileTextFieldRow(
          label: "Weight",
          text: $weightInput,
          prompt: unitSystem == .metric ? "kg" : "lb",
          suffix: unitSystem == .metric ? "kg" : "lb",
          field: .weight,
          focusedField: $focusedField
        )
      }

      Section("Apple Health") {
        Button {
          updateFromHealthKit()
        } label: {
          HStack {
            Label("Update weight", systemImage: "heart.text.square")
            Spacer()
            if healthKitImporting {
              ProgressView()
            }
          }
        }
        .disabled(healthKitImporting)
      }

      if let statusMessage {
        Section {
          Text(statusMessage)
            .font(.footnote)
            .foregroundStyle(statusMessage.hasPrefix("Profile") || statusMessage.hasPrefix("Updated") ? OpenVitalsTheme.gold : OpenVitalsTheme.bronze)
        }
      }
    }
    .listStyle(.insetGrouped)
    .openVitalsListBackground()
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Save") {
          saveProfile()
        }
        .fontWeight(.semibold)
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
          focusedField = nil
        }
      }
    }
    .onAppear {
      hydrateDateOfBirth()
      hydrateMeasurementsIfNeeded()
    }
    .onChange(of: dateOfBirth) { _, newValue in
      dateOfBirthString = MoreProfileDate.dateOnlyString(MoreProfileDate.clamp(newValue))
    }
    .onChange(of: unitSystemRaw) { oldValue, newValue in
      convertDisplayedMeasurements(from: oldValue, to: newValue)
    }
  }

  private func hydrateDateOfBirth() {
    if let saved = MoreProfileDate.parse(dateOfBirthString) {
      dateOfBirth = MoreProfileDate.clamp(saved)
    } else {
      dateOfBirth = MoreProfileDate.defaultDateOfBirth()
      dateOfBirthString = MoreProfileDate.dateOnlyString(dateOfBirth)
    }
  }

  private func hydrateMeasurementsIfNeeded() {
    if unitSystem == .imperial,
       heightFeetInput.isEmpty,
       heightInchesInput.isEmpty,
       heightMm > 0 {
      applyHeightMillimeters(heightMm, for: .imperial)
    }
    if unitSystem == .metric, heightInput.isEmpty, heightMm > 0 {
      applyHeightMillimeters(heightMm, for: .metric)
    }
    if weightInput.isEmpty, weightGrams > 0 {
      applyWeightGrams(weightGrams, for: unitSystem)
    }
  }

  private func saveProfile() {
    focusedField = nil
    statusMessage = nil
    let trimmedName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      statusMessage = "Enter your first name."
      return
    }
    guard trimmedName.count <= 40 else {
      statusMessage = "Use 40 characters or fewer."
      return
    }
    guard !genderRaw.isEmpty else {
      statusMessage = "Select a gender."
      return
    }
    guard let parsedHeightMm = heightMillimeters(for: unitSystem) else {
      statusMessage = "Enter height."
      return
    }
    guard let parsedWeightGrams = parsedWeightGrams(for: unitSystem) else {
      statusMessage = "Enter weight."
      return
    }

    let heightCentimeters = Double(parsedHeightMm) / 10
    guard (90...245).contains(heightCentimeters) else {
      statusMessage = "Check height."
      return
    }
    let weightKilograms = Double(parsedWeightGrams) / 1000
    guard (30...320).contains(weightKilograms) else {
      statusMessage = "Check weight."
      return
    }

    firstName = trimmedName
    dateOfBirthString = MoreProfileDate.dateOnlyString(dateOfBirth)
    heightMm = parsedHeightMm
    weightGrams = parsedWeightGrams
    if createdAtUnixMs == 0 {
      createdAtUnixMs = Int((Date().timeIntervalSince1970 * 1000).rounded())
    }
    timezoneID = TimeZone.current.identifier
    OnboardingProfilePersistence.saveProfile(
      currentProfileSnapshot(),
      onboardingComplete: UserDefaults.standard.bool(forKey: OnboardingStorage.onboardingComplete)
    )
    model.recordUIAction("profile.saved", detail: "\(unitSystem.rawValue) height_mm=\(heightMm) weight_g=\(weightGrams)")
    statusMessage = "Profile updated."
  }

  private func updateFromHealthKit() {
    guard !healthKitImporting else {
      return
    }
    healthKitImporting = true
    statusMessage = nil
    Task {
      let result = await HealthKitProfileImporter.requestProfileAccess()
      await MainActor.run {
        applyHealthKitProfileAutofill(result.autofill, overwrite: true)
        healthKitImporting = false
        statusMessage = result.autofill.hasValues ? "Updated from Apple Health." : result.status
        model.recordUIAction("profile.healthkit_autofill", detail: result.status)
      }
    }
  }

  private func applyHealthKitProfileAutofill(_ autofill: HealthKitProfileAutofill, overwrite: Bool) {
    if let grams = autofill.weightGrams,
       overwrite || weightGrams == 0 {
      weightGrams = grams
      applyWeightGrams(grams, for: unitSystem)
    }
  }

  private func currentProfileSnapshot() -> OnboardingProfileSnapshot {
    OnboardingProfileSnapshot(
      firstName: firstName,
      dateOfBirthString: dateOfBirthString,
      unitSystemRaw: unitSystemRaw,
      heightInput: heightInput,
      heightFeetInput: heightFeetInput,
      heightInchesInput: heightInchesInput,
      weightInput: weightInput,
      genderRaw: genderRaw,
      heightMm: heightMm,
      weightGrams: weightGrams,
      createdAtUnixMs: createdAtUnixMs,
      timezoneID: timezoneID
    )
  }

  private func convertDisplayedMeasurements(from oldRawValue: String, to newRawValue: String) {
    guard
      let oldUnitSystem = MoreProfileUnitSystem(rawValue: oldRawValue),
      let newUnitSystem = MoreProfileUnitSystem(rawValue: newRawValue),
      oldUnitSystem != newUnitSystem
    else {
      return
    }
    if let currentHeightMm = heightMillimeters(for: oldUnitSystem) {
      applyHeightMillimeters(currentHeightMm, for: newUnitSystem)
    }
    if let currentWeightGrams = parsedWeightGrams(for: oldUnitSystem) {
      applyWeightGrams(currentWeightGrams, for: newUnitSystem)
    }
  }

  private func heightMillimeters(for unitSystem: MoreProfileUnitSystem) -> Int? {
    switch unitSystem {
    case .metric:
      guard let centimeters = measurementValue(heightInput), centimeters > 0 else {
        return nil
      }
      return Int((centimeters * 10).rounded())
    case .imperial:
      let feet = measurementValue(heightFeetInput) ?? 0
      let inches = measurementValue(heightInchesInput) ?? 0
      let totalInches = feet * 12 + inches
      guard totalInches > 0 else {
        return nil
      }
      return Int((totalInches * 25.4).rounded())
    }
  }

  private func parsedWeightGrams(for unitSystem: MoreProfileUnitSystem) -> Int? {
    guard let weight = measurementValue(weightInput), weight > 0 else {
      return nil
    }
    switch unitSystem {
    case .metric:
      return Int((weight * 1000).rounded())
    case .imperial:
      return Int((weight * 453.59237).rounded())
    }
  }

  private func applyHeightMillimeters(_ millimeters: Int, for unitSystem: MoreProfileUnitSystem) {
    switch unitSystem {
    case .metric:
      heightInput = MoreProfileFormatting.formatted(Double(millimeters) / 10, maxFractionDigits: 1)
    case .imperial:
      let totalInches = Double(millimeters) / 25.4
      let feet = Int(totalInches / 12)
      let inches = totalInches - Double(feet * 12)
      heightFeetInput = String(feet)
      heightInchesInput = MoreProfileFormatting.formatted(inches, maxFractionDigits: 1)
      heightInput = MoreProfileFormatting.formatted(totalInches, maxFractionDigits: 1)
    }
  }

  private func applyWeightGrams(_ grams: Int, for unitSystem: MoreProfileUnitSystem) {
    switch unitSystem {
    case .metric:
      weightInput = MoreProfileFormatting.formatted(Double(grams) / 1000, maxFractionDigits: 1)
    case .imperial:
      weightInput = MoreProfileFormatting.formatted(Double(grams) / 453.59237, maxFractionDigits: 1)
    }
  }

  private func measurementValue(_ rawValue: String) -> Double? {
    let normalized = rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: ".")
    return Double(normalized)
  }
}

struct MoreProfileTextFieldRow: View {
  let label: String
  @Binding var text: String
  let prompt: String
  let suffix: String
  var keyboardType: UIKeyboardType = .decimalPad
  let field: MoreProfileField
  let focusedField: FocusState<MoreProfileField?>.Binding

  var body: some View {
    HStack(spacing: 10) {
      Text(label)
      TextField(prompt, text: $text)
        .multilineTextAlignment(.trailing)
        .keyboardType(keyboardType)
        .focused(focusedField, equals: field)
      Text(suffix)
        .foregroundStyle(.secondary)
    }
  }
}

enum MoreProfileField: Hashable {
  case firstName
  case heightCentimeters
  case heightFeet
  case heightInches
  case weight
}

enum MoreProfileUnitSystem: String, CaseIterable, Identifiable {
  case imperial
  case metric

  var id: String { rawValue }

  var title: String {
    switch self {
    case .imperial: "Imperial"
    case .metric: "Metric"
    }
  }
}

enum MoreProfileGender: String, CaseIterable, Identifiable {
  case female
  case male
  case nonBinary = "non_binary"
  case preferNotToSay = "prefer_not_to_say"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .female: "Female"
    case .male: "Male"
    case .nonBinary: "Non-binary"
    case .preferNotToSay: "Prefer not to say"
    }
  }
}

enum MoreProfileDate {
  static func parse(_ value: String) -> Date? {
    let formatter = dateFormatter
    guard let date = formatter.date(from: value) else {
      return nil
    }
    return Calendar.current.startOfDay(for: date)
  }

  static func dateOnlyString(_ date: Date) -> String {
    dateFormatter.string(from: date)
  }

  static func defaultDateOfBirth() -> Date {
    clamp(Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date())
  }

  static func minimumDateOfBirth() -> Date {
    Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date.distantPast
  }

  static func maximumDateOfBirth() -> Date {
    Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date()
  }

  static func clamp(_ date: Date) -> Date {
    let normalized = Calendar.current.startOfDay(for: date)
    let minimum = Calendar.current.startOfDay(for: minimumDateOfBirth())
    let maximum = Calendar.current.startOfDay(for: maximumDateOfBirth())
    if normalized < minimum {
      return minimum
    }
    if normalized > maximum {
      return maximum
    }
    return normalized
  }

  private static var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }
}

enum MoreProfileFormatting {
  static func heightText(millimeters: Int, unitSystemRaw: String) -> String {
    guard millimeters > 0 else {
      return ""
    }
    let unitSystem = MoreProfileUnitSystem(rawValue: unitSystemRaw) ?? .imperial
    switch unitSystem {
    case .metric:
      return "\(formatted(Double(millimeters) / 10, maxFractionDigits: 1)) cm"
    case .imperial:
      let totalInches = Double(millimeters) / 25.4
      let feet = Int(totalInches / 12)
      let inches = totalInches - Double(feet * 12)
      return "\(feet) ft \(formatted(inches, maxFractionDigits: 1)) in"
    }
  }

  static func weightText(grams: Int, unitSystemRaw: String) -> String {
    guard grams > 0 else {
      return ""
    }
    let unitSystem = MoreProfileUnitSystem(rawValue: unitSystemRaw) ?? .imperial
    switch unitSystem {
    case .metric:
      return "\(formatted(Double(grams) / 1000, maxFractionDigits: 1)) kg"
    case .imperial:
      return "\(formatted(Double(grams) / 453.59237, maxFractionDigits: 1)) lb"
    }
  }

  static func formatted(_ value: Double, maxFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
  }
}

struct MoreRouteRow: View {
  let route: MoreRoute
  let status: MoreStatusKind
  var showsStatus = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: route.systemImage)
        .font(.title3)
        .foregroundStyle(status.tint)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 3) {
        Text(route.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(OpenVitalsTheme.textPrimary)
        Text(route.subtitle)
          .font(.caption)
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)
      if showsStatus {
        MoreStatusBadge(status: status)
      }
    }
    .padding(.vertical, 4)
  }
}

struct MoreStatusBadge: View {
  let status: MoreStatusKind
  var titleOverride: String? = nil

  var body: some View {
    let title = titleOverride ?? status.title
    Label(title, systemImage: status.systemImage)
      .font(.caption2.weight(.semibold))
      .labelStyle(.titleAndIcon)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(status.tint.opacity(0.13), in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(status.tint.opacity(0.22), lineWidth: 1)
      }
      .foregroundStyle(status.tint)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .accessibilityLabel(title)
  }
}
