import SwiftUI

struct HomeCardioLoadSparkline: View {
  let days: [CardioLoadDay]

  var body: some View {
    GeometryReader { proxy in
      if values.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(OpenVitalsTheme.separator)
          .overlay {
            Text("No data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(OpenVitalsTheme.textSecondary)
          }
      } else {
        ZStack(alignment: .bottomLeading) {
          rangeBandPath(in: proxy.size)
            .fill(OpenVitalsTheme.accent.opacity(0.10))

          sparklinePath(in: proxy.size)
            .stroke(
              OpenVitalsTheme.accent.opacity(0.92),
              style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

          if let last = values.last {
            let lastPoint = chartPoint(index: values.count - 1, value: last, size: proxy.size)
            Circle()
              .fill(OpenVitalsTheme.appBackground)
              .frame(width: 18, height: 18)
              .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
              .position(lastPoint)
            Circle()
              .stroke(OpenVitalsTheme.accent, lineWidth: 3)
              .frame(width: 11, height: 11)
              .position(lastPoint)
          }
        }
      }
    }
  }

  private var values: [Double] {
    days.map(\.load)
  }

  private func sparklinePath(in size: CGSize) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = chartPoint(index: index, value: value, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func rangeBandPath(in size: CGSize) -> Path {
    var upperPoints: [CGPoint] = []
    var lowerPoints: [CGPoint] = []
    for (index, value) in values.enumerated() {
      upperPoints.append(chartPoint(index: index, value: value * 1.14 + 4, size: size))
      lowerPoints.append(chartPoint(index: index, value: max(value * 0.74 - 3, 0), size: size))
    }

    return Path { path in
      guard let first = upperPoints.first else { return }
      path.move(to: first)
      upperPoints.dropFirst().forEach { path.addLine(to: $0) }
      lowerPoints.reversed().forEach { path.addLine(to: $0) }
      path.closeSubpath()
    }
  }

  private func chartPoint(index: Int, value: Double, size: CGSize) -> CGPoint {
    let left: CGFloat = 4
    let right: CGFloat = 16
    let top: CGFloat = 10
    let bottom: CGFloat = 12
    let maximum = max((values.max() ?? 1) * 1.20, 60)
    let x = left + (size.width - left - right) * CGFloat(index) / CGFloat(max(values.count - 1, 1))
    let normalized = min(max(value / maximum, 0), 1)
    let y = top + (size.height - top - bottom) * CGFloat(1 - normalized)
    return CGPoint(x: x, y: y)
  }
}

struct HomeHealthMonitorSection: View {
  let snapshots: [HealthMetricSnapshot]
  let openSnapshot: (HealthMetricSnapshot) -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Health Monitor")

      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(snapshots) { snapshot in
          Button {
            openSnapshot(snapshot)
          } label: {
            HomeHealthMetricCard(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct HomeHealthMetricCard: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: snapshot.systemImage)
            .foregroundStyle(tint)
          Text(snapshot.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(OpenVitalsTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        Spacer(minLength: 4)

        Text(snapshot.displayValue)
          .font(.title3.bold())
          .foregroundStyle(OpenVitalsTheme.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)

        Label(snapshot.status, systemImage: statusImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer(minLength: 0)

      Capsule()
        .fill(tint.opacity(0.18))
        .frame(width: 8)
        .overlay(alignment: .bottom) {
          Capsule()
            .fill(tint)
            .frame(height: 52)
        }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(12)
    .cardSurface(tint: tint)
  }

  private var statusImage: String {
    snapshot.status.localizedCaseInsensitiveContains("unavailable") ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
  }

  private var tint: Color {
    OpenVitalsTheme.routeTint(snapshot.route)
  }
}

struct HomeAlarmSection: View {
  @ObservedObject var ble: OpenVitalsBLEClient
  @State private var alarmTime = defaultWakeTime()
  @State private var draftAlarmTime = defaultWakeTime()
  @State private var showingAlarmEditor = false
  @State private var showingDisableConfirmation = false
  private let alarmID = 1

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Alarm")

      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: "alarm.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(statusTint)
            .frame(width: 34, height: 34)
            .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

          VStack(alignment: .leading, spacing: 3) {
            Text("Wake alarm")
              .font(.headline.weight(.semibold))
              .foregroundStyle(OpenVitalsTheme.textPrimary)

            Text(statusDetail)
              .font(.caption.weight(.medium))
              .foregroundStyle(OpenVitalsTheme.textSecondary)
              .lineLimit(2)
              .minimumScaleFactor(0.78)
          }

          Spacer(minLength: 8)
        }

        Divider().overlay(OpenVitalsTheme.separator)

        HStack(alignment: .top, spacing: 12) {
          HomeAlarmSummaryColumn(
            title: "Alarm status",
            value: statusTitle
          )

          Rectangle()
            .fill(OpenVitalsTheme.separator)
            .frame(width: 1, height: 58)

          HomeAlarmSummaryColumn(
            title: "Wake time",
            value: wakeTimeText
          )
        }

        Divider().overlay(OpenVitalsTheme.separator)

        HStack(spacing: 10) {
          Button {
            draftAlarmTime = displayedAlarmScheduledAt ?? alarmTime
            showingAlarmEditor = true
          } label: {
            Label(alarmEditorButtonTitle, systemImage: alarmIsSet ? "pencil" : "alarm.badge.plus")
              .font(.subheadline.weight(.bold))
              .lineLimit(1)
              .minimumScaleFactor(0.80)
              .foregroundStyle(OpenVitalsTheme.graphite)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(OpenVitalsTheme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)

          Button(role: .destructive) {
            showingDisableConfirmation = true
          } label: {
            Label("Disable", systemImage: "bell.slash.fill")
              .font(.subheadline.weight(.bold))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .foregroundStyle(canDisableAlarm ? statusTint : OpenVitalsTheme.textTertiary)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(OpenVitalsTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .strokeBorder(OpenVitalsTheme.border, lineWidth: 1)
              }
          }
          .buttonStyle(.plain)
          .disabled(!canDisableAlarm)
        }
      }
      .padding(14)
      .cardSurface(tint: statusTint)
      .accessibilityElement(children: .contain)
    }
    .onAppear(perform: syncAlarmTimeFromDevice)
    .onChange(of: ble.lastAlarmScheduledAt) { _, _ in
      syncAlarmTimeFromDevice()
    }
    .onChange(of: ble.savedWakeAlarmScheduledAt) { _, _ in
      syncAlarmTimeFromDevice()
    }
    .sheet(isPresented: $showingAlarmEditor) {
      HomeAlarmEditorSheet(
        alarmTime: $draftAlarmTime,
        canSave: ble.canWriteAlarm,
        blockedReason: ble.alarmWriteSupportSummary
      ) { savedTime in
        alarmTime = savedTime
        ble.setWhoopAlarm(at: savedTime, alarmID: alarmID)
      }
    }
    .alert("Disable alarm?", isPresented: $showingDisableConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Disable", role: .destructive) {
        ble.disableWhoopAlarms()
      }
    } message: {
      Text("Disable alarms on the connected device.")
    }
  }

  private var wakeTimeText: String {
    if let scheduledAt = displayedAlarmScheduledAt {
      return Self.clockFormatter.string(from: scheduledAt)
    }
    return Self.clockFormatter.string(from: alarmTime)
  }

  private var alarmIsSet: Bool {
    displayedAlarmScheduledAt != nil
  }

  private var alarmEditorButtonTitle: String {
    alarmIsSet ? "Edit alarm" : "Set alarm"
  }

  private var canDisableAlarm: Bool {
    alarmIsSet && ble.canWriteAlarm
  }

  private var statusTitle: String {
    if ble.lastAlarmScheduledAt != nil {
      return "Alarm on"
    }
    if ble.savedWakeAlarmScheduledAt != nil {
      return "Alarm on"
    }
    if alarmCommandLooksDisabled {
      return "Alarm off"
    }
    if ble.canWriteAlarm {
      return "Not set"
    }
    return "Unavailable"
  }

  private var statusDetail: String {
    if let scheduledAt = ble.lastAlarmScheduledAt {
      return "Set for \(Self.clockFormatter.string(from: scheduledAt))"
    }
    if let savedWakeTime = ble.savedWakeAlarmScheduledAt {
      return "Saved locally for \(Self.clockFormatter.string(from: savedWakeTime))"
    }
    if alarmCommandLooksDisabled {
      return "Alarm disabled"
    }
    if ble.canWriteAlarm {
      return "Choose a wake time and save it"
    }
    return ble.alarmWriteSupportSummary
  }

  private var statusTint: Color {
    if displayedAlarmScheduledAt != nil || ble.canWriteAlarm {
      return OpenVitalsTheme.accent
    }
    return OpenVitalsTheme.textTertiary
  }

  private var alarmCommandLooksDisabled: Bool {
    ble.alarmCommandStatus.localizedCaseInsensitiveContains("disabled")
      || ble.lastAlarmEventSummary.localizedCaseInsensitiveContains("disabled")
  }

  private var displayedAlarmScheduledAt: Date? {
    ble.lastAlarmScheduledAt ?? ble.savedWakeAlarmScheduledAt
  }

  private func syncAlarmTimeFromDevice() {
    guard let scheduledAt = displayedAlarmScheduledAt else {
      return
    }
    alarmTime = scheduledAt
  }

  private static func defaultWakeTime() -> Date {
    Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
  }

  private static let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}

struct HomeAlarmSummaryColumn: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption.weight(.bold))
        .foregroundStyle(OpenVitalsTheme.textSecondary)
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.74)

      Text(value)
        .font(.title3.weight(.bold))
        .fontDesign(.rounded)
        .foregroundStyle(OpenVitalsTheme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct HomeAlarmEditorSheet: View {
  @Binding var alarmTime: Date
  let canSave: Bool
  let blockedReason: String
  let save: (Date) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Edit alarm")
          .font(.title2.weight(.bold))
          .foregroundStyle(OpenVitalsTheme.textPrimary)
        Text(canSave ? "Choose a wake time." : blockedReason)
          .font(.caption.weight(.medium))
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      DatePicker("Wake time", selection: $alarmTime, displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)

      HStack(spacing: 10) {
        Button {
          dismiss()
        } label: {
          Text("Cancel")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(OpenVitalsTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(OpenVitalsTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(OpenVitalsTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)

        Button {
          save(alarmTime)
          dismiss()
        } label: {
          Text("Save")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(canSave ? OpenVitalsTheme.graphite : OpenVitalsTheme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(canSave ? OpenVitalsTheme.accent : OpenVitalsTheme.separator, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
      }
    }
    .padding(20)
    .presentationDetents([.height(380), .medium])
    .presentationDragIndicator(.visible)
    .background(OpenVitalsTheme.appBackground.ignoresSafeArea())
  }
}

struct HomeDataAlgorithmsSection: View {
  let snapshots: [HealthMetricSnapshot]
  let openSnapshot: (HealthMetricSnapshot) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Data & Algorithms")

      VStack(spacing: 10) {
        ForEach(snapshots) { snapshot in
          Button {
            openSnapshot(snapshot)
          } label: {
            HomeDataAlgorithmRow(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct HomeDataAlgorithmRow: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: snapshot.systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 34, height: 34)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(snapshot.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(OpenVitalsTheme.textPrimary)
          .lineLimit(1)

        Text("\(snapshot.displayValue) | \(snapshot.status)")
          .font(.caption)
          .foregroundStyle(OpenVitalsTheme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }

      Spacer(minLength: 8)

      HealthSourceBadge(source: snapshot.source)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(OpenVitalsTheme.textTertiary)
    }
    .padding(14)
    .cardSurface(tint: tint)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(snapshot.title), \(snapshot.displayValue), \(snapshot.status)")
  }

  private var tint: Color {
    OpenVitalsTheme.routeTint(snapshot.route)
  }
}
