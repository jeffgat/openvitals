import http, { type IncomingMessage, type ServerResponse } from "node:http";
import fs from "node:fs/promises";
import path from "node:path";
import type { MobileIngestState } from "../../shared/types";
import { RustBridgeClient, type CapturedFrameInput } from "../bridge/RustBridgeClient";

interface ImportBatchResponse {
  raw_inserted?: number;
  raw_existing?: number;
  frames_inserted?: number;
  frames_existing?: number;
  issues?: string[];
}

interface MobileIngestOptions {
  databasePath: string;
  rust: RustBridgeClient;
  log(level: "info" | "warn" | "error", source: string, message: string): void;
  onState(): void;
}

interface MobileCaptureSessionPayload {
  session_id?: unknown;
  source?: unknown;
  started_at_unix_ms?: unknown;
  device_model?: unknown;
  active_device_id?: unknown;
  provenance?: unknown;
}

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 8765;
const MAX_BODY_BYTES = 16 * 1024 * 1024;
const MAX_FRAMES_PER_BATCH = 2_000;
const MAX_FRAME_HEX_CHARS = 256 * 1024;
const FRAME_BATCH_SCHEMA = "open_vitals.mobile-capture-frame-batch.v1";
const SESSION_FINISHED_SCHEMA = "open_vitals.mobile-capture-session-finished.v1";

export class MobileIngestServer {
  private server: http.Server | undefined;
  private databasePath: string;
  private readonly enabled: boolean;
  private readonly bindHost: string;
  private readonly port: number;
  private readonly token: string | undefined;
  private readonly ensuredSessions = new Set<string>();
  private state: MobileIngestState;

  constructor(private readonly options: MobileIngestOptions) {
    this.databasePath = options.databasePath;
    this.enabled = process.env.OPENVITALS_MOBILE_INGEST !== "0";
    this.bindHost = process.env.OPENVITALS_MOBILE_INGEST_HOST?.trim() || DEFAULT_HOST;
    this.port = parsePort(process.env.OPENVITALS_MOBILE_INGEST_PORT, DEFAULT_PORT);
    const token = process.env.OPENVITALS_MOBILE_INGEST_TOKEN?.trim();
    this.token = token && token.length > 0 ? token : undefined;
    this.state = {
      enabled: this.enabled,
      listening: false,
      bindHost: this.bindHost,
      port: this.port,
      url: this.renderIngestUrl(),
      tokenRequired: this.tokenRequired(),
      receivedBatches: 0,
      receivedFrames: 0,
      importedFrames: 0,
      existingFrames: 0,
      rawInserted: 0,
      rawExisting: 0,
      pendingBatches: 0,
      lastImportStatus: this.enabled ? "not listening" : "disabled",
    };
  }

  getState(): MobileIngestState {
    return { ...this.state };
  }

  setDatabasePath(databasePath: string): void {
    this.databasePath = databasePath;
    this.ensuredSessions.clear();
    this.state = {
      ...this.state,
      lastImportStatus: this.state.listening ? "database path updated" : this.state.lastImportStatus,
    };
    this.options.onState();
  }

  start(): void {
    if (!this.enabled || this.server) {
      return;
    }
    if (this.tokenRequired() && !this.token) {
      const message = "Set OPENVITALS_MOBILE_INGEST_TOKEN before binding mobile ingest outside loopback.";
      this.state = {
        ...this.state,
        listening: false,
        lastImportStatus: "token required before listening",
        lastError: message,
      };
      this.options.log("warn", "mobile-ingest", message);
      this.options.onState();
      return;
    }

    this.server = http.createServer((request, response) => {
      void this.handleRequest(request, response);
    });
    this.server.on("error", (error) => {
      const message = errorMessage(error);
      this.state = {
        ...this.state,
        listening: false,
        lastImportStatus: "listen failed",
        lastError: message,
      };
      this.options.log("error", "mobile-ingest", message);
      this.options.onState();
    });
    this.server.listen(this.port, this.bindHost, () => {
      this.state = {
        ...this.state,
        listening: true,
        lastImportStatus: "listening",
        lastError: undefined,
      };
      this.options.log("info", "mobile-ingest", `listening ${this.renderIngestUrl()}`);
      this.options.onState();
    });
  }

  async stop(): Promise<void> {
    const server = this.server;
    if (!server) {
      return;
    }
    await new Promise<void>((resolve) => {
      server.close(() => resolve());
    });
    this.server = undefined;
    this.state = {
      ...this.state,
      listening: false,
      lastImportStatus: this.enabled ? "stopped" : "disabled",
    };
    this.options.onState();
  }

