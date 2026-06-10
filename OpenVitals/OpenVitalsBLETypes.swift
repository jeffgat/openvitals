import CoreBluetooth
import Foundation
import OSLog

enum OpenVitalsLogLevel: String {
  case debug
  case info
  case warn
  case error
}

struct OpenVitalsDiscoveredDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
}

struct OpenVitalsScanDiagnostic: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
  let status: String
  let services: String
  let lastSeen: Date
}

struct OpenVitalsMessage: Identifiable {
  let id = UUID()
  let timestamp: Date
  let level: OpenVitalsLogLevel
  let source: String
  let title: String
  let body: String
}

struct OpenVitalsNotificationEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let value: Data
  let capturedAt: Date

  var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "OPENVITALS"
  }
}

struct OpenVitalsBLENotificationContext {
  let activeDeviceName: String
  let connectionState: String
}

struct OpenVitalsCommandWriteEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let commandName: String
  let commandNumber: UInt8?
  let sequence: UInt8?
  let payload: Data
  let frame: Data
  let writeType: String
  let source: String
  let capturedAt: Date
}

enum OpenVitalsSyncToastPhase: String {
  case syncing
  case synced
  case failed
}

struct OpenVitalsSyncToast: Identifiable, Equatable {
  let id = UUID()
  let phase: OpenVitalsSyncToastPhase
  let title: String
  let detail: String
}

struct OpenVitalsHistoricalSyncProgress {
  let status: String
  let detail: String
  let packetCount: Int
  let isTerminal: Bool
  let failed: Bool
  let capturedAt: Date
}

struct OpenVitalsHistoricalRangeTelemetry {
  let capturedAt: Date
  let status: String
  let commandSequence: UInt8
  let resultCode: UInt8
  let resultName: String
  let payloadHex: String
  let bodyHex: String
  let revisionOrStatus: UInt8?
  let wordsFromOffset1: [UInt32]
  let pageCurrent: UInt32?
  let pageOldest: UInt32?
  let pageEnd: UInt32?
  let pagesBehind: Int64?
  let pendingResponseCount: Int
  let retryCount: Int
  let notes: String
}

struct OpenVitalsSyncFailure: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let message: String
  let occurredAt: Date
}

struct OpenVitalsDebugCommandDefinition: Identifiable, Equatable {
  let id: String
  let title: String
  let commandNumber: UInt8
  let family: String
  let risk: String
  let detail: String
  let defaultPayloadHex: String?
  let requiresPayloadHex: Bool
  let payloadHint: String

  var canSendFromButton: Bool {
    defaultPayloadHex != nil || !requiresPayloadHex
  }

  var remoteURLExample: String {
    if requiresPayloadHex {
      return "openvitals://debug-command/\(id)?payload=<hex>"
    }
    return "openvitals://debug-command/\(id)"
  }
}

struct OpenVitalsDebugCommandResponse: Identifiable, Equatable {
  let id: UUID
  let commandID: String
  let title: String
  let commandNumber: UInt8
  let sequence: UInt8
  let requestedAt: Date
  let completedAt: Date?
  let status: String
  let result: String
  let requestPayloadHex: String
  let requestFrameHex: String
  let responsePayloadHex: String
  let responseBodyHex: String
  let source: String

  var summary: String {
    let time = completedAt ?? requestedAt
    let body = responseBodyHex.isEmpty ? "no body" : "body \(responseBodyHex)"
    return "\(status) | \(result) | seq \(sequence) | \(body) | \(time.formatted(date: .omitted, time: .standard))"
  }
}
