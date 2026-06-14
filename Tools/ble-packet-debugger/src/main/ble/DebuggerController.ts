import { EventEmitter } from "node:events";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import noble, {
  type NobleCharacteristic,
  type NoblePeripheral,
  type NobleService,
} from "@abandonware/noble";
import type {
  CaptureState,
  ConnectedCharacteristic,
  ConnectedDevice,
  ConnectionState,
  DebuggerAppState,
  DesktopDiagnostics,
  DiscoveredDevice,
  LogEntry,
  PacketRecord,
  RustDeviceType,
  StandardHeartRateSample,
  StorageCheckResult,
} from "../../shared/types";
import {
  RustBridgeClient,
  type CapturedFrameInput,
  type RrReferenceSampleInput,
} from "../bridge/RustBridgeClient";
import {
  BATTERY_LEVEL_STATUS_UUID,
  BATTERY_LEVEL_UUID,
  COMMAND_CHARACTERISTIC_SET,
  compactUuid,
  CUSTOM_BAND_SERVICE_SET,
  DEVICE_INFORMATION_CHARACTERISTIC_UUIDS,
  displayUuid,
  isCustomBandCharacteristic,
  NOTIFICATION_CHARACTERISTIC_SET,
  rustDeviceTypeForCharacteristic,
  STANDARD_HEART_RATE_SERVICE_UUID,
  STANDARD_HEART_RATE_MEASUREMENT_UUID,
} from "./constants";
import { discoveredDeviceFromPeripheral } from "./deviceMatcher";
import { FrameAccumulator } from "./frameAccumulator";
import { parseStandardHeartRateMeasurement } from "./standardHeartRate";

interface CaptureQueueItem {
  packetId: string;
  frame: CapturedFrameInput;
}

interface ActiveConnection {
  peripheral: NoblePeripheral;
  device: DiscoveredDevice;
  commandCharacteristic?: NobleCharacteristic;
  characteristics: ConnectedCharacteristic[];
}

interface ParsedPayloadResult {
  kind?: string;
  response_to_command?: number;
  response_to_command_name?: string;
  origin_sequence?: number;
  result_code?: number;
}

interface ParseBatchResponse {
  results?: Array<{
    ok?: boolean;
    compact?: {
      packet_type?: number;
      packet_type_name?: string;
      sequence?: number;
      payload_kind?: string;
      summary?: string;
      warnings_count?: number;
    };
    result?: {
      packet_type?: number;
      packet_type_name?: string;
      sequence?: number;
      command_or_event?: number;
      parsed_payload?: ParsedPayloadResult;
      warnings?: string[];
    };
    error?: string;
  }>;
}

interface ImportBatchResponse {
  raw_inserted?: number;
  raw_existing?: number;
  frames_inserted?: number;
  frames_existing?: number;
  results?: Array<{
    evidence_id?: string;
    parse_ok?: boolean;
    issues?: string[];
  }>;
  issues?: string[];
}

interface RrReferenceInsertResponse {
  inserted_count?: number;
  existing_count?: number;
  sample_count?: number;
}

interface SensorStreamCommand {
  commandNumber: number;
  payload: number[];
  name: string;
}

const MAX_PACKETS = 500;
const MAX_LOGS = 300;
const SENSOR_COMMAND_DELAY_MS = 250;
const IOS_PARITY_PHYSIOLOGY_DELAY_MS = 5_000;
const BAND_PARITY_SCAN_TIMEOUT_MS = 10_000;
const BAND_PARITY_OBSERVE_SECONDS = 12;
const BAND_PARITY_POLL_MS = 250;
const BLUETOOTH_POWERED_ON_WAIT_MS = 5_000;
const MAC_PAIRING_ADVERTISEMENT_SCAN_MS = 4_000;
const COMMAND_GET_HELLO = 145;
const CUSTOM_NOTIFY_RETRY_ATTEMPTS = 3;
const CUSTOM_NOTIFY_RETRY_DELAY_MS = 300;
const CLIENT_HELLO_FRAME_HEX = "aa0108000001e67123019101363e5c8d";
const FD4B_COMMAND_CHARACTERISTIC_UUID = "fd4b0002cce1403393ce002d5875f58a";
const FD4B_CUSTOM_BAND_SERVICE_UUID = "fd4b0001cce1403393ce002d5875f58a";
const REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS = [
  "fd4b0003cce1403393ce002d5875f58a",
  "fd4b0004cce1403393ce002d5875f58a",
  "fd4b0005cce1403393ce002d5875f58a",
  "fd4b0007cce1403393ce002d5875f58a",
] as const;

const PHYSIOLOGY_START_COMMANDS: SensorStreamCommand[] = [
  { commandNumber: 3, payload: [1], name: "TOGGLE_REALTIME_HR_ON" },
  { commandNumber: 63, payload: [1], name: "SEND_R10_R11_REALTIME_ON" },
  { commandNumber: 106, payload: [1, 1], name: "TOGGLE_IMU_MODE_ON" },
  { commandNumber: 154, payload: [1, 1], name: "TOGGLE_PERSISTENT_R21_ON" },
  { commandNumber: 107, payload: [1, 1], name: "ENABLE_OPTICAL_DATA_ON" },
  { commandNumber: 108, payload: [1, 1], name: "TOGGLE_OPTICAL_MODE_ON" },
  { commandNumber: 153, payload: [1, 1], name: "TOGGLE_PERSISTENT_R20_ON" },
  { commandNumber: 124, payload: [1, 1], name: "TOGGLE_LABRADOR_DATA_GENERATION_ON" },
  { commandNumber: 125, payload: [1, 1], name: "TOGGLE_LABRADOR_RAW_SAVE_ON" },
  { commandNumber: 139, payload: [1, 1], name: "TOGGLE_LABRADOR_FILTERED_ON" },
];

const PHYSIOLOGY_STOP_COMMANDS: SensorStreamCommand[] = [
  { commandNumber: 139, payload: [1, 0], name: "TOGGLE_LABRADOR_FILTERED_OFF" },
  { commandNumber: 125, payload: [1, 0], name: "TOGGLE_LABRADOR_RAW_SAVE_OFF" },
  { commandNumber: 124, payload: [1, 0], name: "TOGGLE_LABRADOR_DATA_GENERATION_OFF" },
  { commandNumber: 153, payload: [1, 0], name: "TOGGLE_PERSISTENT_R20_OFF" },
  { commandNumber: 108, payload: [1, 0], name: "TOGGLE_OPTICAL_MODE_OFF" },
  { commandNumber: 107, payload: [1, 0], name: "ENABLE_OPTICAL_DATA_OFF" },
  { commandNumber: 154, payload: [1, 0], name: "TOGGLE_PERSISTENT_R21_OFF" },
  { commandNumber: 106, payload: [1, 0], name: "TOGGLE_IMU_MODE_OFF" },
  { commandNumber: 63, payload: [0], name: "SEND_R10_R11_REALTIME_OFF" },
  { commandNumber: 3, payload: [0], name: "TOGGLE_REALTIME_HR_OFF" },
];

const HIGH_FREQUENCY_EXIT_COMMAND: SensorStreamCommand = {
  commandNumber: 97,
  payload: [],
  name: "EXIT_HIGH_FREQ_SYNC",
};

export class DebuggerController extends EventEmitter {
  private readonly peripherals = new Map<string, NoblePeripheral>();
  private readonly devices = new Map<string, DiscoveredDevice>();
  private readonly accumulators = new Map<string, FrameAccumulator>();
  private readonly captureQueue: CaptureQueueItem[] = [];
  private readonly packets: PacketRecord[] = [];
  private readonly logs: LogEntry[] = [];
  private active: ActiveConnection | undefined;
  private captureSessionCounter = 0;
  private packetCounter = 0;
  private evidenceCounter = 0;
  private rrReferenceNotificationCounter = 0;
  private nextSensorCommandSequence = 180;
  private clientHelloSentForCurrentConnection = false;
  private commandWritesAccepted = 0;
  private commandResponsesReceived = 0;
  private helloResponseReceived = false;
  private helloResponseResultCode: number | undefined;
  private lastCommandResponse: DesktopDiagnostics["lastCommandResponse"] | undefined;
  private customNotifyPacketsReceived = 0;
  private fd4bNotifyPacketsReceived = 0;
  private notifyRetryAttempts = 0;
  private notifyRetryConfirmed = 0;
  private notifyRetryErrors = 0;
  private readonly requestedCustomNotifyUuids = new Set<string>();
  private readonly subscribedCustomNotifyUuids = new Set<string>();
  private readonly notifySubscriptionErrors = new Map<string, string>();
  private flushTimer: NodeJS.Timeout | undefined;

  private bluetoothState = noble.state ?? "unknown";
  private connectionState: ConnectionState = "idle";
  private scanning = false;
  private selectedPacketId: string | undefined;
  private lastHelloFrameHex: string | undefined;

  private capture: CaptureState;
  private rustReady = false;
  private rustVersion: string | undefined;
  private rustLastError: string | undefined;
  private macPairingStatus: DesktopDiagnostics["macPairingStatus"] = {
    active: false,
    stage: "idle",
    matchedCount: 0,
  };
  private nativeAuthProbe: DesktopDiagnostics["nativeAuthProbe"] = {
    active: false,
    stage: "idle",
    output: [],
    authErrors: [],
  };
  private bandParityProbe: DesktopDiagnostics["bandParityProbe"] = {
    active: false,
    stage: "idle",
  };

