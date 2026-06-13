import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

struct OpenVitalsLocalDataExportResult {
  let url: URL
  let manifestURL: URL?
  let manifestError: String?
  let fileCount: Int
  let byteCount: UInt64
  let validation: OpenVitalsLocalDataExportValidation

  var manifestStatusSuffix: String {
    if let manifestURL {
      return " | manifest \(manifestURL.lastPathComponent)"
    }
    if let manifestError, !manifestError.isEmpty {
      return " | manifest sidecar error: \(manifestError)"
    }
    return ""
  }
}

struct OpenVitalsLocalDataExportProgress {
  let title: String
  let detail: String
  let fractionCompleted: Double?

  var boundedFractionCompleted: Double? {
    guard let fractionCompleted else {
      return nil
    }
    return min(max(fractionCompleted, 0), 1)
  }

  var percentText: String? {
    guard let boundedFractionCompleted else {
      return nil
    }
    return "\(Int((boundedFractionCompleted * 100).rounded()))%"
  }

  var statusText: String {
    if let percentText {
      return "\(title): \(detail) | \(percentText)"
    }
    return "\(title): \(detail)"
  }
}

enum OpenVitalsLocalDataExportError: LocalizedError, CustomStringConvertible {
  case invalidBundleJSON(String)
  case outputAlreadyExists(String)

  var errorDescription: String? {
    description
  }

  var description: String {
    switch self {
    case .invalidBundleJSON(let message):
      return "Bundle JSON validation failed: \(message)"
    case .outputAlreadyExists(let path):
      return "Bundle output already exists: \(path)"
    }
  }
}

struct OpenVitalsLocalDataExportValidation {
  let requiredOvernightSessionID: String?
  let bundleJSONValid: Bool
  let bundleJSONValidationError: String?
  let rawNotificationsIncluded: Bool
  let historicalRangePollsIncluded: Bool
  let commandWritesIncluded: Bool
  let overnightEventLogIncluded: Bool
  let checkpointsIncluded: Bool
  let checkpointLatestIncluded: Bool
  let manifestIncluded: Bool
  let manifestSessionMatches: Bool
  let manifestFinalized: Bool
  let statusIncluded: Bool
  let statusSessionMatches: Bool
  let statusFinalized: Bool
  let crashMarkerIncluded: Bool
  let crashMarkerJSONValid: Bool
  let crashMarkerSessionMatches: Bool
  let crashMarkerFinalized: Bool
  let exportSelfIncluded: Bool
  let sqliteDatabaseIncluded: Bool
  let sqliteDatabaseExists: Bool
  let sqliteDatabaseOpenable: Bool
  let sqliteStorageCheckPassed: Bool
  let sqliteDatabasePath: String?
  let sqliteMirrorSessionExists: Bool
  let sqliteMirrorRawNotificationCount: Int
  let sqliteMirrorHistoricalRangePollCount: Int
  let sqliteMirrorSuccessfulHistoricalRangePollCount: Int
  let bleLogIncluded: Bool
  let bleLogByteCount: UInt64
  let bleLogSessionIDFound: Bool
  let bleLiveLogIncluded: Bool
  let bleLiveLogByteCount: UInt64
  let bleLiveLogSessionIDFound: Bool
  let rawNotificationCount: Int
  let historicalRangePollRecordCount: Int
  let successfulHistoricalRangePollCount: Int
  let commandWriteRecordCount: Int
  let commandWriteChecksumPresentCount: Int
  let commandWriteChecksumMissingCount: Int
  let commandWriteChecksumMismatchCount: Int
  let commandWriteHexInvalidCount: Int
  let commandWriteParseErrorCount: Int
  let historicalPacketCount: Int?
  let k18Count: Int?
  let k24Count: Int?
  let k25Count: Int?
  let k26Count: Int?
  let packet47Count: Int?
  let event17Count: Int?
  let event29Count: Int?
  let metadata49Count: Int?
  let metadata56Count: Int?
  let firstRawNotificationAt: String?
  let lastRawNotificationAt: String?
  let maxRawNotificationGapSeconds: Double?
  let rawNotificationGapsOver5Minutes: Int
  let rawNotificationChecksumPresentCount: Int
  let rawNotificationChecksumMissingCount: Int
  let rawNotificationChecksumMismatchCount: Int
  let rawNotificationValueHexInvalidCount: Int
  let rawNotificationParseErrorCount: Int
  let historicalRangeChecksumPresentCount: Int
  let historicalRangeChecksumMissingCount: Int
  let historicalRangeChecksumMismatchCount: Int
  let historicalRangeHexInvalidCount: Int
  let historicalRangePollParseErrorCount: Int
  let overnightEventLogRecordCount: Int
  let overnightEventLogParseErrorCount: Int
  let proofSidecarWarningCount: Int
  let proofSidecarWarnings: [String]
  let issues: [String]

