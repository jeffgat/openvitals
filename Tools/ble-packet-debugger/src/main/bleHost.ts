import readline from "node:readline";
import { DebuggerController } from "./ble/DebuggerController";
import { RustBridgeClient } from "./bridge/RustBridgeClient";

interface HostRequest {
  id: string;
  command: string;
  payload?: unknown;
}

const repoRoot = process.env.OPENVITALS_REPO_ROOT;
if (!repoRoot) {
  throw new Error("OPENVITALS_REPO_ROOT is required");
}

const databasePath = process.env.OPENVITALS_BLE_DEBUGGER_DB;
if (!databasePath) {
  throw new Error("OPENVITALS_BLE_DEBUGGER_DB is required");
}

const controller = new DebuggerController(new RustBridgeClient(repoRoot), databasePath, repoRoot);
controller.on("state", (state) => {
  write({ event: "state", payload: state });
});

const lines = readline.createInterface({ input: process.stdin });
lines.on("line", (line) => {
  if (line.trim().length === 0) {
    return;
  }
  void handleLine(line);
});
lines.on("close", () => {
  void controller.shutdown().finally(() => process.exit(0));
});
process.stdin.on("end", () => {
  void controller.shutdown().finally(() => process.exit(0));
});

process.on("SIGTERM", () => {
  void controller.shutdown().finally(() => process.exit(0));
});

process.on("SIGINT", () => {
  void controller.shutdown().finally(() => process.exit(0));
});

async function handleLine(line: string): Promise<void> {
  let request: HostRequest;
  try {
    request = JSON.parse(line) as HostRequest;
  } catch (error) {
    write({ ok: false, error: errorMessage(error) });
    return;
  }

  try {
    const result = await dispatch(request.command, request.payload);
    write({ id: request.id, ok: true, result });
  } catch (error) {
    write({ id: request.id, ok: false, error: errorMessage(error) });
  }
}

async function dispatch(command: string, payload: unknown): Promise<unknown> {
  switch (command) {
    case "getState":
      return controller.getState();
    case "startScan":
      return controller.startScan();
    case "stopScan":
      return controller.stopScan();
    case "connect":
      return controller.connect(requiredString(payload, "deviceId"));
    case "disconnect":
      return controller.disconnect();
    case "startCapture":
      return controller.startCapture(optionalObject(payload));
    case "stopCapture":
      return controller.stopCapture();
    case "setDatabasePath":
      return controller.setDatabasePath(requiredString(payload, "databasePath"));
    case "storageCheck":
      return controller.storageCheck();
    case "sendHello":
      return controller.sendHello();
    case "startIosParityPhysiologyProbe":
      return controller.startIosParityPhysiologyProbe(optionalNonNegativeInteger(payload, "delayMs", 5_000));
    case "startBandParityProbe":
      return controller.startBandParityProbe({
        databasePath: optionalString(payload, "databasePath"),
        scanTimeoutMs: optionalNonNegativeInteger(payload, "scanTimeoutMs", 10_000),
        observeSeconds: optionalPositiveInteger(payload, "observeSeconds", 12),
      });
    case "runNativeAuthProbe":
      return controller.runNativeAuthProbe();
    case "checkMacPairingStatus":
      return controller.checkMacPairingStatus();
    case "startPhysiologyCapture":
      return controller.startPhysiologyCapture();
    case "stopPhysiologyCapture":
      return controller.stopPhysiologyCapture();
    case "enterHighFrequencyHistorySync":
      return controller.enterHighFrequencyHistorySync(
        optionalPositiveInteger(payload, "intervalSeconds", 180),
        optionalPositiveInteger(payload, "durationSeconds", 7_200),
      );
    case "exitHighFrequencyHistorySync":
      return controller.exitHighFrequencyHistorySync();
    case "selectPacket":
      return controller.selectPacket(requiredString(payload, "packetId"));
    default:
      throw new Error(`Unsupported host command ${command}`);
  }
}

function write(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function optionalObject(payload: unknown): Record<string, string> {
  if (payload === undefined || payload === null) {
    return {};
  }
  if (typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("payload must be an object");
  }
  return payload as Record<string, string>;
}

function optionalString(payload: unknown, key: string): string | undefined {
  if (payload === undefined || payload === null) {
    return undefined;
  }
  if (typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("payload must be an object");
  }
  const value = (payload as Record<string, unknown>)[key];
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new Error(`${key} must be a string`);
  }
  return value;
}

function requiredString(payload: unknown, key: string): string {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error(`${key} is required`);
  }
  const value = (payload as Record<string, unknown>)[key];
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${key} is required`);
  }
  return value;
}

function optionalPositiveInteger(payload: unknown, key: string, fallback: number): number {
  if (payload === undefined || payload === null) {
    return fallback;
  }
  if (typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("payload must be an object");
  }
  const value = (payload as Record<string, unknown>)[key];
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0 || value > 0xffff) {
    throw new Error(`${key} must be a positive UInt16`);
  }
  return value;
}

function optionalNonNegativeInteger(payload: unknown, key: string, fallback: number): number {
  if (payload === undefined || payload === null) {
    return fallback;
  }
  if (typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("payload must be an object");
  }
  const value = (payload as Record<string, unknown>)[key];
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new Error(`${key} must be a non-negative integer`);
  }
  return value;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