  constructor(
    private readonly rust: RustBridgeClient,
    databasePath: string,
    private readonly repoRoot: string,
  ) {
    super();
    this.capture = {
      active: false,
      databasePath,
      frameCount: 0,
      rawInserted: 0,
      rawExisting: 0,
      framesInserted: 0,
      framesExisting: 0,
      pendingFrames: 0,
      flushing: false,
      lastImportStatus: "idle",
    };

    noble.on("stateChange", (state) => {
      this.bluetoothState = state;
      if (state !== "poweredOn" && this.scanning) {
        this.scanning = false;
      }
      this.emitState();
    });
    noble.on("discover", (peripheral) => this.handleDiscover(peripheral));

    this.rust.on("stderr", (line) => this.log("info", "rust", line));
    void this.initializeRust();
  }

  async initializeRust(): Promise<void> {
    try {
      const version = await this.rust.version();
      this.rustReady = true;
      this.rustVersion = renderRustVersion(version);
      this.rustLastError = undefined;
      this.log("info", "rust", `bridge ready ${this.rustVersion}`);
    } catch (error) {
      this.rustReady = false;
      this.rustLastError = errorMessage(error);
      this.log("error", "rust", this.rustLastError);
    }
    this.emitState();
  }

  getState(): DebuggerAppState {
    const connectedDevice = this.active ? this.connectedDeviceState(this.active) : undefined;
    const state: DebuggerAppState = {
      bluetoothState: this.bluetoothState,
      connectionState: this.connectionState,
      scanning: this.scanning,
      devices: [...this.devices.values()].sort((left, right) => right.rssi - left.rssi),
      capture: { ...this.capture, pendingFrames: this.captureQueue.length },
      packets: [...this.packets],
      logs: [...this.logs],
      rust: {
        ready: this.rustReady,
        bridgePath: this.rust.bridgePath,
        ...(this.rustVersion ? { version: this.rustVersion } : {}),
        ...(this.rustLastError ? { lastError: this.rustLastError } : {}),
      },
      diagnostics: this.currentDiagnostics(),
      ...(connectedDevice ? { connectedDevice } : {}),
      ...(this.selectedPacketId ? { selectedPacketId: this.selectedPacketId } : {}),
      ...(this.lastHelloFrameHex ? { lastHelloFrameHex: this.lastHelloFrameHex } : {}),
    };
    return state;
  }

  async startScan(): Promise<DebuggerAppState> {
    if (this.bluetoothState !== "poweredOn") {
      await this.waitForBluetoothPoweredOn(BLUETOOTH_POWERED_ON_WAIT_MS);
    }
    if (this.bluetoothState !== "poweredOn") {
      throw new Error(`Bluetooth is ${this.bluetoothState}; macOS must report poweredOn before scanning.`);
    }
    await startScanning();
    this.scanning = true;
    this.connectionState = "scanning";
    this.log("info", "ble", "scan started");
    this.emitState();
    return this.getState();
  }

  async stopScan(): Promise<DebuggerAppState> {
    await stopScanning();
    this.scanning = false;
    if (!this.active) {
      this.connectionState = "idle";
    }
    this.log("info", "ble", "scan stopped");
    this.emitState();
    return this.getState();
  }

  async connect(deviceId: string, options: { autoHello?: boolean } = {}): Promise<DebuggerAppState> {
    const peripheral = this.peripherals.get(deviceId);
    const device = this.devices.get(deviceId);
    if (!peripheral || !device) {
      throw new Error(`Device ${deviceId} is not in the scan list.`);
    }
    if (this.scanning) {
      await stopScanning();
      this.scanning = false;
    }
    if (this.active) {
      await this.disconnect();
    }

    this.clientHelloSentForCurrentConnection = false;
    this.resetConnectionDiagnostics();
    this.connectionState = "connecting";
    this.emitState();
    await connectPeripheral(peripheral);
    peripheral.once("disconnect", () => {
      this.active = undefined;
      this.clientHelloSentForCurrentConnection = false;
      this.connectionState = "disconnected";
      this.log("warn", "ble", "device disconnected");
      this.emitState();
    });

    this.connectionState = "discovering";
    this.emitState();
    const { services, characteristics } = await discoverAll(peripheral);
    const connectedCharacteristics: ConnectedCharacteristic[] = [];
    let commandCharacteristic: NobleCharacteristic | undefined;

    for (const characteristic of characteristics) {
      const characteristicUuid = compactUuid(characteristic.uuid);
      const serviceUuid = characteristicServiceUuid(characteristic, services);
      const role = characteristicRole(characteristicUuid);
      connectedCharacteristics.push({
        serviceUuid: displayUuid(serviceUuid),
        characteristicUuid: displayUuid(characteristicUuid),
        properties: [...characteristic.properties],
        role,
      });

      if (COMMAND_CHARACTERISTIC_SET.has(characteristicUuid)) {
        commandCharacteristic = chooseCommandCharacteristic(commandCharacteristic, characteristic);
      }
    }

    this.active = {
      peripheral,
      device,
      ...(commandCharacteristic ? { commandCharacteristic } : {}),
      characteristics: connectedCharacteristics,
    };

    for (const characteristic of characteristics) {
      await this.subscribeOrReadIfUseful(characteristic, services);
    }

    this.connectionState = "ready";
    this.log("info", "ble", `connected ${device.profileLabel} ${device.id}`);
    this.emitState();
    if (options.autoHello !== false) {
      await this.sendClientHelloIfNeeded("gatt_discovery");
    }
    return this.getState();
  }

  async disconnect(): Promise<DebuggerAppState> {
    if (!this.active) {
      this.connectionState = "idle";
      this.emitState();
      return this.getState();
    }
    const peripheral = this.active.peripheral;
    this.connectionState = "disconnecting";
    this.emitState();
    await disconnectPeripheral(peripheral);
    this.active = undefined;
    this.clientHelloSentForCurrentConnection = false;
    this.resetConnectionDiagnostics();
    this.connectionState = "disconnected";
    this.emitState();
    return this.getState();
  }

  async setDatabasePath(databasePath: string): Promise<DebuggerAppState> {
    if (this.capture.active) {
      throw new Error("Stop capture before changing the database path.");
    }
    this.capture = {
      ...this.capture,
      databasePath,
      lastImportStatus: "database path updated",
    };
    this.emitState();
    return this.getState();
  }

  async startCapture(options: { databasePath?: string } = {}): Promise<DebuggerAppState> {
    if (this.capture.active) {
      return this.getState();
    }
    const databasePath = options.databasePath ?? this.capture.databasePath;
    await fs.mkdir(path.dirname(databasePath), { recursive: true });
    const now = Date.now();
    const sessionId = `desktop-${now.toString(36)}-${++this.captureSessionCounter}`;
    const deviceModel = this.active
      ? `${this.active.device.profileLabel} ${this.active.device.name}`.trim()
      : "desktop ble debugger";
    await this.rust.startCaptureSession({
      databasePath,
      sessionId,
      source: "mac.bluetooth.desktop_debugger",
      startedAtUnixMs: now,
      deviceModel,
      ...(this.active?.device.id ? { activeDeviceId: this.active.device.id } : {}),
      provenance: {
        tool: "ble-packet-debugger",
        transport: "macos-node-noble",
        parser: "rust-bridge",
      },
    });
    this.rrReferenceNotificationCounter = 0;
    this.capture = {
      active: true,
      databasePath,
      sessionId,
      startedAt: new Date(now).toISOString(),
      frameCount: 0,
      rawInserted: 0,
      rawExisting: 0,
      framesInserted: 0,
      framesExisting: 0,
      pendingFrames: 0,
      flushing: false,
      lastImportStatus: "capture active",
    };
    this.log("info", "capture", `session ${sessionId} started`);
    this.emitState();
    return this.getState();
  }

  async stopCapture(): Promise<DebuggerAppState> {
    if (!this.capture.active || !this.capture.sessionId) {
      return this.getState();
    }
    await this.flushCaptureQueue();
    await this.rust.finishCaptureSession({
      databasePath: this.capture.databasePath,
      sessionId: this.capture.sessionId,
      endedAtUnixMs: Date.now(),
      frameCount: this.capture.frameCount,
    });
    this.capture = {
      ...this.capture,
      active: false,
      flushing: false,
      pendingFrames: 0,
      lastImportStatus: "capture finished",
    };
    this.log("info", "capture", `session ${this.capture.sessionId} finished`);
    this.emitState();
    return this.getState();
  }

  async storageCheck(): Promise<StorageCheckResult> {
    await fs.mkdir(path.dirname(this.capture.databasePath), { recursive: true });
    const report = await this.rust.storageCheck(this.capture.databasePath);
    const pass = typeof report === "object" && report !== null && "pass" in report
      ? Boolean((report as { pass: unknown }).pass)
      : false;
    this.capture = {
      ...this.capture,
      lastImportStatus: pass ? "storage check passed" : "storage check reported issues",
    };
    this.emitState();
    return { pass, report };
  }