  var passed: Bool {
    bundleJSONValid && issues.isEmpty
  }

  var summary: String {
    if passed {
      if requiredOvernightSessionID != nil {
        return "Validated bundle JSON, overnight files, checkpoints, crash marker, \(rawNotificationCount) raw, \(commandWriteRecordCount) command writes, checksums \(rawNotificationChecksumPresentCount)/\(rawNotificationCount), \(successfulHistoricalRangePollCount) successful range responses, \(overnightEventLogRecordCount) events, no proof sidecar warnings, \(bleLiveLogByteCount) live BLE log bytes with session marker, SQLite mirror raw \(sqliteMirrorRawNotificationCount), and export self-exclusion"
      }
      return "Validated bundle JSON and export self-exclusion"
    }
    return issues.joined(separator: " | ")
  }

  var jsonObject: [String: Any] {
    [
      "required_overnight_session_id": requiredOvernightSessionID ?? NSNull(),
      "bundle_json_valid": bundleJSONValid,
      "bundle_json_validation_error": bundleJSONValidationError ?? NSNull(),
      "raw_notifications_included": rawNotificationsIncluded,
      "historical_range_polls_included": historicalRangePollsIncluded,
      "command_writes_included": commandWritesIncluded,
      "overnight_event_log_included": overnightEventLogIncluded,
      "checkpoints_included": checkpointsIncluded,
      "checkpoint_latest_included": checkpointLatestIncluded,
      "manifest_included": manifestIncluded,
      "manifest_session_matches": manifestSessionMatches,
      "manifest_finalized": manifestFinalized,
      "status_included": statusIncluded,
      "status_session_matches": statusSessionMatches,
      "status_finalized": statusFinalized,
      "crash_marker_included": crashMarkerIncluded,
      "crash_marker_json_valid": crashMarkerJSONValid,
      "crash_marker_session_matches": crashMarkerSessionMatches,
      "crash_marker_finalized": crashMarkerFinalized,
      "export_self_included": exportSelfIncluded,
      "sqlite_database_included": sqliteDatabaseIncluded,
      "sqlite_database_exists": sqliteDatabaseExists,
      "sqlite_database_openable": sqliteDatabaseOpenable,
      "sqlite_storage_check_passed": sqliteStorageCheckPassed,
      "sqlite_database_path": sqliteDatabasePath ?? NSNull(),
      "sqlite_mirror_session_exists": sqliteMirrorSessionExists,
      "sqlite_mirror_raw_notification_count": sqliteMirrorRawNotificationCount,
      "sqlite_mirror_historical_range_poll_count": sqliteMirrorHistoricalRangePollCount,
      "sqlite_mirror_successful_historical_range_poll_count": sqliteMirrorSuccessfulHistoricalRangePollCount,
      "ble_log_included": bleLogIncluded,
      "ble_log_byte_count": Int64(bleLogByteCount),
      "ble_log_session_id_found": bleLogSessionIDFound,
      "ble_live_log_included": bleLiveLogIncluded,
      "ble_live_log_byte_count": Int64(bleLiveLogByteCount),
      "ble_live_log_session_id_found": bleLiveLogSessionIDFound,
      "raw_notification_count": rawNotificationCount,
      "historical_range_poll_record_count": historicalRangePollRecordCount,
      "successful_historical_range_poll_count": successfulHistoricalRangePollCount,
      "command_write_record_count": commandWriteRecordCount,
      "command_write_checksum_present_count": commandWriteChecksumPresentCount,
      "command_write_checksum_missing_count": commandWriteChecksumMissingCount,
      "command_write_checksum_mismatch_count": commandWriteChecksumMismatchCount,
      "command_write_hex_invalid_count": commandWriteHexInvalidCount,
      "command_write_parse_error_count": commandWriteParseErrorCount,
      "historical_packet_count": historicalPacketCount ?? NSNull(),
      "k18_count": k18Count ?? NSNull(),
      "k24_count": k24Count ?? NSNull(),
      "k25_count": k25Count ?? NSNull(),
      "k26_count": k26Count ?? NSNull(),
      "packet47_count": packet47Count ?? NSNull(),
      "event17_count": event17Count ?? NSNull(),
      "event29_count": event29Count ?? NSNull(),
      "metadata49_count": metadata49Count ?? NSNull(),
      "metadata56_count": metadata56Count ?? NSNull(),
      "event49_count": metadata49Count ?? NSNull(),
      "event56_count": metadata56Count ?? NSNull(),
      "first_raw_notification_at": firstRawNotificationAt ?? NSNull(),
      "last_raw_notification_at": lastRawNotificationAt ?? NSNull(),
      "max_raw_notification_gap_seconds": maxRawNotificationGapSeconds ?? NSNull(),
      "raw_notification_gaps_over_5_minutes": rawNotificationGapsOver5Minutes,
      "raw_notification_checksum_present_count": rawNotificationChecksumPresentCount,
      "raw_notification_checksum_missing_count": rawNotificationChecksumMissingCount,
      "raw_notification_checksum_mismatch_count": rawNotificationChecksumMismatchCount,
      "raw_notification_value_hex_invalid_count": rawNotificationValueHexInvalidCount,
      "raw_notification_parse_error_count": rawNotificationParseErrorCount,
      "historical_range_checksum_present_count": historicalRangeChecksumPresentCount,
      "historical_range_checksum_missing_count": historicalRangeChecksumMissingCount,
      "historical_range_checksum_mismatch_count": historicalRangeChecksumMismatchCount,
      "historical_range_hex_invalid_count": historicalRangeHexInvalidCount,
      "historical_range_poll_parse_error_count": historicalRangePollParseErrorCount,
      "overnight_event_log_record_count": overnightEventLogRecordCount,
      "overnight_event_log_parse_error_count": overnightEventLogParseErrorCount,
      "proof_sidecar_warning_count": proofSidecarWarningCount,
      "proof_sidecar_warnings": proofSidecarWarnings,
      "passed": passed,
      "issues": issues,
    ]
  }

