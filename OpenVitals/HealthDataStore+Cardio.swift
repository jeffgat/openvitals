import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  func cardioLoadWeeklyPoints() -> [CardioLoadDay] {
    cardioLoadPoints(range: "7D")
  }

  func cardioLoadPoints(range: String) -> [CardioLoadDay] {
    cardioLoadAlgorithmSummary(range: range).points
  }

  func cardioLoadAlgorithmSummary(
    range: String = "30D",
    calendar: Calendar = .current
  ) -> CardioLoadAlgorithmSummary {
    _ = range
    _ = calendar
    return emptyCardioLoadSummary(
      status: previewMissingData ? "No data" : "Needs activity",
      freshness: previewMissingData ? "Missing" : "No local data",
      source: .unavailable(
        previewMissingData
          ? "preview missing cardio load data"
          : "cardio load needs local OpenVitals activity sessions and daily activity metrics"
      )
    )
  }

  func cardioStatusRows() -> [HealthSummaryRow] {
    let points = cardioLoadWeeklyPoints()
    guard !points.isEmpty else {
      return [
        HealthSummaryRow("Calibrating", value: "No weekly HR + activity data yet", source: .unavailable("cardio inputs pending"), systemImage: "heart.circle")
      ]
    }
    let grouped = Dictionary(grouping: points, by: \.status)
    return ["Calibrating", "Detraining", "Maintaining", "Peaking", "Productive", "Fatigued", "Overtraining"].map { status in
      let days = grouped[status]?.count ?? 0
      let percent = Double(days) / Double(points.count)
      return HealthSummaryRow(
        status,
        value: days == 0 ? "0d | supported status state" : "\(days)d | \(Self.percentText(percent) ?? "0%") of visible week",
        source: .local("open_vitals.cardio_load.local_v1 status bands"),
        systemImage: "heart.circle"
      )
    }
  }

  func emptyCardioLoadSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> CardioLoadAlgorithmSummary {
    CardioLoadAlgorithmSummary(
      points: [],
      status: status,
      freshness: freshness,
      source: source,
      sessionCount: 0,
      activityDayCount: 0,
      hasBaseline: false
    )
  }

  func cardioLoadSnapshot(base snapshot: HealthMetricSnapshot) -> HealthMetricSnapshot {
    let summary = cardioLoadAlgorithmSummary(range: "30D")
    guard let latest = summary.latestPoint else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "load",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.cardioLoadTrendModel(base: snapshot.trend, summary: summary)
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: Self.numberText(latest.load, fractionDigits: 0) ?? "0",
      unit: "load",
      status: summary.hasBaseline ? latest.status : "Calibrating",
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: Self.cardioLoadTrendModel(base: snapshot.trend, summary: summary)
    )
  }

  func cardioLoadActivitySessions(from start: Date, to end: Date) -> [[String: Any]] {
    do {
      let report = try bridge.request(
        method: "activity.list_sessions",
        args: [
          "database_path": databasePath,
          "start_time_unix_ms": Self.unixMilliseconds(start),
          "end_time_unix_ms": Self.unixMilliseconds(end),
        ]
      )
      return report["sessions"] as? [[String: Any]] ?? []
    } catch {
      return []
    }
  }

  func cardioLoadActivityMetricsByName(sessionID: String?) -> [String: [String: Any]] {
    guard let sessionID else {
      return [:]
    }
    do {
      let report = try bridge.request(
        method: "activity.list_metrics",
        args: [
          "database_path": databasePath,
          "activity_session_id": sessionID,
        ]
      )
      let metrics = report["metrics"] as? [[String: Any]] ?? []
      return Dictionary(
        uniqueKeysWithValues: metrics.compactMap { metric in
          guard let name = metric["metric_name"] as? String else {
            return nil
          }
          return (name, metric)
        }
      )
    } catch {
      return [:]
    }
  }

  func cardioLoadContribution(
    from session: [String: Any],
    metrics: [String: [String: Any]],
    observedMaxHeartRate: Double?,
    calendar: Calendar
  ) -> CardioLoadSessionContribution? {
    guard let sessionID = session["session_id"] as? String,
          let startMs = Self.int64Value(session["start_time_unix_ms"]),
          let endMs = Self.int64Value(session["end_time_unix_ms"]),
          endMs > startMs else {
      return nil
    }

    let start = Date(timeIntervalSince1970: Double(startMs) / 1000)
    let end = Date(timeIntervalSince1970: Double(endMs) / 1000)
    let storedDurationSeconds = Self.doubleValue(metrics["duration"]?["value"])
      ?? Self.doubleValue(session["duration_ms"]).map { $0 / 1000 }
      ?? end.timeIntervalSince(start)
    let durationMinutes = max(storedDurationSeconds / 60, 0)
    guard durationMinutes >= 1 else {
      return nil
    }

    let zoneLoad = (1...5).reduce(0.0) { partial, zoneID in
      let seconds = Self.doubleValue(metrics["hr_zone_\(zoneID)_duration"]?["value"]) ?? 0
      return partial + max(seconds, 0) / 60.0 * Double(zoneID)
    }
    let load: Double
    if zoneLoad > 0.25 {
      load = zoneLoad
    } else {
      let sessionSamples = heartRateSeriesStore.samples(from: start, to: end)
      let averageHeartRate = Self.doubleValue(metrics["average_hr"]?["value"])
        ?? Self.averageHeartRate(in: sessionSamples)
      let sessionMaxHeartRate = Self.doubleValue(metrics["max_hr"]?["value"])
        ?? sessionSamples.map(\.bpm).max().map(Double.init)
      let restingHeartRate = heartRateSeriesStore.restingEstimate(forDayContaining: start, calendar: calendar)?.bpm
        ?? Self.liveHRDerivedRestingHeartRateSample()?.bpm
      guard let averageHeartRate,
            let restingHeartRate,
            let maxHeartRate = [sessionMaxHeartRate, observedMaxHeartRate].compactMap({ $0 }).max(),
            maxHeartRate >= restingHeartRate + 25 else {
        return nil
      }
      let reserveFraction = Self.clamp(
        (averageHeartRate - restingHeartRate) / max(maxHeartRate - restingHeartRate, 1),
        min: 0,
        max: 1
      )
      guard reserveFraction > 0.05 else {
        return nil
      }
      load = durationMinutes * 0.64 * exp(1.92 * reserveFraction)
    }

    guard load.isFinite, load > 0 else {
      return nil
    }
    return CardioLoadSessionContribution(
      sessionID: sessionID,
      start: start,
      end: end,
      dayStart: calendar.startOfDay(for: start),
      load: load,
      durationMinutes: durationMinutes
    )
  }

  func cardioLoadDailyComputations(
    contributions: [CardioLoadSessionContribution],
    dayStarts: [Date]
  ) -> [CardioLoadDailyComputation] {
    let grouped = Dictionary(grouping: contributions, by: \.dayStart)
    let dailyLoads = dayStarts.map { day -> Double in
      grouped[day, default: []].reduce(0) { $0 + $1.load }
    }
    let dailyDurations = dayStarts.map { day -> Double in
      grouped[day, default: []].reduce(0) { $0 + $1.durationMinutes }
    }

    return dayStarts.enumerated().map { index, day in
      let activityDaysSoFar = dailyLoads.prefix(index + 1).filter { $0 > 0 }.count
      let acuteStart = max(0, index - 6)
      let chronicStart = max(0, index - 27)
      let acuteValues = dailyLoads[acuteStart...index]
      let chronicValues = dailyLoads[chronicStart...index]
      let acute = acuteValues.reduce(0, +) / Double(max(acuteValues.count, 1))
      let chronic = chronicValues.reduce(0, +) / Double(max(chronicValues.count, 1))
      return CardioLoadDailyComputation(
        dayStart: day,
        load: dailyLoads[index],
        durationMinutes: dailyDurations[index],
        status: Self.cardioLoadTrainingStatus(
          acute: acute,
          chronic: chronic,
          activityDayCount: activityDaysSoFar
        )
      )
    }
  }

  func energyStressChartPoints() -> [EnergyStressPoint] {
    guard !previewMissingData else {
      return []
    }
    let summary = energyBankAlgorithmSummary()
    return summary.hasData ? summary.points : []
  }

  func energyStressSelectedPoint() -> EnergyStressPoint? {
    energyStressChartPoints().first { $0.id == "2130" } ?? energyStressChartPoints().last
  }

  func healthMonitorExportRows() -> [HealthSummaryRow] {
    guard localDataSupportsExport else {
      return []
    }
    return [
      HealthSummaryRow("Local health export", value: "Packet reports and reference comparisons available", source: .bridge("local cached bridge reports"), systemImage: "square.and.arrow.up")
    ]
  }

  func applyPreviewState(_ state: HealthPreviewState) {
    attemptedCatalogLoad = true
    switch state {
    case .populated:
      previewMissingData = false
      primarySleepDetail = nil
      packetInputStatus = "No run"
      packetScoreStatus = "No run"
      externalSleepImportStatus = "External sleep imports disabled"
      packetInputReports = [:]
      packetScoreReports = [:]
      referenceComparisonReports = [:]
      referenceRunStatusByFamily = [:]
      calibrationLabelsImported = false
      calibrationRunComplete = false
    case .missing:
      previewMissingData = true
      primarySleepDetail = nil
      packetInputStatus = "No run"
      packetScoreStatus = "No run"
      externalSleepImportStatus = "External sleep imports disabled"
      packetInputReports = [:]
      packetScoreReports = [:]
      referenceComparisonReports = [:]
      referenceRunStatusByFamily = [:]
      algorithmDefinitions = []
      referenceDefinitions = []
      selectedAlgorithmByFamily = [:]
      catalogStatus = "Preview missing catalog"
      catalogSource = .unavailable("preview missing catalog")
      calibrationLabelsImported = false
      calibrationRunComplete = false
    case .recoveryNoData:
      previewMissingData = false
      primarySleepDetail = nil
      packetInputStatus = "No run"
      packetScoreStatus = "No run"
      externalSleepImportStatus = "External sleep imports disabled"
      packetInputReports = [:]
      packetScoreReports = [:]
      referenceComparisonReports = [:]
      referenceRunStatusByFamily = [:]
      calibrationLabelsImported = false
      calibrationRunComplete = false
    case .recoveryBridgeData:
      applyRecoveryBridgeDataPreview()
    case .recoveryPacketRunBlocked:
      applyRecoveryPacketRunBlockedPreview()
    }
    refreshHealthDashboardSnapshots()
  }

  func applyRecoveryBridgeDataPreview() {
    previewMissingData = false
    packetInputStatus = "Bridge packet-derived inputs extracted"
    packetScoreStatus = "Bridge packet-derived scores recomputed"
    referenceComparisonReports = [:]
    referenceRunStatusByFamily = [:]
    calibrationLabelsImported = false
    calibrationRunComplete = false

    let window = Self.currentDailyMetricWindow()
    let dates = previewRecoveryDateWindows(endingAt: window.start, count: 4)
    let scoreRows = zip(dates, [58.0, 64.0, 71.0, 76.0]).map { dateWindow, score in
      [
        "date": dateWindow.dateKey,
        "score_0_to_100": score,
      ] as [String: Any]
    }
    packetScoreReports = [
      "recovery": [
        "schema": "open_vitals.preview.recovery_score.v1",
        "pass": true,
        "daily": scoreRows,
        "score_result": [
          "output": [
            "score_0_to_100": 76.0,
          ],
        ],
        "provided_vitals": [
          "trusted_metric_input": true,
          "source": "preview packet-derived recovery vitals",
          "respiratory_rate_rpm": 14.7,
          "respiratory_rate_baseline_rpm": 14.4,
          "skin_temp_delta_c": 0.2,
          "quality_flags": [],
        ],
      ],
    ]

    let metrics = dates.enumerated().flatMap { index, dateWindow -> [[String: Any]] in
      let hrv = [49.0, 52.0, 55.0, 58.0][index]
      let rhr = [57.0, 56.0, 55.0, 54.0][index]
      let rr = [14.9, 14.8, 14.7, 14.6][index]
      let spo2 = [96.0, 97.0, 97.0, 98.0][index]
      let temp = [-0.1, 0.0, 0.1, 0.2][index]
      return [
        Self.recoveryPreviewMetricRow(dateWindow: dateWindow, metricID: "hrv_rmssd_ms", metricName: "Resting HRV", valueKey: "hrv_rmssd_ms", value: hrv, confidence: 0.84),
        Self.recoveryPreviewMetricRow(dateWindow: dateWindow, metricID: "resting_hr_bpm", metricName: "Resting HR", valueKey: "resting_hr_bpm", value: rhr, confidence: 0.86),
        Self.recoveryPreviewMetricRow(dateWindow: dateWindow, metricID: "respiratory_rate_rpm", metricName: "Respiratory Rate", valueKey: "respiratory_rate_rpm", value: rr, confidence: 0.81),
        Self.recoveryPreviewMetricRow(dateWindow: dateWindow, metricID: "oxygen_saturation_percent", metricName: "Oxygen Saturation", valueKey: "oxygen_saturation_percent", value: spo2, confidence: 0.78),
        Self.recoveryPreviewMetricRow(dateWindow: dateWindow, metricID: "skin_temperature_delta_c", metricName: "Wrist Temperature", valueKey: "skin_temperature_delta_c", value: temp, confidence: 0.79),
      ]
    }
    packetInputReports = [
      "daily_recovery": [
        "schema": "open_vitals.preview.daily_recovery_metrics.v1",
        "metrics": metrics,
      ],
    ]

    primarySleepDetail = PrimarySleepDetail(
      id: "preview-primary-sleep",
      dateLabel: "Today",
      startLabel: "10:48 PM",
      endLabel: "6:42 AM",
      durationText: "7h 18m",
      timeInBedText: "7h 54m",
      scoreText: "82",
      qualityText: "Good",
      source: .bridge("preview sleep score output"),
      stages: []
    )
  }

  func applyRecoveryPacketRunBlockedPreview() {
    previewMissingData = false
    primarySleepDetail = nil
    packetInputStatus = "Bridge input extraction blocked: no trusted recovery packet inputs"
    packetScoreStatus = "Bridge score run blocked: recovery is not ready"
    referenceComparisonReports = [:]
    referenceRunStatusByFamily = [:]
    calibrationLabelsImported = false
    calibrationRunComplete = false

    let window = Self.currentDailyMetricWindow()
    let metrics = [
      Self.recoveryPreviewUnavailableRow(dateWindow: window, metricID: "hrv_rmssd_ms", metricName: "Resting HRV", blocker: "no_trusted_hrv_rr_intervals"),
      Self.recoveryPreviewUnavailableRow(dateWindow: window, metricID: "respiratory_rate_rpm", metricName: "Respiratory Rate", blocker: "respiratory_rate_semantics_unverified"),
      Self.recoveryPreviewUnavailableRow(dateWindow: window, metricID: "oxygen_saturation_percent", metricName: "Oxygen Saturation", blocker: "oxygen_saturation_decoder_not_implemented"),
      Self.recoveryPreviewUnavailableRow(dateWindow: window, metricID: "skin_temperature_delta_c", metricName: "Wrist Temperature", blocker: "temperature_units_unverified"),
    ]
    packetInputReports = [
      "daily_recovery": [
        "schema": "open_vitals.preview.daily_recovery_metrics.v1",
        "metrics": metrics,
      ],
      "recovery_unavailable_status": [
        "schema": "open_vitals.preview.recovery-unavailable-daily-status-report.v1",
        "pass": true,
        "statuses": metrics,
      ],
    ]
    packetScoreReports = [:]
  }

  func previewRecoveryDateWindows(endingAt endDate: Date, count: Int) -> [DailyMetricWindow] {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return (0..<count).compactMap { offset in
      let start = calendar.date(byAdding: .day, value: offset - count + 1, to: endDate)
        ?? endDate.addingTimeInterval(Double(offset - count + 1) * 86_400)
      return Self.dailyMetricWindow(for: start, calendar: calendar)
    }
  }

  static func dailyMetricWindow(for start: Date, calendar: Calendar) -> DailyMetricWindow {
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = calendar.timeZone
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    isoFormatter.formatOptions = [.withInternetDateTime]
    return DailyMetricWindow(
      dateKey: dateFormatter.string(from: start),
      timezone: calendar.timeZone.identifier,
      start: start,
      end: end,
      startISO: isoFormatter.string(from: start),
      endISO: isoFormatter.string(from: end),
      startTimeUnixMS: unixMilliseconds(start),
      endTimeUnixMS: unixMilliseconds(end)
    )
  }

  static func recoveryPreviewMetricRow(
    dateWindow: DailyMetricWindow,
    metricID: String,
    metricName: String,
    valueKey: String,
    value: Double,
    confidence: Double
  ) -> [String: Any] {
    var row = recoveryPreviewBaseRow(
      dateWindow: dateWindow,
      metricID: metricID,
      metricName: metricName,
      sourceKind: "device_sensor",
      confidence: confidence,
      blocker: nil
    )
    row[valueKey] = value
    return row
  }

  static func recoveryPreviewUnavailableRow(
    dateWindow: DailyMetricWindow,
    metricID: String,
    metricName: String,
    blocker: String
  ) -> [String: Any] {
    recoveryPreviewBaseRow(
      dateWindow: dateWindow,
      metricID: metricID,
      metricName: metricName,
      sourceKind: "unavailable",
      confidence: 0,
      blocker: blocker
    )
  }

  static func recoveryPreviewBaseRow(
    dateWindow: DailyMetricWindow,
    metricID: String,
    metricName: String,
    sourceKind: String,
    confidence: Double,
    blocker: String?
  ) -> [String: Any] {
    let metricToken = metricIDToken(metricID)
    let inputs: [String: Any] = [
      "metric_id": metricID,
      "metric_name": metricName,
      "blocker_reasons": blocker.map { [$0] } ?? [],
    ]
    let provenance: [String: Any] = [
      "algorithm": sourceKind == "device_sensor" ? "open_vitals.preview.recovery_sensor.device_sensor.v0" : "open_vitals.preview.recovery.unavailable_status.v0",
      "source_kind": sourceKind,
      "metric_id": metricID,
      "metric_name": metricName,
      "blocker_reasons": blocker.map { [$0] } ?? [],
    ]
    let flags = blocker.map { [$0, "source_kind_\(sourceKind)"] } ?? ["source_kind_\(sourceKind)"]
    return [
      "daily_metric_id": "preview-\(metricToken)-\(dateWindow.dateKey)",
      "date_key": dateWindow.dateKey,
      "timezone": dateWindow.timezone,
      "start_time_unix_ms": dateWindow.startTimeUnixMS,
      "end_time_unix_ms": dateWindow.endTimeUnixMS,
      "source_kind": sourceKind,
      "confidence": confidence,
      "inputs_json": jsonString(inputs),
      "quality_flags_json": jsonString(flags),
      "provenance_json": jsonString(provenance),
    ]
  }
}