  async sendHello(): Promise<DebuggerAppState> {
    await this.sendClientHello("manual", true);
    return this.getState();
  }

  async startIosParityPhysiologyProbe(delayMs = IOS_PARITY_PHYSIOLOGY_DELAY_MS): Promise<DebuggerAppState> {
    await this.sendClientHelloIfNeeded("ios_parity_probe");
    await delay(delayMs);
    return this.startPhysiologyCapture();
  }

  async startBandParityProbe(options: {
    databasePath?: string | undefined;
    scanTimeoutMs?: number | undefined;
    observeSeconds?: number | undefined;
  } = {}): Promise<DebuggerAppState> {
    const scanTimeoutMs = options.scanTimeoutMs ?? BAND_PARITY_SCAN_TIMEOUT_MS;
    const observeSeconds = options.observeSeconds ?? BAND_PARITY_OBSERVE_SECONDS;
    const startedAt = new Date().toISOString();
    this.bandParityProbe = {
      active: true,
      stage: "preparing",
      startedAt,
      message: "preparing fresh desktop band probe",
    };
    this.log("info", "probe", "band parity probe starting");
    this.emitState();

    try {
      if (this.capture.active) {
        this.setBandParityStage("stopping existing capture");
        await this.stopCapture();
      }
      if (this.scanning) {
        this.setBandParityStage("stopping existing scan");
        await this.stopScan();
      }
      if (this.active) {
        this.setBandParityStage("disconnecting existing device");
        await this.disconnect();
      }

      this.devices.clear();
      this.peripherals.clear();
      this.setBandParityStage("scanning for custom-service band");
      await this.startScan();
      const target = await this.waitForCustomBandDevice(scanTimeoutMs);
      if (!target) {
        throw new Error(`No custom-service compatible band found after ${Math.round(scanTimeoutMs / 1000)} seconds.`);
      }

      this.bandParityProbe = {
        ...this.bandParityProbe,
        targetDeviceId: target.id,
        targetDeviceName: target.name,
      };
      this.setBandParityStage("connecting to compatible band");
      if (this.scanning) {
        await this.stopScan();
      }
      await this.connect(target.id, { autoHello: false });

      this.setBandParityStage("starting local capture");
      await this.startCapture(options.databasePath ? { databasePath: options.databasePath } : {});

      this.setBandParityStage("verifying fd4b command and notify chars");
      this.verifyFd4bParityReady();

      const notifyCountBeforeProbe = this.fd4bNotifyPacketsReceived;
      this.setBandParityStage("sending client hello");
      await this.sendClientHello("band_parity_probe", true);

      this.setBandParityStage("waiting for hello response");
      const helloResponseReceived = await this.waitForHelloResponse(IOS_PARITY_PHYSIOLOGY_DELAY_MS);
      if (!helloResponseReceived) {
        const seconds = Math.round(IOS_PARITY_PHYSIOLOGY_DELAY_MS / 1000);
        const commandResponseText = this.commandResponsesReceived === 0
          ? "no command responses received"
          : `${this.commandResponsesReceived} command responses received, none for GET_HELLO`;
        const fd4bRequested = REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS
          .filter((uuid) => this.requestedCustomNotifyUuids.has(uuid)).length;
        const fd4bConfirmed = REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS
          .filter((uuid) => this.subscribedCustomNotifyUuids.has(uuid)).length;
        const authHint = this.notifySubscriptionFailureHint(fd4bRequested, fd4bConfirmed) ?? "";
        this.bandParityProbe = {
          ...this.bandParityProbe,
          active: false,
          stage: authHint ? "auth required" : "no hello response",
          completedAt: new Date().toISOString(),
          success: false,
          message: `No GET_HELLO command response after ${seconds} seconds; ${commandResponseText}.${authHint}`,
          noHelloResponseAfterSeconds: seconds,
        };
        this.log("warn", "probe", this.bandParityProbe.message ?? "band parity probe saw no hello response");
        this.emitState();
        return this.getState();
      }

      this.setBandParityStage("starting physiology sequence");
      await this.startPhysiologyCapture();

      this.setBandParityStage("watching for custom notify frames");
      await delay(observeSeconds * 1000);

      const notifyDelta = this.fd4bNotifyPacketsReceived - notifyCountBeforeProbe;
      if (notifyDelta > 0) {
        this.bandParityProbe = {
          ...this.bandParityProbe,
          active: false,
          stage: "custom notify frames received",
          completedAt: new Date().toISOString(),
          success: true,
          message: `${notifyDelta} fd4b custom notify packets received after physiology start`,
        };
        this.log("info", "probe", this.bandParityProbe.message ?? "band parity probe received custom notify packets");
      } else {
        this.bandParityProbe = {
          ...this.bandParityProbe,
          active: false,
          stage: "no custom frames",
          completedAt: new Date().toISOString(),
          success: false,
          message: `No fd4b custom notify frames after ${observeSeconds} seconds`,
          noCustomFramesAfterSeconds: observeSeconds,
        };
        this.log("warn", "probe", this.bandParityProbe.message ?? "band parity probe saw no custom notify frames");
      }
    } catch (error) {
      const message = errorMessage(error);
      this.bandParityProbe = {
        ...this.bandParityProbe,
        active: false,
        stage: "failed",
        completedAt: new Date().toISOString(),
        success: false,
        message,
      };
      this.log("error", "probe", message);
    }

    this.emitState();
    return this.getState();
  }

  async checkMacPairingStatus(): Promise<DebuggerAppState> {
    this.macPairingStatus = {
      ...this.macPairingStatus,
      active: true,
      stage: "checking",
      message: "checking macOS Bluetooth registry",
    };
    this.log("info", "pairing", "checking macOS Bluetooth registry");
    this.emitState();

    try {
      const lines: string[] = [];
      const result = await runProcessCapture("system_profiler", ["SPBluetoothDataType"], {
        cwd: this.repoRoot,
        timeoutMs: 20_000,
        onLine: (line) => lines.push(line),
      });
      if (result.exitCode !== 0) {
        throw new Error(`system_profiler exited code=${result.exitCode}`);
      }
      const parsed = parseMacBluetoothBandStatus(lines);
      const advertising = await this.findCustomBandAdvertisement(MAC_PAIRING_ADVERTISEMENT_SCAN_MS);
      const stage = parsed.known
        ? parsed.connected ? "connected" : "registered"
        : advertising ? "advertising unregistered"
        : "not registered";
      this.macPairingStatus = {
        active: false,
        stage,
        checkedAt: new Date().toISOString(),
        known: parsed.known,
        connected: parsed.connected,
        matchedCount: parsed.matchedCount,
        advertising: advertising !== undefined,
        ...(advertising ? {
          advertisingDeviceId: advertising.id,
          advertisingName: advertising.name,
          advertisingRssi: advertising.rssi,
          advertisingServices: advertising.advertisedServices.map(displayUuid),
        } : {}),
        message: parsed.known
          ? parsed.connected
            ? "Compatible band is listed as connected in macOS Bluetooth."
            : "Compatible band is listed in macOS Bluetooth but is not connected."
          : advertising
            ? `Compatible band is advertising the custom fd4b service at ${advertising.rssi} dBm, but macOS Bluetooth has not registered it; secure fd4b notifications still require a bonded/authenticated link.`
          : "Compatible band is not listed in macOS Bluetooth; pair or bond it before expecting fd4b notifications.",
      };
      this.log(parsed.known ? "info" : "warn", "pairing", this.macPairingStatus.message ?? stage);
    } catch (error) {
      const message = errorMessage(error);
      this.macPairingStatus = {
        ...this.macPairingStatus,
        active: false,
        stage: "failed",
        checkedAt: new Date().toISOString(),
        known: false,
        connected: false,
        matchedCount: 0,
        message,
      };
      this.log("error", "pairing", message);
    }

    this.emitState();
    return this.getState();
  }