  func withBundleJSONValidation(valid: Bool, error: String?) -> OpenVitalsLocalDataExportValidation {
    OpenVitalsLocalDataExportValidation(
      requiredOvernightSessionID: requiredOvernightSessionID,
      bundleJSONValid: valid,
      bundleJSONValidationError: error,
      rawNotificationsIncluded: rawNotificationsIncluded,
      historicalRangePollsIncluded: historicalRangePollsIncluded,
      commandWritesIncluded: commandWritesIncluded,
      overnightEventLogIncluded: overnightEventLogIncluded,
      checkpointsIncluded: checkpointsIncluded,
      checkpointLatestIncluded: checkpointLatestIncluded,
      manifestIncluded: manifestIncluded,
      manifestSessionMatches: manifestSessionMatches,
      manifestFinalized: manifestFinalized,
      statusIncluded: statusIncluded,
      statusSessionMatches: statusSessionMatches,
      statusFinalized: statusFinalized,
      crashMarkerIncluded: crashMarkerIncluded,
      crashMarkerJSONValid: crashMarkerJSONValid,
      crashMarkerSessionMatches: crashMarkerSessionMatches,
      crashMarkerFinalized: crashMarkerFinalized,
      exportSelfIncluded: exportSelfIncluded,
      sqliteDatabaseIncluded: sqliteDatabaseIncluded,
      sqliteDatabaseExists: sqliteDatabaseExists,
      sqliteDatabaseOpenable: sqliteDatabaseOpenable,
      sqliteStorageCheckPassed: sqliteStorageCheckPassed,
      sqliteDatabasePath: sqliteDatabasePath,
      sqliteMirrorSessionExists: sqliteMirrorSessionExists,
      sqliteMirrorRawNotificationCount: sqliteMirrorRawNotificationCount,
      sqliteMirrorHistoricalRangePollCount: sqliteMirrorHistoricalRangePollCount,
      sqliteMirrorSuccessfulHistoricalRangePollCount: sqliteMirrorSuccessfulHistoricalRangePollCount,
      bleLogIncluded: bleLogIncluded,
      bleLogByteCount: bleLogByteCount,
      bleLogSessionIDFound: bleLogSessionIDFound,
      bleLiveLogIncluded: bleLiveLogIncluded,
      bleLiveLogByteCount: bleLiveLogByteCount,
      bleLiveLogSessionIDFound: bleLiveLogSessionIDFound,
      rawNotificationCount: rawNotificationCount,
      historicalRangePollRecordCount: historicalRangePollRecordCount,
      successfulHistoricalRangePollCount: successfulHistoricalRangePollCount,
      commandWriteRecordCount: commandWriteRecordCount,
      commandWriteChecksumPresentCount: commandWriteChecksumPresentCount,
      commandWriteChecksumMissingCount: commandWriteChecksumMissingCount,
      commandWriteChecksumMismatchCount: commandWriteChecksumMismatchCount,
      commandWriteHexInvalidCount: commandWriteHexInvalidCount,
      commandWriteParseErrorCount: commandWriteParseErrorCount,
      historicalPacketCount: historicalPacketCount,
      k18Count: k18Count,
      k24Count: k24Count,
      k25Count: k25Count,
      k26Count: k26Count,
      packet47Count: packet47Count,
      event17Count: event17Count,
      event29Count: event29Count,
      metadata49Count: metadata49Count,
      metadata56Count: metadata56Count,
      firstRawNotificationAt: firstRawNotificationAt,
      lastRawNotificationAt: lastRawNotificationAt,
      maxRawNotificationGapSeconds: maxRawNotificationGapSeconds,
      rawNotificationGapsOver5Minutes: rawNotificationGapsOver5Minutes,
      rawNotificationChecksumPresentCount: rawNotificationChecksumPresentCount,
      rawNotificationChecksumMissingCount: rawNotificationChecksumMissingCount,
      rawNotificationChecksumMismatchCount: rawNotificationChecksumMismatchCount,
      rawNotificationValueHexInvalidCount: rawNotificationValueHexInvalidCount,
      rawNotificationParseErrorCount: rawNotificationParseErrorCount,
      historicalRangeChecksumPresentCount: historicalRangeChecksumPresentCount,
      historicalRangeChecksumMissingCount: historicalRangeChecksumMissingCount,
      historicalRangeChecksumMismatchCount: historicalRangeChecksumMismatchCount,
      historicalRangeHexInvalidCount: historicalRangeHexInvalidCount,
      historicalRangePollParseErrorCount: historicalRangePollParseErrorCount,
      overnightEventLogRecordCount: overnightEventLogRecordCount,
      overnightEventLogParseErrorCount: overnightEventLogParseErrorCount,
      proofSidecarWarningCount: proofSidecarWarningCount,
      proofSidecarWarnings: proofSidecarWarnings,
      issues: issues
    )
  }