  private async handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
    const pathname = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`).pathname;
    if (request.method === "GET" && pathname === "/health") {
      writeJson(response, 200, { ok: true, mobile_ingest: this.getState() });
      return;
    }
    if (request.method !== "POST") {
      writeJson(response, 405, { ok: false, error: "method_not_allowed" });
      return;
    }
    if (!this.authorized(request)) {
      writeJson(response, 401, { ok: false, error: "unauthorized" });
      return;
    }

    try {
      const body = await readJsonBody(request);
      if (pathname === "/v1/mobile/frame-batch") {
        const result = await this.importFrameBatch(body);
        writeJson(response, 200, { ok: true, ...result });
        return;
      }
      if (pathname === "/v1/mobile/capture-session-finished") {
        const result = await this.finishCaptureSession(body);
        writeJson(response, 200, { ok: true, ...result });
        return;
      }
      writeJson(response, 404, { ok: false, error: "not_found" });
    } catch (error) {
      const message = errorMessage(error);
      this.state = {
        ...this.state,
        lastImportStatus: "request failed",
        lastError: message,
      };
      this.options.log("error", "mobile-ingest", message);
      this.options.onState();
      writeJson(response, 400, { ok: false, error: message });
    }
  }

  private async importFrameBatch(body: unknown): Promise<Record<string, unknown>> {
    const object = requireObject(body, "body");
    const schema = optionalString(object.schema);
    if (schema && schema !== FRAME_BATCH_SCHEMA) {
      throw new Error(`unsupported schema ${schema}`);
    }
    const frames = requireArray(object.frames, "frames").map(sanitizeFrame);
    if (frames.length === 0) {
      throw new Error("frames must not be empty");
    }
    if (frames.length > MAX_FRAMES_PER_BATCH) {
      throw new Error(`frames exceeds ${MAX_FRAMES_PER_BATCH}`);
    }
    const session = sanitizeCaptureSession(object.capture_session) ?? synthesizeCaptureSession(frames);
    if (session) {
      for (const frame of frames) {
        frame.capture_session_id = frame.capture_session_id ?? session.sessionId;
      }
    }
    this.state = {
      ...this.state,
      pendingBatches: this.state.pendingBatches + 1,
      receivedBatches: this.state.receivedBatches + 1,
      receivedFrames: this.state.receivedFrames + frames.length,
      lastReceivedAt: new Date().toISOString(),
      activeSessionId: session?.sessionId ?? frames[0]?.capture_session_id,
      lastImportStatus: `importing ${frames.length} mobile frames`,
      lastError: undefined,
    };
    this.options.onState();

    try {
      await fs.mkdir(path.dirname(this.databasePath), { recursive: true });
      const sessions = sessionsForFrames(session, frames);
      for (const frameSession of sessions) {
        await this.ensureCaptureSession(frameSession);
      }
      const report = await this.importFrameBatchWithMissingSessionRetry(frames) as ImportBatchResponse;
      const inserted = report.frames_inserted ?? 0;
      const existing = report.frames_existing ?? 0;
      this.state = {
        ...this.state,
        pendingBatches: Math.max(0, this.state.pendingBatches - 1),
        importedFrames: this.state.importedFrames + inserted,
        existingFrames: this.state.existingFrames + existing,
        rawInserted: this.state.rawInserted + (report.raw_inserted ?? 0),
        rawExisting: this.state.rawExisting + (report.raw_existing ?? 0),
        lastImportStatus: report.issues?.length
          ? `${report.issues.length} mobile import issues`
          : `imported ${inserted}, existing ${existing}`,
        lastError: report.issues?.slice(0, 3).join(" | "),
      };
      this.options.onState();
      return {
        schema: "open_vitals.mobile-ingest-result.v1",
        frame_count: frames.length,
        raw_inserted: report.raw_inserted ?? 0,
        raw_existing: report.raw_existing ?? 0,
        frames_inserted: inserted,
        frames_existing: existing,
        issues: report.issues ?? [],
      };
    } catch (error) {
      this.state = {
        ...this.state,
        pendingBatches: Math.max(0, this.state.pendingBatches - 1),
        lastImportStatus: "mobile import failed",
        lastError: errorMessage(error),
      };
      this.options.onState();
      throw error;
    }
  }

  private async importFrameBatchWithMissingSessionRetry(frames: CapturedFrameInput[]): Promise<unknown> {
    try {
      return await this.options.rust.importFrameBatch(this.databasePath, frames);
    } catch (error) {
      const missingSessionId = missingCaptureSessionId(error);
      if (!missingSessionId || frames.length === 0) {
        throw error;
      }
      const frame = frames.find((candidate) => candidate.capture_session_id === missingSessionId) ?? frames[0];
      if (!frame) {
        throw error;
      }
      await this.ensureCaptureSession(synthesizedSessionFromFrame(missingSessionId, frame), { force: true });
      return await this.options.rust.importFrameBatch(this.databasePath, frames);
    }
  }

  private async finishCaptureSession(body: unknown): Promise<Record<string, unknown>> {
    const object = requireObject(body, "body");
    const schema = optionalString(object.schema);
    if (schema && schema !== SESSION_FINISHED_SCHEMA) {
      throw new Error(`unsupported schema ${schema}`);
    }
    const sessionId = requireString(object.session_id, "session_id");
    const endedAtUnixMs = requireFiniteInteger(object.ended_at_unix_ms, "ended_at_unix_ms");
    const frameCount = requireFiniteInteger(object.frame_count, "frame_count");
    const report = await this.options.rust.finishCaptureSession({
      databasePath: this.databasePath,
      sessionId,
      endedAtUnixMs,
      frameCount,
    });
    this.state = {
      ...this.state,
      activeSessionId: sessionId,
      lastImportStatus: `finished mobile session ${sessionId}`,
      lastError: undefined,
    };
    this.options.log("info", "mobile-ingest", `finished mobile session ${sessionId} frames=${frameCount}`);
    this.options.onState();
    return {
      schema: "open_vitals.mobile-ingest-session-finished-result.v1",
      session_id: sessionId,
      report,
    };
  }

  private async ensureCaptureSession(
    session: SanitizedCaptureSession,
    options: { force?: boolean } = {},
  ): Promise<void> {
    if (!options.force && this.ensuredSessions.has(session.sessionId)) {
      return;
    }
    await fs.mkdir(path.dirname(this.databasePath), { recursive: true });
    await this.options.rust.startCaptureSession({
      databasePath: this.databasePath,
      sessionId: session.sessionId,
      source: session.source,
      startedAtUnixMs: session.startedAtUnixMs,
      deviceModel: session.deviceModel,
      ...(session.activeDeviceId ? { activeDeviceId: session.activeDeviceId } : {}),
      provenance: session.provenance,
    });
    this.ensuredSessions.add(session.sessionId);
  }

  private authorized(request: IncomingMessage): boolean {
    if (!this.token) {
      return true;
    }
    const header = request.headers["x-openvitals-ingest-token"];
    if (typeof header === "string" && header === this.token) {
      return true;
    }
    const authorization = request.headers.authorization;
    return authorization === `Bearer ${this.token}`;
  }

  private tokenRequired(): boolean {
    return !isLoopbackHost(this.bindHost) || this.token !== undefined;
  }

  private renderIngestUrl(): string {
    return `http://${this.bindHost}:${this.port}/v1/mobile/frame-batch`;
  }
}