  async runNativeAuthProbe(): Promise<DebuggerAppState> {
    const startedAt = new Date().toISOString();
    this.nativeAuthProbe = {
      active: true,
      stage: "preparing",
      startedAt,
      output: [],
      authErrors: [],
      message: "preparing native CoreBluetooth auth probe",
    };
    this.log("info", "auth-probe", "native auth probe starting");
    this.emitState();

    try {
      if (this.capture.active) {
        await this.stopCapture();
      }
      if (this.scanning) {
        await this.stopScan();
      }
      if (this.active) {
        await this.disconnect();
      }

      const toolRoot = path.join(this.repoRoot, "Tools/ble-packet-debugger");
      const scriptPath = path.join(toolRoot, "scripts/corebluetooth_probe.swift");
      const outputPath = "/tmp/openvitals-corebluetooth-probe";
      this.setNativeAuthProbeStage("compiling native probe");
      const compile = await runProcessCapture("swiftc", [
        "-framework",
        "Foundation",
        "-framework",
        "CoreBluetooth",
        scriptPath,
        "-o",
        outputPath,
      ], {
        cwd: toolRoot,
        onLine: (line) => this.recordNativeAuthProbeLine(line),
      });
      if (compile.exitCode !== 0) {
        throw new Error(`native auth probe compile failed code=${compile.exitCode}`);
      }

      this.setNativeAuthProbeStage("running native probe");
      const run = await runProcessCapture(outputPath, [], {
        cwd: toolRoot,
        timeoutMs: 60_000,
        onLine: (line) => this.recordNativeAuthProbeLine(line),
      });
      const output = this.nativeAuthProbe.output;
      const authErrors = output.filter((line) => /authenticat|encrypt/i.test(line));
      const success = run.exitCode === 0 && output.some((line) => /custom notify received/i.test(line));
      const authBlocked = authErrors.length > 0;
      this.nativeAuthProbe = {
        ...this.nativeAuthProbe,
        active: false,
        stage: success ? "custom notify received" : authBlocked ? "auth required" : "finished",
        completedAt: new Date().toISOString(),
        exitCode: run.exitCode,
        success,
        authErrors,
        message: success
          ? "Native CoreBluetooth probe received a custom notify frame."
          : authBlocked
            ? "Native CoreBluetooth probe confirmed authentication/encryption is required before fd4b notifications can enable."
            : `Native CoreBluetooth probe finished code=${run.exitCode}; no custom notify frame received.`,
      };
      this.log(success ? "info" : "warn", "auth-probe", this.nativeAuthProbe.message ?? "native auth probe finished");
    } catch (error) {
      const message = errorMessage(error);
      this.nativeAuthProbe = {
        ...this.nativeAuthProbe,
        active: false,
        stage: "failed",
        completedAt: new Date().toISOString(),
        success: false,
        message,
      };
      this.log("error", "auth-probe", message);
    }

    this.emitState();
    return this.getState();
  }

  private async sendClientHelloIfNeeded(reason: string): Promise<void> {
    if (this.clientHelloSentForCurrentConnection) {
      this.log("info", "ble", `hello skipped reason=${reason} already sent`);
      return;
    }
    await this.sendClientHello(reason, false);
  }

  private async sendClientHello(reason: string, force: boolean): Promise<void> {
    if (this.clientHelloSentForCurrentConnection && !force) {
      this.log("info", "ble", `hello skipped reason=${reason} already sent`);
      return;
    }
    const active = this.active;
    if (!active?.commandCharacteristic) {
      if (force) {
        throw new Error("No writable command characteristic is active.");
      }
      return;
    }
    const writeType = writeTypeForCharacteristic(active.commandCharacteristic);
    const frame = Buffer.from(CLIENT_HELLO_FRAME_HEX, "hex");
    this.lastHelloFrameHex = CLIENT_HELLO_FRAME_HEX;
    await writeCharacteristic(active.commandCharacteristic, frame, writeType.withoutResponse);
    this.commandWritesAccepted += 1;
    this.clientHelloSentForCurrentConnection = true;
    this.recordFramePacket({
      direction: "write",
      source: "mac.ble.command_write.get_hello",
      serviceUuid: displayUuid(characteristicServiceUuid(active.commandCharacteristic, [])),
      characteristicUuid: displayUuid(active.commandCharacteristic.uuid),
      frame,
      raw: frame,
      capturedAt: new Date(),
      deviceType: "OPENVITALS",
      summary: `Client hello GET_HELLO reason=${reason} writeType=${writeType.name}`,
    });
    this.log("info", "ble", `hello frame sent reason=${reason} writeType=${writeType.name}`);
    this.emitState();
  }

  async startPhysiologyCapture(): Promise<DebuggerAppState> {
    return this.sendSensorStreamCommands("start physiology", PHYSIOLOGY_START_COMMANDS);
  }

  async stopPhysiologyCapture(): Promise<DebuggerAppState> {
    return this.sendSensorStreamCommands("stop physiology", PHYSIOLOGY_STOP_COMMANDS);
  }

  async enterHighFrequencyHistorySync(intervalSeconds = 180, durationSeconds = 7_200): Promise<DebuggerAppState> {
    return this.sendSensorStreamCommands("enter high-frequency history sync", [
      highFrequencyHistorySyncCommand(intervalSeconds, durationSeconds),
    ]);
  }

  async exitHighFrequencyHistorySync(): Promise<DebuggerAppState> {
    return this.sendSensorStreamCommands("exit high-frequency history sync", [HIGH_FREQUENCY_EXIT_COMMAND]);
  }

  selectPacket(packetId: string): DebuggerAppState {
    this.selectedPacketId = packetId;
    this.emitState();
    return this.getState();
  }

  async shutdown(): Promise<void> {
    if (this.capture.active) {
      await this.stopCapture();
    }
    if (this.scanning) {
      await stopScanning();
    }
    this.rust.stop();
  }

  private handleDiscover(peripheral: NoblePeripheral): void {
    this.peripherals.set(peripheral.id, peripheral);
    const device = discoveredDeviceFromPeripheral(peripheral);
    this.devices.set(device.id, device);
    this.emitState();
  }

  private async sendSensorStreamCommands(label: string, commands: SensorStreamCommand[]): Promise<DebuggerAppState> {
    const active = this.active;
    if (!active?.commandCharacteristic) {
      throw new Error("No writable command characteristic is active.");
    }

    const writeType = writeTypeForCharacteristic(active.commandCharacteristic);
    for (const [index, command] of commands.entries()) {
      const sequence = this.takeNextSensorCommandSequence();
      const payloadHex = Buffer.from(command.payload).toString("hex");
      const built = await this.rust.buildV5CommandFrame(sequence, command.commandNumber, payloadHex);
      const frame = Buffer.from(built.frame_hex, "hex");
      await writeCharacteristic(
        active.commandCharacteristic,
        frame,
        writeType.withoutResponse,
      );
      this.commandWritesAccepted += 1;
      this.recordFramePacket({
        direction: "write",
        source: `mac.ble.command_write.sensor.${command.name.toLowerCase()}`,
        serviceUuid: displayUuid(characteristicServiceUuid(active.commandCharacteristic, [])),
        characteristicUuid: displayUuid(active.commandCharacteristic.uuid),
        frame,
        raw: frame,
        capturedAt: new Date(),
        deviceType: "OPENVITALS",
        summary: `Command ${command.name} (${command.commandNumber}) seq=${sequence} payload=${payloadHex || "-"} writeType=${writeType.name}`,
      });
      this.log("info", "ble", `${label} command ${command.name} sent seq=${sequence} writeType=${writeType.name}`);
      if (index < commands.length - 1) {
        await delay(SENSOR_COMMAND_DELAY_MS);
      }
    }

    this.emitState();
    return this.getState();
  }

  private takeNextSensorCommandSequence(): number {
    const sequence = this.nextSensorCommandSequence;
    this.nextSensorCommandSequence = this.nextSensorCommandSequence >= 255 ? 180 : this.nextSensorCommandSequence + 1;
    return sequence;
  }

  private async subscribeOrReadIfUseful(characteristic: NobleCharacteristic, services: NobleService[]): Promise<void> {
    const characteristicUuid = compactUuid(characteristic.uuid);
    const canNotify = characteristic.properties.includes("notify") || characteristic.properties.includes("indicate");
    const shouldNotify = NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)
      || characteristicUuid === STANDARD_HEART_RATE_MEASUREMENT_UUID
      || characteristicUuid === BATTERY_LEVEL_UUID
      || characteristicUuid === BATTERY_LEVEL_STATUS_UUID;