  func withAdditionalIssue(_ issue: String) -> OpenVitalsLocalDataExportValidation {
    OpenVitalsLocalDataExportValidation(
      requiredOvernightSessionID: requiredOvernightSessionID,
      bundleJSONValid: bundleJSONValid,
      bundleJSONValidationError: bundleJSONValidationError,
      rawNotificationsIncluded: rawNotificationsIncluded,
      historicalRangePollsIncluded: historicalRangePollsIncluded,
      commandWritesIncluded: commandWritesIncluded,
      overnightEventLogIncluded: overnightEventLogIncluded,
      checkpointsIncluded: checkpointsIncluded,
      checkpointLatestIncluded: checkpointLatestIncluded,
      manifestIncluded: manifestIncluded,
      manifestSessionMatches: manifestSessionMatches,
      manifestFinalized: manifestFinalized,
      statusIncluded: statusIncluded,
      statusSessionMatches: statusSessionMatches,
      statusFinalized: statusFinalized,
      crashMarkerIncluded: crashMarkerIncluded,
      crashMarkerJSONValid: crashMarkerJSONValid,
      crashMarkerSessionMatches: crashMarkerSessionMatches,
      crashMarkerFinalized: crashMarkerFinalized,
      exportSelfIncluded: exportSelfIncluded,
      sqliteDatabaseIncluded: sqliteDatabaseIncluded,
      sqliteDatabaseExists: sqliteDatabaseExists,
      sqliteDatabaseOpenable: sqliteDatabaseOpenable,
      sqliteStorageCheckPassed: sqliteStorageCheckPassed,
      sqliteDatabasePath: sqliteDatabasePath,
      sqliteMirrorSessionExists: sqliteMirrorSessionExists,
      sqliteMirrorRawNotificationCount: sqliteMirrorRawNotificationCount,
      sqliteMirrorHistoricalRangePollCount: sqliteMirrorHistoricalRangePollCount,
      sqliteMirrorSuccessfulHistoricalRangePollCount: sqliteMirrorSuccessfulHistoricalRangePollCount,
      bleLogIncluded: bleLogIncluded,
      bleLogByteCount: bleLogByteCount,
      bleLogSessionIDFound: bleLogSessionIDFound,
      bleLiveLogIncluded: bleLiveLogIncluded,
      bleLiveLogByteCount: bleLiveLogByteCount,
      bleLiveLogSessionIDFound: bleLiveLogSessionIDFound,
      rawNotificationCount: rawNotificationCount,
      historicalRangePollRecordCount: historicalRangePollRecordCount,
      successfulHistoricalRangePollCount: successfulHistoricalRangePollCount,
      commandWriteRecordCount: commandWriteRecordCount,
      commandWriteChecksumPresentCount: commandWriteChecksumPresentCount,
      commandWriteChecksumMissingCount: commandWriteChecksumMissingCount,
      commandWriteChecksumMismatchCount: commandWriteChecksumMismatchCount,
      commandWriteHexInvalidCount: commandWriteHexInvalidCount,
      commandWriteParseErrorCount: commandWriteParseErrorCount,
      historicalPacketCount: historicalPacketCount,
      k18Count: k18Count,
      k24Count: k24Count,
      k25Count: k25Count,
      k26Count: k26Count,
      packet47Count: packet47Count,
      event17Count: event17Count,
      event29Count: event29Count,
      metadata49Count: metadata49Count,
      metadata56Count: metadata56Count,
      firstRawNotificationAt: firstRawNotificationAt,
      lastRawNotificationAt: lastRawNotificationAt,
      maxRawNotificationGapSeconds: maxRawNotificationGapSeconds,
      rawNotificationGapsOver5Minutes: rawNotificationGapsOver5Minutes,
      rawNotificationChecksumPresentCount: rawNotificationChecksumPresentCount,
      rawNotificationChecksumMissingCount: rawNotificationChecksumMissingCount,
      rawNotificationChecksumMismatchCount: rawNotificationChecksumMismatchCount,
      rawNotificationValueHexInvalidCount: rawNotificationValueHexInvalidCount,
      rawNotificationParseErrorCount: rawNotificationParseErrorCount,
      historicalRangeChecksumPresentCount: historicalRangeChecksumPresentCount,
      historicalRangeChecksumMissingCount: historicalRangeChecksumMissingCount,
      historicalRangeChecksumMismatchCount: historicalRangeChecksumMismatchCount,
      historicalRangeHexInvalidCount: historicalRangeHexInvalidCount,
      historicalRangePollParseErrorCount: historicalRangePollParseErrorCount,
      overnightEventLogRecordCount: overnightEventLogRecordCount,
      overnightEventLogParseErrorCount: overnightEventLogParseErrorCount,
      proofSidecarWarningCount: proofSidecarWarningCount,
      proofSidecarWarnings: proofSidecarWarnings,
      issues: issues + [issue]
    )
  }
}

