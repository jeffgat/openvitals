export type DeviceProfileId = "custom-band" | "standard-heart-rate" | "unknown";
export type ConnectionState =
  | "idle"
  | "scanning"
  | "connecting"
  | "discovering"
  | "ready"
  | "disconnecting"
  | "disconnected"
  | "failed";

export type PacketDirection = "notify" | "read" | "write";
export type PacketParserStatus = "pending" | "parsed" | "raw" | "buffered" | "parse_failed";
export type RustDeviceType = "OPENVITALS" | "GEN4";

export interface DiscoveredDevice {
  id: string;
  address?: string;
  name: string;
  rssi: number;
  profileId: DeviceProfileId;
  profileLabel: string;
  advertisedServices: string[];
  evidence: string;
  lastSeenUnixMs: number;
}

export interface ConnectedCharacteristic {
  serviceUuid: string;
  characteristicUuid: string;
  properties: string[];
  role: "command" | "notify" | "heart_rate" | "battery" | "device_info" | "other";
}

export interface ConnectedDevice {
  id: string;
  name: string;
  profileId: DeviceProfileId;
  profileLabel: string;
  commandReady: boolean;
  characteristics: ConnectedCharacteristic[];
}

export interface StandardHeartRateSample {
  bpm: number;
  rrIntervalsMs: number[];
  contactDetected?: boolean;
  energyExpendedJ?: number;
}

export interface PacketRecord {
  id: string;
  evidenceId?: string;
  capturedAt: string;
  direction: PacketDirection;
  source: string;
  deviceId?: string;
  deviceName?: string;
  serviceUuid: string;
  characteristicUuid: string;
  bytes: number;
  rawHex: string;
  frameHex: string;
  deviceType: RustDeviceType;
  parserStatus: PacketParserStatus;
  packetType?: number;
  packetTypeName?: string;
  sequence?: number;
  commandOrEvent?: number;
  payloadKind?: string;
  summary: string;
  warnings: string[];
  importIssues: string[];
  parsedJson?: unknown;
  standardHeartRate?: StandardHeartRateSample;
}

export interface CaptureState {
  active: boolean;
  databasePath: string;
  sessionId?: string;
  startedAt?: string;
  frameCount: number;
  rawInserted: number;
  rawExisting: number;
  framesInserted: number;
  framesExisting: number;
  pendingFrames: number;
  flushing: boolean;
  lastImportStatus: string;
}

export interface MobileIngestState {
  enabled: boolean;
  listening: boolean;
  bindHost: string;
  port: number;
  url: string;
  tokenRequired: boolean;
  receivedBatches: number;
  receivedFrames: number;
  importedFrames: number;
  existingFrames: number;
  rawInserted: number;
  rawExisting: number;
  pendingBatches: number;
  lastReceivedAt?: string | undefined;
  lastImportStatus: string;
  activeSessionId?: string | undefined;
  lastError?: string | undefined;
}

export interface NotifySubscriptionDiagnostic {
  characteristicUuid: string;
  requested: boolean;
  subscribed: boolean;
}

export interface NotifySubscriptionErrorDiagnostic {
  characteristicUuid: string;
  message: string;
}

export interface BandParityProbeState {
  active: boolean;
  stage: string;
  startedAt?: string;
  completedAt?: string;
  success?: boolean;
  message?: string;
  targetDeviceId?: string;
  targetDeviceName?: string;
  noHelloResponseAfterSeconds?: number;
  noCustomFramesAfterSeconds?: number;
}

export interface CommandResponseDiagnostic {
  responseToCommand?: number;
  responseToCommandName?: string;
  originSequence?: number;
  resultCode?: number;
  sequence?: number;
  characteristicUuid?: string;
  capturedAt?: string;
}

export interface NativeAuthProbeState {
  active: boolean;
  stage: string;
  startedAt?: string;
  completedAt?: string;
  exitCode?: number;
  success?: boolean;
  message?: string;
  output: string[];
  authErrors: string[];
}

export interface MacPairingStatusState {
  active: boolean;
  stage: string;
  checkedAt?: string;
  known?: boolean;
  connected?: boolean;
  matchedCount: number;
  advertising?: boolean;
  advertisingDeviceId?: string;
  advertisingName?: string;
  advertisingRssi?: number;
  advertisingServices?: string[];
  message?: string;
}

export interface DesktopDiagnostics {
  fd4bCommandReady: boolean;
  commandCharacteristicUuid?: string;
  helloSent: boolean;
  helloResponseReceived: boolean;
  helloResponseResultCode?: number;
  commandWritesAccepted: number;
  commandResponsesReceived: number;
  lastCommandResponse?: CommandResponseDiagnostic;
  customNotifyPacketsReceived: number;
  fd4bNotifyPacketsReceived: number;
  notifyRetryAttempts: number;
  notifyRetryConfirmed: number;
  notifyRetryErrors: number;
  requestedCustomNotifyUuids: string[];
  subscribedCustomNotifyUuids: string[];
  notifySubscriptionErrors: NotifySubscriptionErrorDiagnostic[];
  requiredFd4bNotify: NotifySubscriptionDiagnostic[];
  macPairingStatus: MacPairingStatusState;
  nativeAuthProbe: NativeAuthProbeState;
  bandParityProbe: BandParityProbeState;
}

export interface LogEntry {
  id: string;
  at: string;
  level: "info" | "warn" | "error";
  source: string;
  message: string;
}

export interface RustStatus {
  ready: boolean;
  version?: string;
  bridgePath?: string;
  lastError?: string;
}

export interface DebuggerAppState {
  bluetoothState: string;
  connectionState: ConnectionState;
  scanning: boolean;
  devices: DiscoveredDevice[];
  connectedDevice?: ConnectedDevice;
  capture: CaptureState;
  mobileIngest: MobileIngestState;
  packets: PacketRecord[];
  selectedPacketId?: string;
  logs: LogEntry[];
  rust: RustStatus;
  diagnostics: DesktopDiagnostics;
  lastHelloFrameHex?: string;
}

export interface StartCaptureOptions {
  databasePath?: string;
}

export interface StartBandParityProbeOptions {
  databasePath?: string;
  scanTimeoutMs?: number;
  observeSeconds?: number;
}

export interface StorageCheckResult {
  pass: boolean;
  report: unknown;
}