    if (NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)) {
      this.log(
        "info",
        "ble",
        `custom notify candidate ${displayUuid(characteristicUuid)} properties=${characteristic.properties.join(",") || "none"}`,
      );
      if (!canNotify) {
        this.log(
          "warn",
          "ble",
          `custom notify unavailable ${displayUuid(characteristicUuid)} properties=${characteristic.properties.join(",") || "none"}`,
        );
      }
    }

    if (shouldNotify && canNotify) {
      characteristic.on("notify", (state: boolean) => {
        if (!NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)) {
          return;
        }
        if (state) {
          this.subscribedCustomNotifyUuids.add(characteristicUuid);
        } else {
          this.subscribedCustomNotifyUuids.delete(characteristicUuid);
        }
        this.log("info", "ble", `notify state ${displayUuid(characteristicUuid)} ${state ? "subscribed" : "unsubscribed"}`);
        this.emitState();
      });
      characteristic.on("data", (data: Buffer) => {
        void this.handleValue(characteristic, services, data, "notify");
      });
      if (NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)) {
        this.requestedCustomNotifyUuids.add(characteristicUuid);
        this.notifySubscriptionErrors.delete(characteristicUuid);
        this.log("info", "ble", `requested custom notify ${displayUuid(characteristicUuid)}`);
        this.emitState();
      }
      const notifying = NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)
        ? await this.subscribeCustomNotifyWithRetry(characteristic, characteristicUuid)
        : await subscribeCharacteristic(characteristic).catch((error: unknown) => {
          this.log("warn", "ble", `notify state ${displayUuid(characteristicUuid)} failed: ${errorMessage(error)}`);
          return false;
        });
      if (NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)) {
        if (notifying) {
          this.subscribedCustomNotifyUuids.add(characteristicUuid);
          this.notifySubscriptionErrors.delete(characteristicUuid);
          this.log("info", "ble", `subscribed custom notify ${displayUuid(characteristicUuid)}`);
        } else {
          this.subscribedCustomNotifyUuids.delete(characteristicUuid);
          if (!this.notifySubscriptionErrors.has(characteristicUuid)) {
            this.notifySubscriptionErrors.set(characteristicUuid, "notification state not confirmed");
          }
          this.log("warn", "ble", `custom notify did not enable ${displayUuid(characteristicUuid)}`);
        }
      }
    }

    const shouldRead = characteristic.properties.includes("read")
      && (characteristicUuid === BATTERY_LEVEL_UUID
        || characteristicUuid === BATTERY_LEVEL_STATUS_UUID
        || DEVICE_INFORMATION_CHARACTERISTIC_UUIDS.has(characteristicUuid));
    if (shouldRead) {
      try {
        const data = await readCharacteristic(characteristic);
        await this.handleValue(characteristic, services, data, "read");
      } catch (error) {
        this.log("warn", "ble", `read ${displayUuid(characteristicUuid)} failed: ${errorMessage(error)}`);
      }
    }
  }

  private async handleValue(
    characteristic: NobleCharacteristic,
    services: NobleService[],
    data: Buffer,
    direction: "notify" | "read",
  ): Promise<void> {
    const characteristicUuid = compactUuid(characteristic.uuid);
    const serviceUuid = displayUuid(characteristicServiceUuid(characteristic, services));
    const capturedAt = new Date();
    const source = `mac.ble.${direction}.${displayUuid(characteristicUuid)}`;

    if (direction === "notify" && NOTIFICATION_CHARACTERISTIC_SET.has(characteristicUuid)) {
      this.customNotifyPacketsReceived += 1;
      if (characteristicUuid.startsWith("fd4b")) {
        this.fd4bNotifyPacketsReceived += 1;
      }
    }

    if (characteristicUuid === STANDARD_HEART_RATE_MEASUREMENT_UUID) {
      const sample = parseStandardHeartRateMeasurement(data);
      this.recordRawPacket({
        direction,
        source,
        serviceUuid,
        characteristicUuid: displayUuid(characteristicUuid),
        raw: data,
        capturedAt,
        deviceType: "OPENVITALS",
        parserStatus: "raw",
        summary: sample ? `Heart rate ${sample.bpm} bpm rr=${sample.rrIntervalsMs.length}` : "Heart rate parse failed",
        ...(sample ? { standardHeartRate: sample } : {}),
      });
      if (sample) {
        this.storeRrReferenceSamples(sample, capturedAt);
      }
      return;
    }

    if (!isCustomBandCharacteristic(characteristicUuid)) {
      this.recordRawPacket({
        direction,
        source,
        serviceUuid,
        characteristicUuid: displayUuid(characteristicUuid),
        raw: data,
        capturedAt,
        deviceType: "OPENVITALS",
        parserStatus: "raw",
        summary: `${data.length} raw bytes`,
      });
      return;
    }

    const deviceType = rustDeviceTypeForCharacteristic(characteristicUuid);
    const key = `${deviceType}:${characteristicUuid}`;
    const accumulator = this.accumulators.get(key) ?? new FrameAccumulator(deviceType);
    this.accumulators.set(key, accumulator);
    const result = accumulator.feed(data);
    for (const frame of result.frames) {
      this.recordFramePacket({
        direction,
        source,
        serviceUuid,
        characteristicUuid: displayUuid(characteristicUuid),
        frame,
        raw: data,
        capturedAt,
        deviceType,
        summary: `${frame.length} byte frame`,
      });
    }
    if (result.frames.length === 0 && result.bufferedLen > 0) {
      this.recordRawPacket({
        direction,
        source,
        serviceUuid,
        characteristicUuid: displayUuid(characteristicUuid),
        raw: data,
        capturedAt,
        deviceType,
        parserStatus: "buffered",
        summary: `buffering ${result.bufferedLen} bytes`,
      });
    }
    if (result.droppedPrefixLen > 0) {
      this.log("warn", "ble", `dropped ${result.droppedPrefixLen} bytes before frame start`);
    }
  }

  private async subscribeCustomNotifyWithRetry(
    characteristic: NobleCharacteristic,
    characteristicUuid: string,
  ): Promise<boolean> {
    for (let attempt = 1; attempt <= CUSTOM_NOTIFY_RETRY_ATTEMPTS; attempt += 1) {
      if (attempt > 1) {
        this.notifyRetryAttempts += 1;
        this.log("info", "ble", `retry custom notify ${displayUuid(characteristicUuid)} attempt=${attempt}`);
        this.emitState();
        await delay(CUSTOM_NOTIFY_RETRY_DELAY_MS);
      }

      try {
        const notifying = await subscribeCharacteristic(characteristic);
        if (notifying) {
          this.notifySubscriptionErrors.delete(characteristicUuid);
          if (attempt > 1) {
            this.notifyRetryConfirmed += 1;
            this.emitState();
          }
          return true;
        }
        this.log("warn", "ble", `notify state ${displayUuid(characteristicUuid)} unsubscribed attempt=${attempt}`);
      } catch (error) {
        if (attempt > 1) {
          this.notifyRetryErrors += 1;
        }
        const message = errorMessage(error);
        this.notifySubscriptionErrors.set(characteristicUuid, message);
        this.log("warn", "ble", `notify state ${displayUuid(characteristicUuid)} failed attempt=${attempt}: ${message}`);
      }
    }
    this.emitState();
    return false;
  }

  private recordFramePacket(args: {
    direction: "notify" | "read" | "write";
    source: string;
    serviceUuid: string;
    characteristicUuid: string;
    frame: Buffer;
    raw: Buffer;
    capturedAt: Date;
    deviceType: RustDeviceType;
    summary: string;
  }): void {
    const packet = this.basePacket({
      direction: args.direction,
      source: args.source,
      serviceUuid: args.serviceUuid,
      characteristicUuid: args.characteristicUuid,
      raw: args.raw,
      frameHex: args.frame.toString("hex"),
      capturedAt: args.capturedAt,
      deviceType: args.deviceType,
      parserStatus: "pending",
      summary: args.summary,
    });
    this.pushPacket(packet);
    this.enqueueCapture(packet, args.frame, args.deviceType);
    void this.parsePacket(packet.id, args.frame.toString("hex"), args.deviceType);
  }

  private recordRawPacket(args: {
    direction: "notify" | "read";
    source: string;
    serviceUuid: string;
    characteristicUuid: string;
    raw: Buffer;
    capturedAt: Date;
    deviceType: RustDeviceType;
    parserStatus: "raw" | "buffered";
    summary: string;
    standardHeartRate?: StandardHeartRateSample;
  }): void {
    const packet = this.basePacket({
      direction: args.direction,
      source: args.source,
      serviceUuid: args.serviceUuid,
      characteristicUuid: args.characteristicUuid,
      raw: args.raw,
      frameHex: args.raw.toString("hex"),
      capturedAt: args.capturedAt,
      deviceType: args.deviceType,
      parserStatus: args.parserStatus,
      summary: args.summary,
      ...(args.standardHeartRate ? { standardHeartRate: args.standardHeartRate } : {}),
    });
    this.pushPacket(packet);
    if (args.parserStatus === "raw") {
      this.enqueueCapture(packet, args.raw, args.deviceType);
    }
  }

  private basePacket(args: {
    direction: "notify" | "read" | "write";
    source: string;
    serviceUuid: string;
    characteristicUuid: string;
    raw: Buffer;
    frameHex: string;
    capturedAt: Date;
    deviceType: RustDeviceType;
    parserStatus: "pending" | "raw" | "buffered";
    summary: string;
    standardHeartRate?: StandardHeartRateSample;
  }): PacketRecord {
    const id = `packet-${Date.now()}-${++this.packetCounter}`;
    return {
      id,
      capturedAt: args.capturedAt.toISOString(),
      direction: args.direction,
      source: args.source,
      serviceUuid: args.serviceUuid,
      characteristicUuid: args.characteristicUuid,
      bytes: args.raw.length,
      rawHex: args.raw.toString("hex"),
      frameHex: args.frameHex,
      deviceType: args.deviceType,
      parserStatus: args.parserStatus,
      summary: args.summary,
      warnings: [],
      importIssues: [],
      ...(this.active ? {
        deviceId: this.active.device.id,
        deviceName: this.active.device.name,
      } : {}),
      ...(args.standardHeartRate ? { standardHeartRate: args.standardHeartRate } : {}),
    };
  }

  private pushPacket(packet: PacketRecord): void {
    this.packets.unshift(packet);
    this.selectedPacketId = this.selectedPacketId ?? packet.id;
    if (this.packets.length > MAX_PACKETS) {
      this.packets.splice(MAX_PACKETS);
    }
    this.emitState();
  }

  private async parsePacket(packetId: string, frameHex: string, deviceType: RustDeviceType): Promise<void> {
    try {
      const response = await this.rust.parseFrameBatch([frameHex], deviceType) as ParseBatchResponse;
      const result = response.results?.[0];
      if (result?.ok) {
        const packet = this.packets.find((candidate) => candidate.id === packetId);
        this.recordParsedProtocolDiagnostics(packet, result);
        this.updatePacket(packetId, (packet) => ({
          ...packet,
          parserStatus: "parsed",
          summary: result.compact?.summary ?? packet.summary,
          warnings: result.result?.warnings ?? [],
          parsedJson: result.result,
          ...optionalField("packetType", result.compact?.packet_type ?? result.result?.packet_type),
          ...optionalField("packetTypeName", result.compact?.packet_type_name ?? result.result?.packet_type_name),
          ...optionalField("sequence", result.compact?.sequence ?? result.result?.sequence),
          ...optionalField("commandOrEvent", result.result?.command_or_event),
          ...optionalField("payloadKind", result.compact?.payload_kind),
        }));
      } else {
        this.updatePacket(packetId, (packet) => ({
          ...packet,
          parserStatus: "parse_failed",
          importIssues: [result?.error ?? "parse failed"],
          summary: result?.error ?? packet.summary,
        }));
      }
    } catch (error) {
      this.updatePacket(packetId, (packet) => ({
        ...packet,
        parserStatus: "parse_failed",
        importIssues: [errorMessage(error)],
      }));
    }
  }

  private recordParsedProtocolDiagnostics(
    packet: PacketRecord | undefined,
    result: NonNullable<ParseBatchResponse["results"]>[number],
  ): void {
    const payloadKind = result.compact?.payload_kind ?? result.result?.parsed_payload?.kind;
    if (payloadKind !== "command_response") {
      return;
    }

    const payload = result.result?.parsed_payload;
    const responseToCommand = payload?.response_to_command ?? result.result?.command_or_event;
    const responseToCommandName = payload?.response_to_command_name;
    const originSequence = payload?.origin_sequence;
    const resultCode = payload?.result_code;

    this.commandResponsesReceived += 1;
    this.lastCommandResponse = {
      ...(responseToCommand !== undefined ? { responseToCommand } : {}),
      ...(responseToCommandName ? { responseToCommandName } : {}),
      ...(originSequence !== undefined ? { originSequence } : {}),
      ...(resultCode !== undefined ? { resultCode } : {}),
      ...(result.result?.sequence !== undefined ? { sequence: result.result.sequence } : {}),
      ...(packet?.characteristicUuid ? { characteristicUuid: packet.characteristicUuid } : {}),
      ...(packet?.capturedAt ? { capturedAt: packet.capturedAt } : {}),
    };

    const commandName = responseToCommandName ?? (responseToCommand !== undefined ? `command ${responseToCommand}` : "unknown command");
    this.log("info", "ble", `command response ${commandName} originSeq=${originSequence ?? "-"} result=${resultCode ?? "-"}`);

    if (responseToCommand === COMMAND_GET_HELLO || responseToCommandName === "GET_HELLO") {
      this.helloResponseReceived = true;
      this.helloResponseResultCode = resultCode;
      this.log("info", "ble", `hello response received result=${resultCode ?? "-"}`);
    }
    this.emitState();
  }

  private enqueueCapture(packet: PacketRecord, frame: Buffer, deviceType: RustDeviceType): void {
    if (!this.capture.active || !this.capture.sessionId) {
      return;
    }
    const evidenceId = `${this.capture.sessionId}.e${++this.evidenceCounter}`;
    const capturedFrame: CapturedFrameInput = {
      evidence_id: evidenceId,
      frame_id: `${evidenceId}.frame.0`,
      source: packet.source,
      captured_at: packet.capturedAt,
      device_model: this.active
        ? `${this.active.device.profileLabel} ${this.active.device.name}`.trim()
        : "desktop ble debugger",
      frame_hex: frame.toString("hex"),
      sensitivity: "sensitive",
      capture_session_id: this.capture.sessionId,
      device_type: deviceType,
    };
    packet.evidenceId = evidenceId;
    this.captureQueue.push({ packetId: packet.id, frame: capturedFrame });
    this.capture = {
      ...this.capture,
      frameCount: this.capture.frameCount + 1,
      pendingFrames: this.captureQueue.length,
      lastImportStatus: "queued",
    };
    if (this.captureQueue.length >= 50) {
      void this.flushCaptureQueue();
    } else {
      this.scheduleFlush();
    }
  }

  private storeRrReferenceSamples(sample: StandardHeartRateSample, capturedAt: Date): void {
    if (!this.capture.active || !this.capture.sessionId || sample.rrIntervalsMs.length === 0) {
      return;
    }
    const active = this.active;
    if (!active) {
      return;
    }

    const notificationSequence = ++this.rrReferenceNotificationCounter;
    const sessionId = this.capture.sessionId;
    const capturedAtText = capturedAt.toISOString();
    const rows: RrReferenceSampleInput[] = sample.rrIntervalsMs.map((rrIntervalMs, index) => ({
      sample_id: `${sessionId}.rr.${notificationSequence}.${index}`,
      session_id: sessionId,
      captured_at: capturedAtText,
      device_name: active.device.name,
      device_id: active.device.id,
      heart_rate_bpm: sample.bpm,
      rr_interval_ms: rrIntervalMs,
      notification_sequence: notificationSequence,
      rr_index: index,
      ...(sample.contactDetected === undefined ? {} : { contact_detected: sample.contactDetected }),
      ...(sample.energyExpendedJ === undefined ? {} : { energy_expended_j: sample.energyExpendedJ }),
      provenance: {
        schema: "open_vitals.rr-reference-sample-provenance.v1",
        collector: "ble-packet-debugger",
        service_uuid: STANDARD_HEART_RATE_SERVICE_UUID,
        characteristic_uuid: STANDARD_HEART_RATE_MEASUREMENT_UUID,
        source: "standard_ble_heart_rate_service",
        transport: "macos-node-noble",
        storage_policy: "standard_ble_rr_reference_for_validation_only",
      },
    }));

    void this.rust.insertRrReferenceSamples(this.capture.databasePath, rows)
      .then((report) => {
        const insertReport = report as RrReferenceInsertResponse;
        const inserted = insertReport.inserted_count ?? rows.length;
        const existing = insertReport.existing_count ?? 0;
        this.capture = {
          ...this.capture,
          lastImportStatus: `stored ${inserted} RR reference samples${existing ? ` (${existing} existing)` : ""}`,
        };
        this.emitState();
      })
      .catch((error) => {
        const message = `RR reference store failed: ${errorMessage(error)}`;
        this.capture = {
          ...this.capture,
          lastImportStatus: message,
        };
        this.log("error", "capture", message);
      });
  }

  private scheduleFlush(): void {
    if (this.flushTimer) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined;
      void this.flushCaptureQueue();
    }, 500);
  }

  private async flushCaptureQueue(): Promise<void> {
    if (this.captureQueue.length === 0 || !this.capture.active) {
      return;
    }
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = undefined;
    }
    const batch = this.captureQueue.splice(0);
    this.capture = {
      ...this.capture,
      flushing: true,
      pendingFrames: this.captureQueue.length,
      lastImportStatus: `importing ${batch.length}`,
    };
    this.emitState();
    try {
      const report = await this.rust.importFrameBatch(
        this.capture.databasePath,
        batch.map((item) => item.frame),
      ) as ImportBatchResponse;
      const resultByEvidence = new Map(
        (report.results ?? [])
          .filter((result) => result.evidence_id)
          .map((result) => [result.evidence_id as string, result]),
      );
      for (const item of batch) {
        const result = resultByEvidence.get(item.frame.evidence_id);
        if (!result) {
          continue;
        }
        this.updatePacket(item.packetId, (packet) => ({
          ...packet,
          importIssues: result.issues ?? packet.importIssues,
        }), false);
      }
      this.capture = {
        ...this.capture,
        rawInserted: this.capture.rawInserted + (report.raw_inserted ?? 0),
        rawExisting: this.capture.rawExisting + (report.raw_existing ?? 0),
        framesInserted: this.capture.framesInserted + (report.frames_inserted ?? 0),
        framesExisting: this.capture.framesExisting + (report.frames_existing ?? 0),
        pendingFrames: this.captureQueue.length,
        flushing: false,
        lastImportStatus: report.issues?.length ? `${report.issues.length} import issues` : "imported",
      };
    } catch (error) {
      const message = errorMessage(error);
      for (const item of batch) {
        this.updatePacket(item.packetId, (packet) => ({
          ...packet,
          importIssues: [...packet.importIssues, message],
        }), false);
      }
      this.capture = {
        ...this.capture,
        pendingFrames: this.captureQueue.length,
        flushing: false,
        lastImportStatus: message,
      };
      this.log("error", "capture", message);
    }
    this.emitState();
  }

  private updatePacket(
    packetId: string,
    update: (packet: PacketRecord) => PacketRecord,
    emit = true,
  ): void {
    const index = this.packets.findIndex((packet) => packet.id === packetId);
    if (index === -1) {
      return;
    }
    const current = this.packets[index];
    if (!current) {
      return;
    }
    this.packets[index] = update(current);
    if (emit) {
      this.emitState();
    }
  }

  private currentDiagnostics(): DesktopDiagnostics {
    const commandCharacteristicUuid = this.active?.commandCharacteristic
      ? displayUuid(compactUuid(this.active.commandCharacteristic.uuid))
      : undefined;
    return {
      fd4bCommandReady: this.isFd4bCommandReady(),
      ...(commandCharacteristicUuid ? { commandCharacteristicUuid } : {}),
      helloSent: this.clientHelloSentForCurrentConnection,
      helloResponseReceived: this.helloResponseReceived,
      ...(this.helloResponseResultCode !== undefined ? { helloResponseResultCode: this.helloResponseResultCode } : {}),
      commandWritesAccepted: this.commandWritesAccepted,
      commandResponsesReceived: this.commandResponsesReceived,
      ...(this.lastCommandResponse ? { lastCommandResponse: { ...this.lastCommandResponse } } : {}),
      customNotifyPacketsReceived: this.customNotifyPacketsReceived,
      fd4bNotifyPacketsReceived: this.fd4bNotifyPacketsReceived,
      notifyRetryAttempts: this.notifyRetryAttempts,
      notifyRetryConfirmed: this.notifyRetryConfirmed,
      notifyRetryErrors: this.notifyRetryErrors,
      requestedCustomNotifyUuids: [...this.requestedCustomNotifyUuids].sort().map(displayUuid),
      subscribedCustomNotifyUuids: [...this.subscribedCustomNotifyUuids].sort().map(displayUuid),
      notifySubscriptionErrors: [...this.notifySubscriptionErrors.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([characteristicUuid, message]) => ({
          characteristicUuid: displayUuid(characteristicUuid),
          message,
        })),
      requiredFd4bNotify: REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS.map((uuid) => ({
        characteristicUuid: displayUuid(uuid),
        requested: this.requestedCustomNotifyUuids.has(uuid),
        subscribed: this.subscribedCustomNotifyUuids.has(uuid),
      })),
      macPairingStatus: { ...this.macPairingStatus },
      nativeAuthProbe: {
        ...this.nativeAuthProbe,
        output: [...this.nativeAuthProbe.output],
        authErrors: [...this.nativeAuthProbe.authErrors],
      },
      bandParityProbe: { ...this.bandParityProbe },
    };
  }

  private resetConnectionDiagnostics(): void {
    this.commandWritesAccepted = 0;
    this.commandResponsesReceived = 0;
    this.helloResponseReceived = false;
    this.helloResponseResultCode = undefined;
    this.lastCommandResponse = undefined;
    this.customNotifyPacketsReceived = 0;
    this.fd4bNotifyPacketsReceived = 0;
    this.notifyRetryAttempts = 0;
    this.notifyRetryConfirmed = 0;
    this.notifyRetryErrors = 0;
    this.requestedCustomNotifyUuids.clear();
    this.subscribedCustomNotifyUuids.clear();
    this.notifySubscriptionErrors.clear();
  }

  private setBandParityStage(stage: string): void {
    this.bandParityProbe = {
      ...this.bandParityProbe,
      active: true,
      stage,
    };
    this.log("info", "probe", stage);
    this.emitState();
  }

  private setNativeAuthProbeStage(stage: string): void {
    this.nativeAuthProbe = {
      ...this.nativeAuthProbe,
      active: true,
      stage,
    };
    this.log("info", "auth-probe", stage);
    this.emitState();
  }

  private recordNativeAuthProbeLine(line: string): void {
    if (line.trim().length === 0) {
      return;
    }
    this.nativeAuthProbe = {
      ...this.nativeAuthProbe,
      output: [...this.nativeAuthProbe.output, line].slice(-80),
      authErrors: /authenticat|encrypt/i.test(line)
        ? [...this.nativeAuthProbe.authErrors, line].slice(-20)
        : this.nativeAuthProbe.authErrors,
    };
    this.log(/authenticat|encrypt|error|failed/i.test(line) ? "warn" : "info", "auth-probe", line);
    this.emitState();
  }

  private async waitForCustomBandDevice(timeoutMs: number): Promise<DiscoveredDevice | undefined> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const target = this.bestCustomBandDevice();
      if (target) {
        return target;
      }
      await delay(BAND_PARITY_POLL_MS);
    }
    return this.bestCustomBandDevice();
  }

  private async findCustomBandAdvertisement(timeoutMs: number): Promise<DiscoveredDevice | undefined> {
    const existing = this.bestCustomBandDevice();
    if (existing) {
      return existing;
    }

    if (this.active?.device.profileId === "custom-band") {
      return this.active.device;
    }

    if (this.scanning) {
      return this.waitForCustomBandDevice(timeoutMs);
    }

    if (this.active) {
      return undefined;
    }

    if (this.bluetoothState !== "poweredOn") {
      await this.waitForBluetoothPoweredOn(BLUETOOTH_POWERED_ON_WAIT_MS);
    }
    if (this.bluetoothState !== "poweredOn") {
      return undefined;
    }

    const previousConnectionState = this.connectionState;
    await startScanning();
    this.scanning = true;
    this.connectionState = "scanning";
    this.emitState();
    try {
      return await this.waitForCustomBandDevice(timeoutMs);
    } finally {
      await stopScanning();
      this.scanning = false;
      if (!this.active) {
        this.connectionState = previousConnectionState;
      }
      this.emitState();
    }
  }

  private async waitForHelloResponse(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (this.helloResponseReceived) {
        return true;
      }
      await delay(Math.min(BAND_PARITY_POLL_MS, Math.max(1, deadline - Date.now())));
    }
    return this.helloResponseReceived;
  }

  private async waitForBluetoothPoweredOn(timeoutMs: number): Promise<boolean> {
    if (this.bluetoothState === "poweredOn" || noble.state === "poweredOn") {
      this.bluetoothState = "poweredOn";
      return true;
    }

    return new Promise((resolve) => {
      let timer: NodeJS.Timeout;
      function finish(poweredOn: boolean): void {
        clearTimeout(timer);
        noble.off("stateChange", listener);
        resolve(poweredOn);
      }
      const listener = (state: string): void => {
        this.bluetoothState = state;
        if (state === "poweredOn") {
          finish(true);
        }
      };
      timer = setTimeout(() => {
        if (noble.state === "poweredOn") {
          this.bluetoothState = "poweredOn";
          finish(true);
        } else {
          finish(false);
        }
      }, timeoutMs);
      noble.on("stateChange", listener);
    });
  }

  private bestCustomBandDevice(): DiscoveredDevice | undefined {
    return [...this.devices.values()]
      .filter((device) => device.profileId === "custom-band"
        && device.advertisedServices.some((uuid) => CUSTOM_BAND_SERVICE_SET.has(uuid)))
      .sort((left, right) => customBandDeviceScore(right) - customBandDeviceScore(left))[0];
  }

  private verifyFd4bParityReady(): void {
    if (!this.isFd4bCommandReady()) {
      const uuid = this.active?.commandCharacteristic?.uuid
        ? displayUuid(compactUuid(this.active.commandCharacteristic.uuid))
        : "missing";
      throw new Error(`fd4b0002 command characteristic unavailable; current command=${uuid}`);
    }

    const missingNotify = REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS
      .filter((uuid) => !this.requestedCustomNotifyUuids.has(uuid))
      .map((uuid) => displayUuid(uuid));
    if (missingNotify.length > 0) {
      throw new Error(`Missing fd4b notify requests: ${missingNotify.join(", ")}`);
    }

    const unconfirmedNotify = REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS
      .filter((uuid) => !this.subscribedCustomNotifyUuids.has(uuid))
      .map((uuid) => displayUuid(uuid));
    if (unconfirmedNotify.length > 0) {
      this.log("warn", "probe", `fd4b notify state not confirmed: ${unconfirmedNotify.join(", ")}`);
      if (this.notifySubscriptionErrors.size > 0) {
        const errorText = [...this.notifySubscriptionErrors.entries()]
          .map(([uuid, message]) => `${displayUuid(uuid)} ${message}`)
          .join("; ");
        this.log("warn", "probe", `fd4b notify enable errors: ${errorText}`);
      }
    }
  }

  private notifySubscriptionFailureHint(fd4bRequested: number, fd4bConfirmed: number): string | undefined {
    const errorText = [...this.notifySubscriptionErrors.values()].join(" ");
    if (/authenticat|encrypt/i.test(errorText)) {
      return " fd4b notification enable failed with authentication/encryption errors; pair or bond the band to this Mac before expecting custom notify frames.";
    }
    if (fd4bRequested === REQUIRED_FD4B_NOTIFY_CHARACTERISTIC_UUIDS.length && fd4bConfirmed === 0) {
      return " fd4b notifications were requested but not confirmed; native CoreBluetooth reports insufficient authentication/encryption until the band is paired or bonded to this Mac.";
    }
    return undefined;
  }

  private isFd4bCommandReady(): boolean {
    return this.active?.commandCharacteristic !== undefined
      && compactUuid(this.active.commandCharacteristic.uuid) === FD4B_COMMAND_CHARACTERISTIC_UUID;
  }

  private connectedDeviceState(active: ActiveConnection): ConnectedDevice {
    return {
      id: active.device.id,
      name: active.device.name,
      profileId: active.device.profileId,
      profileLabel: active.device.profileLabel,
      commandReady: active.commandCharacteristic !== undefined,
      characteristics: active.characteristics,
    };
  }

  private log(level: LogEntry["level"], source: string, message: string): void {
    this.logs.unshift({
      id: `log-${Date.now()}-${this.logs.length}`,
      at: new Date().toISOString(),
      level,
      source,
      message,
    });
    if (this.logs.length > MAX_LOGS) {
      this.logs.splice(MAX_LOGS);
    }
    this.emitState();
  }

  private emitState(): void {
    this.emit("state", this.getState());
  }
}