struct OpenVitalsOvernightExportMetrics {
  var rawNotificationCount = 0
  var historicalRangePollRecordCount = 0
  var successfulHistoricalRangePollCount = 0
  var commandWriteRecordCount = 0
  var commandWriteChecksumPresentCount = 0
  var commandWriteChecksumMissingCount = 0
  var commandWriteChecksumMismatchCount = 0
  var commandWriteHexInvalidCount = 0
  var commandWriteParseErrorCount = 0
  var historicalPacketCount: Int?
  var k18Count: Int?
  var k24Count: Int?
  var k25Count: Int?
  var k26Count: Int?
  var packet47Count: Int?
  var event17Count: Int?
  var event29Count: Int?
  var metadata49Count: Int?
  var metadata56Count: Int?
  var firstRawNotificationAt: String?
  var lastRawNotificationAt: String?
  var maxRawNotificationGapSeconds: Double?
  var rawNotificationGapsOver5Minutes = 0
  var rawNotificationChecksumPresentCount = 0
  var rawNotificationChecksumMissingCount = 0
  var rawNotificationChecksumMismatchCount = 0
  var rawNotificationValueHexInvalidCount = 0
  var rawNotificationParseErrorCount = 0
  var historicalRangeChecksumPresentCount = 0
  var historicalRangeChecksumMissingCount = 0
  var historicalRangeChecksumMismatchCount = 0
  var historicalRangeHexInvalidCount = 0
  var historicalRangePollParseErrorCount = 0
  var overnightEventLogRecordCount = 0
  var overnightEventLogParseErrorCount = 0
  var sqliteMirrorSessionExists = false
  var sqliteMirrorRawNotificationCount = 0
  var sqliteMirrorHistoricalRangePollCount = 0
  var sqliteMirrorSuccessfulHistoricalRangePollCount = 0
  var proofSidecarWarningCount = 0
  var proofSidecarWarnings: [String] = []
}