interface SanitizedCaptureSession {
  sessionId: string;
  source: string;
  startedAtUnixMs: number;
  deviceModel: string;
  activeDeviceId?: string;
  provenance: Record<string, unknown>;
}

function sanitizeCaptureSession(value: unknown): SanitizedCaptureSession | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  const object = requireObject(value, "capture_session") as MobileCaptureSessionPayload;
  const activeDeviceId = optionalString(object.active_device_id);
  return {
    sessionId: requireString(object.session_id, "capture_session.session_id"),
    source: optionalString(object.source) ?? "ios.health_packet_capture",
    startedAtUnixMs: requireFiniteInteger(object.started_at_unix_ms, "capture_session.started_at_unix_ms"),
    deviceModel: optionalString(object.device_model) ?? "iOS OpenVitals",
    ...(activeDeviceId ? { activeDeviceId } : {}),
    provenance: sanitizeProvenance(object.provenance),
  };
}

function synthesizeCaptureSession(frames: CapturedFrameInput[]): SanitizedCaptureSession | undefined {
  const firstFrameWithSession = frames.find((frame) => frame.capture_session_id);
  if (!firstFrameWithSession?.capture_session_id) {
    return undefined;
  }
  return synthesizedSessionFromFrame(firstFrameWithSession.capture_session_id, firstFrameWithSession);
}