function customBandDeviceScore(device: DiscoveredDevice): number {
  const hasFd4bService = device.advertisedServices.includes(FD4B_CUSTOM_BAND_SERVICE_UUID);
  return (hasFd4bService ? 10_000 : 0) + device.rssi;
}

function renderRustVersion(value: unknown): string {
  if (typeof value !== "object" || value === null) {
    return "unknown";
  }
  const version = "core_version" in value ? String((value as { core_version: unknown }).core_version) : "unknown";
  const schema = "storage_schema_version" in value
    ? String((value as { storage_schema_version: unknown }).storage_schema_version)
    : "?";
  return `${version} schema ${schema}`;
}

function characteristicRole(uuid: string): ConnectedCharacteristic["role"] {
  if (COMMAND_CHARACTERISTIC_SET.has(uuid)) {
    return "command";
  }
  if (NOTIFICATION_CHARACTERISTIC_SET.has(uuid)) {
    return "notify";
  }
  if (uuid === STANDARD_HEART_RATE_MEASUREMENT_UUID) {
    return "heart_rate";
  }
  if (uuid === BATTERY_LEVEL_UUID || uuid === BATTERY_LEVEL_STATUS_UUID) {
    return "battery";
  }
  if (DEVICE_INFORMATION_CHARACTERISTIC_UUIDS.has(uuid)) {
    return "device_info";
  }
  return "other";
}