enum OpenVitalsLocalDataExporter {
  struct FileContentDigest {
    let byteCount: UInt64
    let sha256: String
  }

  static let exportProtection: FileProtectionType = .completeUntilFirstUserAuthentication

  static let jsonlTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static func createBundle(
    requiredOvernightSessionID: String? = nil,
    progress: ((OpenVitalsLocalDataExportProgress) -> Void)? = nil
  ) throws -> OpenVitalsLocalDataExportResult {
    let fileManager = FileManager.default
    let now = Date()
    let createdAt = ISO8601DateFormatter().string(from: now)
    let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    let exportsDirectory = documentsDirectory
      .appendingPathComponent("OpenVitals", isDirectory: true)
      .appendingPathComponent("Exports", isDirectory: true)
    try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    try applyExportProtection(to: exportsDirectory)

    let exportID = UUID().uuidString.lowercased()
    let fileName = "open-vitals-local-data-\(Int(now.timeIntervalSince1970))-\(exportID).openvitalsbundle.json"
    let outputURL = exportsDirectory.appendingPathComponent(fileName)
    let temporaryURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
    try Data().write(to: temporaryURL, options: .atomic)
    try applyExportProtection(to: temporaryURL)
    let handle = try FileHandle(forWritingTo: temporaryURL)

    let exportScope = requiredOvernightSessionID.map { "overnight_session:\($0)" } ?? "full_app_container"
    let roots = exportRoots(
      fileManager: fileManager,
      documentsDirectory: documentsDirectory
    )
    var firstFile = true
    var fileCount = 0
    var byteCount: UInt64 = 0
    var exportedRelativePaths: [String] = []
    var exportedFileSummaries: [[String: Any]] = []
    var sourceReadFailureCount = 0
    var sourceReadFailureIssues: [String] = []
    var completedValidation: OpenVitalsLocalDataExportValidation?

    func report(_ title: String, _ detail: String, _ fractionCompleted: Double? = nil) {
      progress?(OpenVitalsLocalDataExportProgress(
        title: title,
        detail: detail,
        fractionCompleted: fractionCompleted
      ))
    }

    report("Preparing export", "Collecting local files", 0.02)

    let selectedFiles = roots.flatMap { root in
      filesUnder(
        root.url,
        label: root.label,
        outputDirectory: exportsDirectory,
        requiredOvernightSessionID: requiredOvernightSessionID,
        fileManager: fileManager
      )
      .filter { !shouldSkipFileDuringExport($0.relativePath) }
      .map { file in
        (source: root.label, url: file.url, relativePath: file.relativePath)
      }
    }
    let totalSourceBytes = selectedFiles.reduce(UInt64(0)) { total, file in
      total + fileByteCount(at: file.url, fileManager: fileManager)
    }
    var completedSourceBytes: UInt64 = 0
    var lastReportedWritingFraction = 0.0

    func reportWritingProgress(fileName: String, currentFileBytes: UInt64 = 0, force: Bool = false) {
      let detail = "Writing \(fileName)"
      guard totalSourceBytes > 0 else {
        report("Writing bundle", detail, nil)
        return
      }
      let currentBytes = min(completedSourceBytes + currentFileBytes, totalSourceBytes)
      let writingFraction = Double(currentBytes) / Double(totalSourceBytes)
      let overallFraction = 0.15 + (writingFraction * 0.60)
      if force || overallFraction - lastReportedWritingFraction >= 0.005 {
        lastReportedWritingFraction = overallFraction
        report("Writing bundle", detail, overallFraction)
      }
    }

    do {
      try writeString("{", to: handle)
      try writeJSONObjectFields([
        "schema": "open_vitals.local-data-export.v1",
        "export_id": exportID,
        "created_at": createdAt,
        "scope": exportScope,
        "format": "Each file record stores base64 file contents from the app container.",
      ], to: handle)
      try writeString(",\"files\":[", to: handle)

      for file in selectedFiles {
          let fileName = file.url.lastPathComponent
          let preparedReadURL: URL
          let cleanupURL: URL?
          do {
            if file.relativePath == "Application Support/OpenVitals/open_vitals.sqlite" {
              report("Snapshotting database", "Creating a consistent SQLite copy", 0.08)
            }
            let prepared = try preparedReadURLForExport(
              sourceURL: file.url,
              relativePath: file.relativePath,
              exportID: exportID,
              fileManager: fileManager
            )
            preparedReadURL = prepared.url
            cleanupURL = prepared.cleanupURL
          } catch {
            sourceReadFailureCount += 1
            if sourceReadFailureIssues.count < 5 {
              sourceReadFailureIssues.append("failed to snapshot selected export file \(file.relativePath): \(String(describing: error))")
            }
            if !firstFile {
              try writeString(",", to: handle)
            }
            firstFile = false
            try writeJSONObject([
              "source": file.source,
              "relative_path": file.relativePath,
              "error": String(describing: error),
            ], to: handle)
            exportedFileSummaries.append([
              "source": file.source,
              "relative_path": file.relativePath,
              "exported": false,
              "error": String(describing: error),
            ])
            continue
          }

          let inputHandle: FileHandle
          do {
            inputHandle = try FileHandle(forReadingFrom: preparedReadURL)
          } catch {
            if let cleanupURL {
              try? fileManager.removeItem(at: cleanupURL)
            }
            sourceReadFailureCount += 1
            if sourceReadFailureIssues.count < 5 {
              sourceReadFailureIssues.append("failed to read selected export file \(file.relativePath): \(String(describing: error))")
            }
            if !firstFile {
              try writeString(",", to: handle)
            }
            firstFile = false
            try writeJSONObject([
              "source": file.source,
              "relative_path": file.relativePath,
              "error": String(describing: error),
            ], to: handle)
            exportedFileSummaries.append([
              "source": file.source,
              "relative_path": file.relativePath,
              "exported": false,
              "error": String(describing: error),
            ])
            continue
          }

          if !firstFile {
            try writeString(",", to: handle)
          }
          firstFile = false

          do {
            reportWritingProgress(fileName: fileName, force: true)
            let exportedFileDigest = try writeFileRecord(
              source: file.source,
              relativePath: file.relativePath,
              inputHandle: inputHandle,
              to: handle,
              progress: { bytesWritten in
                reportWritingProgress(fileName: fileName, currentFileBytes: bytesWritten)
              }
          )
            if let cleanupURL {
              try? fileManager.removeItem(at: cleanupURL)
            }
            byteCount += exportedFileDigest.byteCount
            completedSourceBytes += exportedFileDigest.byteCount
            reportWritingProgress(fileName: fileName, force: true)
            fileCount += 1
            exportedRelativePaths.append(file.relativePath)
            exportedFileSummaries.append([
              "source": file.source,
              "relative_path": file.relativePath,
              "exported": true,
              "byte_count": Int64(exportedFileDigest.byteCount),
              "sha256": exportedFileDigest.sha256,
            ])
          } catch {
            try? inputHandle.close()
            if let cleanupURL {
              try? fileManager.removeItem(at: cleanupURL)
            }
            throw error
          }
      }

      if sourceReadFailureCount > sourceReadFailureIssues.count {
        sourceReadFailureIssues.append("failed to read \(sourceReadFailureCount - sourceReadFailureIssues.count) additional selected export files")
      }
      report("Validating bundle", "Checking included files and storage", 0.78)
      let validation = sourceReadFailureIssues.reduce(
        validate(
          exportedRelativePaths: exportedRelativePaths,
          requiredOvernightSessionID: requiredOvernightSessionID,
          documentsDirectory: documentsDirectory,
          fileManager: fileManager
        ).withBundleJSONValidation(valid: true, error: nil)
      ) { validation, issue in
        validation.withAdditionalIssue(issue)
      }
      completedValidation = validation
      try writeString("],\"summary\":", to: handle)
      try writeJSONObject([
        "export_id": exportID,
        "file_count": fileCount,
        "byte_count": Int64(byteCount),
        "created_at": createdAt,
        "scope": exportScope,
        "file_protection": exportProtection.rawValue,
        "validation": validation.jsonObject,
      ], to: handle)
      try writeString("}\n", to: handle)
      report("Writing bundle", "Flushing local data file", 0.84)
      try synchronizeAndClose(handle)
      report("Validating bundle", "Checking JSON structure", 0.86)
      if let validationError = bundleJSONStructureIssue(at: temporaryURL) {
        throw OpenVitalsLocalDataExportError.invalidBundleJSON(validationError)
      }
      if fileManager.fileExists(atPath: outputURL.path) {
        throw OpenVitalsLocalDataExportError.outputAlreadyExists(outputURL.path)
      }
      try fileManager.moveItem(at: temporaryURL, to: outputURL)
      try applyExportProtection(to: outputURL)
    } catch {
      try? handle.close()
      try? fileManager.removeItem(at: temporaryURL)
      throw error
    }
    guard let validation = completedValidation else {
      throw OpenVitalsLocalDataExportError.invalidBundleJSON("Local export validation did not complete")
    }
    let manifestURL: URL?
    let manifestError: String?
    do {
      report("Hashing manifest", "Hashing final bundle", 0.88)
      manifestURL = try writeExportManifest(
        for: outputURL,
        createdAt: createdAt,
        requiredOvernightSessionID: requiredOvernightSessionID,
        exportScope: exportScope,
        fileCount: fileCount,
        byteCount: byteCount,
        files: exportedFileSummaries,
        validation: validation,
        progress: { digestFraction in
          report("Hashing manifest", "Hashing final bundle", 0.88 + (digestFraction * 0.10))
        }
      )
      manifestError = nil
    } catch {
      manifestURL = nil
      manifestError = String(describing: error)
    }
    let resultValidation: OpenVitalsLocalDataExportValidation
    if let manifestError, !manifestError.isEmpty {
      resultValidation = validation.withAdditionalIssue("export manifest sidecar failed: \(manifestError)")
    } else {
      resultValidation = validation
    }
    report("Done", "Local data file saved", 1)
    return OpenVitalsLocalDataExportResult(
      url: outputURL,
      manifestURL: manifestURL,
      manifestError: manifestError,
      fileCount: fileCount,
      byteCount: byteCount,
      validation: resultValidation
    )
  }

