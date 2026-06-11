import SwiftUI

struct HomeDashboardView: View {
  @EnvironmentObject private var model: OpenVitalsAppModel
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void
  @State private var showingScoreDatePicker = false
  @State private var selectedHealthMonitorTrend: HealthMetricSnapshot?
  @State private var scoreSyncIsPreparing = false
  @State private var scoreSyncWaitingForBand = false

  var body: some View {
    let dashboard = dashboardMetrics
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeDailyScoreCard(
          scores: dashboard.scoreSnapshots,
          syncDetail: homeScoreSyncDetail,
          syncButtonTitle: homeScoreSyncButtonTitle,
          syncIsRunning: homeScoreSyncIsRunning,
          syncCanRun: homeScoreSyncCanRun,
          syncAction: startHomeScoreSync,
          openScore: openHealth
        )

        if !dashboard.missingDataItems.isEmpty {
          HomeMissingDataSection(
            items: dashboard.missingDataItems,
            openItem: { openHealth($0.route) }
          )
        }

        HomeHealthMonitorSection(
          snapshots: dashboard.healthMonitorSnapshots,
          openSnapshot: openHealthMonitorSnapshot
        )

        HomeAlarmSection(ble: model.ble)

        HomeDataAlgorithmsSection(
          snapshots: dashboard.dataAlgorithmSnapshots,
          openSnapshot: { openHealth($0.route) }
        )

      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .scrollClipDisabled()
    .openVitalsScreenBackground()
    .navigationTitle("Today")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .overlay(alignment: .top) {
      HomeTopScrollFade()
        .allowsHitTesting(false)
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HomeStartActivityFloatingButton(session: model.activitySession)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        ScoreDateTitleButton(
          title: homeTitle,
          subtitle: nil,
          action: { showingScoreDatePicker = true }
        )
      }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView()
        } label: {
          Image(systemName: "applewatch")
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(deviceToolbarTint)
        }
        .accessibilityLabel("Device")
        .accessibilityValue(deviceToolbarAccessibilityValue)
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Home")
    }
    .task {
      healthStore.loadBridgeCatalogsIfNeeded()
      healthStore.loadPersistedPacketScoresIfNeeded()
    }
    .onChange(of: model.ble.historicalSyncStatus) { _, newValue in
      handleHomeScoreSyncStatusChange(newValue)
    }
    .sheet(isPresented: $showingScoreDatePicker) {
      ScoreDatePickerSheet(
        title: "Daily Scores",
        routes: [.sleep, .recovery, .strain],
        snapshots: scorePickerSnapshots,
        selectedDate: $selectedDate
      )
    }
    .sheet(item: $selectedHealthMonitorTrend) { snapshot in
      SleepV2BevelTrendSheet(snapshot: snapshot)
    }
  }

  private var scorePickerSnapshots: [HealthMetricSnapshot] {
    let snapshots = healthStore.healthDashboardExploreSnapshots
    return [
      homeSnapshot(for: .sleep, in: snapshots),
      homeSnapshot(for: .recovery, in: snapshots),
      homeSnapshot(for: .strain, in: snapshots),
    ]
  }

  private var homeTitle: String {
    ScoreDateTimeline.dateLabel(for: selectedDate)
  }

  private var deviceToolbarTint: Color {
    deviceToolbarConnected ? OpenVitalsTheme.accent : OpenVitalsTheme.textTertiary
  }

  private var deviceToolbarAccessibilityValue: String {
    deviceToolbarConnected ? "Connected" : "Disconnected"
  }

  private var deviceToolbarConnected: Bool {
    let state = model.ble.connectionState.lowercased()
    return state == "ready" || state == "connected"
  }

  private var homeScoreSyncIsRunning: Bool {
    scoreSyncIsPreparing || model.ble.isHistoricalSyncing || healthStore.healthMetricWorkIsRunning
  }

  private var homeScoreSyncCanRun: Bool {
    model.ble.canSyncHistorical && !homeScoreSyncIsRunning
  }

  private var homeScoreSyncButtonTitle: String {
    if scoreSyncIsPreparing {
      return "Preparing"
    }
    if model.ble.isHistoricalSyncing {
      return "Syncing"
    }
    if healthStore.healthMetricWorkIsRunning {
      return "Updating"
    }
    return "Sync"
  }

  private var homeScoreSyncDetail: String {
    if scoreSyncIsPreparing {
      return model.dailyMetricSyncStatus
    }
    if model.ble.isHistoricalSyncing {
      return "\(homeHistoricalPacketText) | \(model.ble.historicalSyncStatus)"
    }
    if healthStore.healthMetricWorkIsRunning {
      return healthStore.healthMetricRefreshStatus
    }
    if model.ble.historicalSyncStatus == "failed" {
      return model.ble.lastSyncFailure?.message ?? "Band sync failed"
    }
    if let completedAt = model.ble.lastHistoricalSyncCompletedAt {
      let relative = HealthDataStore.relativeText(for: completedAt) ?? completedAt.formatted(date: .omitted, time: .shortened)
      return "Last band sync \(relative) | \(healthStore.packetScoreStatus)"
    }
    if model.ble.canSyncHistorical {
      return "Ready for Sleep, Recovery, and Strain"
    }
    return "Connect device to sync daily scores"
  }

  private var homeHistoricalPacketText: String {
    let packetCount = model.ble.historicalPacketCount
    return packetCount == 1 ? "1 packet" : "\(packetCount) packets"
  }

  private func landingSnapshot(for route: HealthRoute, in snapshots: [HealthMetricSnapshot]) -> HealthMetricSnapshot {
    snapshots.first { $0.route == route } ?? healthStore.snapshot(for: route)
  }

  private func homeSnapshot(for route: HealthRoute, in snapshots: [HealthMetricSnapshot]) -> HealthMetricSnapshot {
    let snapshot = landingSnapshot(for: route, in: snapshots)
    guard route == .strain, snapshot.unit != "%" else {
      return snapshot
    }
    let rawValue = firstNumber(in: snapshot.displayValue) ?? firstNumber(in: snapshot.value) ?? 0
    let percent = min(max(Int((rawValue / 21 * 100).rounded()), 0), 100)
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "\(percent)",
      unit: "%",
      status: snapshot.status,
      freshness: snapshot.freshness,
      provenance: snapshot.provenance,
      source: snapshot.source,
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: snapshot.trend
    )
  }

  private func openHealth(_ route: HealthRoute) {
    openHealthRoute(route)
    model.recordUIAction("health.deep_link.opened", detail: route.title)
  }

  private func openHealthMonitorSnapshot(_ snapshot: HealthMetricSnapshot) {
    if snapshot.id == "resting-hr" || snapshot.id == "resting-hrv" {
      selectedHealthMonitorTrend = snapshot
    } else {
      openHealth(.healthMonitor)
    }
  }

  private func startHomeScoreSync() {
    guard !homeScoreSyncIsRunning else {
      return
    }
    healthStore.loadBridgeCatalogsIfNeeded()
    scoreSyncIsPreparing = true
    scoreSyncWaitingForBand = false
    model.recordUIAction("home.daily_scores.sync.requested", detail: model.ble.historicalSyncStatus)

    guard model.ble.canSyncHistorical else {
      scoreSyncIsPreparing = false
      return
    }

    model.startDailyMetricSyncCaptureAndHistoricalSync { started in
      scoreSyncIsPreparing = false
      scoreSyncWaitingForBand = started
    }
  }

  private func handleHomeScoreSyncStatusChange(_ status: String) {
    guard scoreSyncWaitingForBand else {
      return
    }
    if status == "synced" {
      scoreSyncWaitingForBand = false
      scoreSyncIsPreparing = true
      model.finishDailyMetricSyncCaptureIfNeeded {
        scoreSyncIsPreparing = false
        healthStore.refreshHealthMetrics()
      }
    } else if status == "failed" {
      scoreSyncWaitingForBand = false
      scoreSyncIsPreparing = true
      model.finishDailyMetricSyncCaptureIfNeeded {
        scoreSyncIsPreparing = false
      }
    }
  }

  private var dashboardMetrics: HomeDashboardMetrics {
    let snapshots = healthStore.healthDashboardExploreSnapshots
    let sleep = homeSnapshot(for: .sleep, in: snapshots)
    let recovery = homeSnapshot(for: .recovery, in: snapshots)
    let strain = homeSnapshot(for: .strain, in: snapshots)
    return HomeDashboardMetrics(
      scoreSnapshots: [
        ScoreDateTimeline.datedSnapshot(from: sleep, date: selectedDate),
        ScoreDateTimeline.datedSnapshot(from: recovery, date: selectedDate),
        ScoreDateTimeline.datedSnapshot(from: strain, date: selectedDate),
      ],
      healthMonitorSnapshots: healthStore.healthDashboardVitalSnapshots,
      dataAlgorithmSnapshots: healthStore.healthDashboardAlgorithmSnapshots.filter {
        [.packetInputs, .algorithms].contains($0.route)
      },
      missingDataItems: healthStore.homeMissingDataItems()
    )
  }

  private struct HomeDashboardMetrics {
    let scoreSnapshots: [HealthMetricSnapshot]
    let healthMonitorSnapshots: [HealthMetricSnapshot]
    let dataAlgorithmSnapshots: [HealthMetricSnapshot]
    let missingDataItems: [HomeMissingDataItem]
  }
}