function chooseCommandCharacteristic(
  current: NobleCharacteristic | undefined,
  candidate: NobleCharacteristic,
): NobleCharacteristic {
  if (!current) {
    return candidate;
  }
  const currentUuid = compactUuid(current.uuid);
  const candidateUuid = compactUuid(candidate.uuid);
  if (!currentUuid.startsWith("fd4b0002") && candidateUuid.startsWith("fd4b0002")) {
    return candidate;
  }
  return current;
}

function characteristicServiceUuid(characteristic: NobleCharacteristic, services: NobleService[]): string {
  const raw = characteristic as NobleCharacteristic & { _serviceUuid?: string; serviceUuid?: string };
  if (raw.serviceUuid) {
    return compactUuid(raw.serviceUuid);
  }
  if (raw._serviceUuid) {
    return compactUuid(raw._serviceUuid);
  }
  return compactUuid(services[0]?.uuid ?? "unknown");
}

function writeTypeForCharacteristic(characteristic: NobleCharacteristic): { name: "withResponse" | "withoutResponse"; withoutResponse: boolean } {
  if (characteristic.properties.includes("write")) {
    return { name: "withResponse", withoutResponse: false };
  }
  if (characteristic.properties.includes("writeWithoutResponse")) {
    return { name: "withoutResponse", withoutResponse: true };
  }
  throw new Error("Command characteristic is not writable.");
}