  static func writeExportManifest(
    for bundleURL: URL,
    createdAt: String,
    requiredOvernightSessionID: String?,
    exportScope: String,
    fileCount: Int,
    byteCount: UInt64,
    files: [[String: Any]],
    validation: OpenVitalsLocalDataExportValidation,
    progress: ((Double) -> Void)? = nil
  ) throws -> URL {
    let manifestURL = bundleURL
      .deletingPathExtension()
      .appendingPathExtension("manifest.json")
    let bundleDigest = try fileDigest(at: bundleURL, progress: progress)
    let object: [String: Any] = [
      "schema": "open_vitals.local-data-export-manifest.v1",
      "bundle_file": bundleURL.lastPathComponent,
      "bundle_path": bundleURL.path,
      "bundle_file_byte_count": Int64(bundleDigest.byteCount),
      "bundle_sha256": bundleDigest.sha256,
      "created_at": createdAt,
      "scope": exportScope,
      "required_overnight_session_id": requiredOvernightSessionID ?? NSNull(),
      "file_count": fileCount,
      "byte_count": Int64(byteCount),
      "file_protection": exportProtection.rawValue,
      "source_file_hash_algorithm": "sha256(raw_file_bytes)",
      "validation": validation.jsonObject,
      "files": files,
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: manifestURL, options: .atomic)
    try applyExportProtection(to: manifestURL)
    let handle = try FileHandle(forUpdating: manifestURL)
    try synchronizeAndClose(handle)
    return manifestURL
  }

}