function sessionsForFrames(
  session: SanitizedCaptureSession | undefined,
  frames: CapturedFrameInput[],
): SanitizedCaptureSession[] {
  const sessions = new Map<string, SanitizedCaptureSession>();
  if (session) {
    sessions.set(session.sessionId, session);
  }
  for (const frame of frames) {
    const sessionId = frame.capture_session_id;
    if (!sessionId || sessions.has(sessionId)) {
      continue;
    }
    sessions.set(sessionId, synthesizedSessionFromFrame(sessionId, frame));
  }
  return [...sessions.values()];
}

function synthesizedSessionFromFrame(sessionId: string, frame: CapturedFrameInput): SanitizedCaptureSession {
  return {
    sessionId,
    source: sourceForSessionId(sessionId),
    startedAtUnixMs: unixMsFromIsoString(frame.captured_at),
    deviceModel: frame.device_model,
    provenance: {
      transport: "ios_to_mac_mobile_ingest",
      synthesized_from_frame_batch: true,
    },
  };
}

function sourceForSessionId(sessionId: string): string {
  if (sessionId.startsWith("ios.overnight_guard.")) {
    return "ios.overnight_guard";
  }
  if (sessionId.startsWith("ios.health-packet-capture.")) {
    return "ios.health_packet_capture";
  }
  return "ios.mobile_capture";
}

function unixMsFromIsoString(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : Date.now();
}

function sanitizeFrame(value: unknown): CapturedFrameInput {
  const object = requireObject(value, "frame");
  const frameHex = requireHexString(object.frame_hex, "frame.frame_hex");
  if (frameHex.length > MAX_FRAME_HEX_CHARS) {
    throw new Error("frame.frame_hex exceeds maximum size");
  }
  const frameId = optionalAnyString(object, ["frame_id", "frameId", "frameID"]);
  const captureSessionId = optionalAnyString(object, ["capture_session_id", "captureSessionId", "captureSessionID"]);
  const deviceType = optionalString(object.device_type) === "GEN4" ? "GEN4" : "OPENVITALS";
  const frame: CapturedFrameInput = {
    evidence_id: requireString(object.evidence_id, "frame.evidence_id"),
    source: optionalString(object.source) ?? "ios.corebluetooth.notification",
    captured_at: requireString(object.captured_at, "frame.captured_at"),
    device_model: optionalString(object.device_model) ?? "iOS OpenVitals",
    frame_hex: frameHex,
    sensitivity: optionalString(object.sensitivity) ?? "sensitive",
    device_type: deviceType,
  };
  if (frameId) {
    frame.frame_id = frameId;
  }
  if (captureSessionId) {
    frame.capture_session_id = captureSessionId;
  }
  return frame;
}

function sanitizeProvenance(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null) {
    return {};
  }
  const object = requireObject(value, "capture_session.provenance");
  return { ...object };
}

function requireObject(value: unknown, name: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
  return value as Record<string, unknown>;
}

function requireArray(value: unknown, name: string): unknown[] {
  if (!Array.isArray(value)) {
    throw new Error(`${name} must be an array`);
  }
  return value;
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function optionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function optionalAnyString(object: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = optionalString(object[key]);
    if (value) {
      return value;
    }
  }
  return undefined;
}

function requireHexString(value: unknown, name: string): string {
  const text = requireString(value, name).trim().toLowerCase();
  if (text.length % 2 !== 0 || /[^0-9a-f]/.test(text)) {
    throw new Error(`${name} must be lowercase/uppercase hex bytes`);
  }
  return text;
}

function requireFiniteInteger(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || !Number.isInteger(value) || value < 0) {
    throw new Error(`${name} must be a non-negative integer`);
  }
  return value;
}

function parsePort(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 && parsed <= 65535 ? parsed : fallback;
}

function isLoopbackHost(host: string): boolean {
  return host === "127.0.0.1" || host === "::1" || host === "localhost";
}

function readJsonBody(request: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    request.on("data", (chunk: Buffer) => {
      total += chunk.byteLength;
      if (total > MAX_BODY_BYTES) {
        reject(new Error("request body too large"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

function writeJson(response: ServerResponse, statusCode: number, value: unknown): void {
  const data = JSON.stringify(value);
  response.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(data),
  });
  response.end(data);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function missingCaptureSessionId(error: unknown): string | undefined {
  const match = errorMessage(error).match(/capture session ([^\s]+) not found/);
  return match?.[1];
}
