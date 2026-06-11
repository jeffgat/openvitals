import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  nonisolated static func packetInputBridgeReports(databasePath: String) -> Result<[String: [String: Any]], Error> {
    let bridge = OpenVitalsRustBridge()
    let featureWindow = packetInputFeatureWindow()
    let summaryArgs: [String: Any] = [
      "database_path": databasePath,
      "start": featureWindow.start,
      "end": featureWindow.end,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "require_owned_captures": false,
      "require_scores_ready": true,
      "max_step_candidate_fields": 100,
      "max_step_ingest_candidate_fields": 1_000,
      "hrv_min_rr_intervals_to_compute": 2,
      "hrv_baseline_min_days": 3,
      "hrv_require_baseline": false,
      "resting_hr_baseline_min_days": 3,
      "resting_hr_require_baseline": false,
      "resting_hr_daily_rollup": restingHeartRateDailyRollupArgs(databasePath: databasePath, writeMetric: true),
      "step_counter_daily_rollup": stepCounterDailyRollupArgs(databasePath: databasePath, writeMetric: true),
      "step_counter_hourly_rollup": stepCounterHourlyRollupArgs(databasePath: databasePath, writeMetric: true),
      "activity_unavailable_daily_status": activityUnavailableDailyStatusArgs(databasePath: databasePath, writeMetric: true),
      "energy_daily_rollup": energyDailyRollupArgs(
        databasePath: databasePath,
        restingHeartRateRollup: nil,
        writeMetric: true
      ),
      "energy_hourly_rollup": energyHourlyRollupArgs(
        databasePath: databasePath,
        restingHeartRateRollup: nil,
        writeMetric: true
      ),
      "energy_unavailable_daily_status": energyDailyRollupArgs(
        databasePath: databasePath,
        restingHeartRateRollup: nil,
        writeMetric: true
      ),
      "recovery_sensor_daily_rollup": recoverySensorDailyRollupArgs(databasePath: databasePath, writeMetric: true),
      "recovery_unavailable_daily_status": recoveryUnavailableDailyStatusArgs(databasePath: databasePath, writeMetric: true),
      "daily_activity_metrics": dailyActivityMetricListArgs(databasePath: databasePath),
      "hourly_activity_metrics": hourlyActivityMetricListArgs(databasePath: databasePath),
      "daily_recovery_metrics": dailyRecoveryMetricListArgs(databasePath: databasePath),
    ]
    do {
      let summary = try bridge.request(method: "metrics.packet_input_summary", args: summaryArgs)
      let rawReports = summary["reports"] as? [String: Any] ?? [:]
      let reports = rawReports.reduce(into: [String: [String: Any]]()) { output, element in
        if let report = element.value as? [String: Any] {
          output[element.key] = report
        }
      }
      return .success(reports)
    } catch {
      return .failure(error)
    }
  }

  nonisolated static func packetInputFeatureWindow(
    now: Date = Date(),
    lookbackDays: Int = 14
  ) -> (start: String, end: String) {
    let lookback = TimeInterval(max(1, lookbackDays) * 24 * 60 * 60)
    let start = now.addingTimeInterval(-lookback)
    let end = now.addingTimeInterval(60 * 60)
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return (formatter.string(from: start), formatter.string(from: end))
  }

  nonisolated static func restingHeartRateDailyRollupArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()

    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "baseline_min_days": 3,
      "require_baseline": false,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func stepCounterDailyRollupArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()
    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func recoveryUnavailableDailyStatusArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()
    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_rr_intervals_to_compute": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func recoverySensorDailyRollupArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()
    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_rr_intervals_to_compute": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func activityUnavailableDailyStatusArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()
    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func stepCounterHourlyRollupArgs(
    databasePath: String,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentHourlyMetricWindow()
    return [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start_time_unix_ms": window.startTimeUnixMS,
      "end_time_unix_ms": window.endTimeUnixMS,
      "min_sample_count": 2,
      "write_metric": writeMetric,
    ]
  }

  nonisolated static func dailyActivityMetricListArgs(databasePath: String) -> [String: Any] {
    let window = currentDailyMetricWindow()
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let historyStart = calendar.date(byAdding: .day, value: -29, to: window.start)
      ?? window.start.addingTimeInterval(-29 * 86_400)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func hourlyActivityMetricListArgs(databasePath: String) -> [String: Any] {
    let window = currentHourlyMetricWindow()
    let historyStart = window.start.addingTimeInterval(-48 * 3_600)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func dailyRecoveryMetricListArgs(databasePath: String) -> [String: Any] {
    let window = currentDailyMetricWindow()
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let historyStart = calendar.date(byAdding: .day, value: -29, to: window.start)
      ?? window.start.addingTimeInterval(-29 * 86_400)
    return [
      "database_path": databasePath,
      "start_time_unix_ms": Int64((historyStart.timeIntervalSince1970 * 1000).rounded()),
      "end_time_unix_ms": window.endTimeUnixMS,
    ]
  }

  nonisolated static func energyDailyRollupArgs(
    databasePath: String,
    restingHeartRateRollup: [String: Any]?,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentDailyMetricWindow()
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")

    var args: [String: Any] = [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_heart_rate_samples": 2,
      "write_metric": writeMetric,
    ]

    let profile = OnboardingProfileSnapshot()
    if profile.weightGrams > 0 {
      let weightKg = Double(profile.weightGrams) / 1000.0
      if (25.0...300.0).contains(weightKg) {
        args["profile_weight_kg"] = weightKg
      }
    }
    if let ageYears = profileAgeYears(from: profile.dateOfBirthString, calendar: calendar) {
      args["profile_age_years"] = ageYears
      args["max_hr_bpm"] = max(120.0, min(210.0, 208.0 - 0.7 * Double(ageYears)))
    }
    if let sex = normalizedProfileSex(profile.genderRaw) {
      args["profile_sex"] = sex
    }
    if let restingHeartRate = nonisolatedDoubleValue(restingHeartRateRollup?["resting_hr_bpm"]) {
      args["resting_hr_bpm"] = restingHeartRate
    }
    return args
  }

  nonisolated static func energyHourlyRollupArgs(
    databasePath: String,
    restingHeartRateRollup: [String: Any]?,
    writeMetric: Bool
  ) -> [String: Any] {
    let window = currentHourlyMetricWindow()
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")

    var args: [String: Any] = [
      "database_path": databasePath,
      "date_key": window.dateKey,
      "timezone": window.timezone,
      "start": window.startISO,
      "end": window.endISO,
      "min_owned_captures": 2,
      "require_trusted_evidence": false,
      "min_heart_rate_samples": 2,
      "write_metric": writeMetric,
    ]

    let profile = OnboardingProfileSnapshot()
    if profile.weightGrams > 0 {
      let weightKg = Double(profile.weightGrams) / 1000.0
      if (25.0...300.0).contains(weightKg) {
        args["profile_weight_kg"] = weightKg
      }
    }
    if let ageYears = profileAgeYears(from: profile.dateOfBirthString, calendar: calendar) {
      args["profile_age_years"] = ageYears
      args["max_hr_bpm"] = max(120.0, min(210.0, 208.0 - 0.7 * Double(ageYears)))
    }
    if let sex = normalizedProfileSex(profile.genderRaw) {
      args["profile_sex"] = sex
    }
    if let restingHeartRate = nonisolatedDoubleValue(restingHeartRateRollup?["resting_hr_bpm"]) {
      args["resting_hr_bpm"] = restingHeartRate
    }
    return args
  }

  nonisolated static func currentDailyMetricWindow() -> DailyMetricWindow {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let start = calendar.startOfDay(for: Date())
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
      startTimeUnixMS: Int64((start.timeIntervalSince1970 * 1000).rounded()),
      endTimeUnixMS: Int64((end.timeIntervalSince1970 * 1000).rounded())
    )
  }

  nonisolated static func currentHourlyMetricWindow() -> DailyMetricWindow {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let now = Date()
    let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
    let start = calendar.date(from: components) ?? now
    let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)

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
      startTimeUnixMS: Int64((start.timeIntervalSince1970 * 1000).rounded()),
      endTimeUnixMS: Int64((end.timeIntervalSince1970 * 1000).rounded())
    )
  }

  static func metricDateKey(for date: Date, calendar inputCalendar: Calendar = .current) -> String {
    var calendar = inputCalendar
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let start = calendar.startOfDay(for: date)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: start)
  }

  nonisolated static func nonisolatedDoubleValue(_ value: Any?) -> Double? {
    if let double = value as? Double {
      return double
    }
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return nil
  }

  nonisolated static func profileAgeYears(from dateOfBirthString: String, calendar: Calendar) -> Int? {
    guard !dateOfBirthString.isEmpty else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let dateOfBirth = formatter.date(from: dateOfBirthString) else {
      return nil
    }
    let years = calendar.dateComponents([.year], from: dateOfBirth, to: Date()).year
    guard let years, (13...120).contains(years) else {
      return nil
    }
    return years
  }

  nonisolated static func normalizedProfileSex(_ rawValue: String) -> String? {
    switch rawValue {
    case "female", "male":
      return rawValue
    default:
      return nil
    }
  }
}