function highFrequencyHistorySyncCommand(intervalSeconds: number, durationSeconds: number): SensorStreamCommand {
  if (!Number.isInteger(intervalSeconds) || intervalSeconds <= 0 || intervalSeconds > 0xffff) {
    throw new Error("intervalSeconds must be a positive UInt16");
  }
  if (!Number.isInteger(durationSeconds) || durationSeconds <= 0 || durationSeconds > 0xffff) {
    throw new Error("durationSeconds must be a positive UInt16");
  }
  return {
    commandNumber: 96,
    payload: [2, ...uint16LE(intervalSeconds), ...uint16LE(durationSeconds)],
    name: "ENTER_HIGH_FREQ_SYNC",
  };
}

function uint16LE(value: number): number[] {
  return [value & 0xff, (value >> 8) & 0xff];
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function startScanning(): Promise<void> {
  return new Promise((resolve, reject) => {
    noble.startScanning([], true, (error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

function stopScanning(): Promise<void> {
  return new Promise((resolve) => {
    noble.stopScanning(() => resolve());
  });
}

function connectPeripheral(peripheral: NoblePeripheral): Promise<void> {
  return new Promise((resolve, reject) => {
    peripheral.connect((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

function disconnectPeripheral(peripheral: NoblePeripheral): Promise<void> {
  return new Promise((resolve, reject) => {
    peripheral.disconnect((error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

function discoverAll(peripheral: NoblePeripheral): Promise<{
  services: NobleService[];
  characteristics: NobleCharacteristic[];
}> {
  return new Promise((resolve, reject) => {
    peripheral.discoverAllServicesAndCharacteristics((error, services, characteristics) => {
      if (error) {
        reject(error);
      } else {
        resolve({ services, characteristics });
      }
    });
  });
}

function subscribeCharacteristic(characteristic: NobleCharacteristic): Promise<boolean> {
  return new Promise((resolve, reject) => {
    let timeout: NodeJS.Timeout;
    let settled = false;
    function cleanup(): void {
      clearTimeout(timeout);
      characteristic.off("notify", finish);
    }
    function finish(state: boolean): void {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve(Boolean(state));
    }
    function fail(error: Error): void {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      reject(error);
    }
    timeout = setTimeout(() => {
      fail(new Error(`notify state timed out for ${displayUuid(compactUuid(characteristic.uuid))}`));
    }, 5_000);
    characteristic.once("notify", finish);
    characteristic.subscribe((error) => {
      if (error) {
        fail(error);
      }
    });
  });
}

function readCharacteristic(characteristic: NobleCharacteristic): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    characteristic.read((error, data) => {
      if (error) {
        reject(error);
      } else if (!data) {
        reject(new Error("read returned no data"));
      } else {
        resolve(data);
      }
    });
  });
}

function writeCharacteristic(
  characteristic: NobleCharacteristic,
  data: Buffer,
  withoutResponse: boolean,
): Promise<void> {
  return new Promise((resolve, reject) => {
    characteristic.write(data, withoutResponse, (error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

interface ProcessCaptureOptions {
  cwd: string;
  timeoutMs?: number;
  onLine(line: string): void;
}

interface ProcessCaptureResult {
  exitCode: number;
}

interface ParsedMacBluetoothBandStatus {
  known: boolean;
  connected: boolean;
  matchedCount: number;
}

function parseMacBluetoothBandStatus(lines: string[]): ParsedMacBluetoothBandStatus {
  let section: "connected" | "not-connected" | undefined;
  let matchedCount = 0;
  let connected = false;
  for (const line of lines) {
    if (/^\s*Connected:\s*$/.test(line)) {
      section = "connected";
      continue;
    }
    if (/^\s*Not Connected:\s*$/.test(line)) {
      section = "not-connected";
      continue;
    }
    const entry = line.match(/^\s{10}(.+):\s*$/);
    if (!entry || !section) {
      continue;
    }
    const name = entry[1] ?? "";
    if (/\bwhoop\b/i.test(name)) {
      matchedCount += 1;
      if (section === "connected") {
        connected = true;
      }
    }
  }
  return {
    known: matchedCount > 0,
    connected,
    matchedCount,
  };
}

function runProcessCapture(
  command: string,
  args: string[],
  options: ProcessCaptureOptions,
): Promise<ProcessCaptureResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let settled = false;
    let stdoutRemainder = "";
    let stderrRemainder = "";
    const timeout = options.timeoutMs
      ? setTimeout(() => {
          if (!settled) {
            settled = true;
            child.kill("SIGTERM");
            reject(new Error(`${command} timed out after ${options.timeoutMs}ms`));
          }
        }, options.timeoutMs)
      : undefined;

    const flushLines = (chunk: Buffer, stream: "stdout" | "stderr"): void => {
      const current = (stream === "stdout" ? stdoutRemainder : stderrRemainder) + chunk.toString("utf8");
      const lines = current.split(/\r?\n/);
      const remainder = lines.pop() ?? "";
      if (stream === "stdout") {
        stdoutRemainder = remainder;
      } else {
        stderrRemainder = remainder;
      }
      for (const line of lines) {
        options.onLine(stream === "stderr" ? `stderr: ${line}` : line);
      }
    };

    child.stdout.on("data", (chunk: Buffer) => flushLines(chunk, "stdout"));
    child.stderr.on("data", (chunk: Buffer) => flushLines(chunk, "stderr"));
    child.on("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timeout) {
        clearTimeout(timeout);
      }
      reject(error);
    });
    child.on("close", (code) => {
      if (settled) {
        return;
      }
      settled = true;
      if (timeout) {
        clearTimeout(timeout);
      }
      if (stdoutRemainder) {
        options.onLine(stdoutRemainder);
      }
      if (stderrRemainder) {
        options.onLine(`stderr: ${stderrRemainder}`);
      }
      resolve({ exitCode: code ?? 0 });
    });
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function optionalField<K extends string, V>(
  key: K,
  value: V | undefined,
): V extends undefined ? Record<string, never> : Partial<Record<K, V>> {
  return (value === undefined ? {} : { [key]: value }) as V extends undefined
    ? Record<string, never>
    : Partial<Record<K, V>>;
}
