import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { EventEmitter } from "node:events";
import readline from "node:readline";
import path from "node:path";

interface BridgeEnvelope {
  schema: string;
  request_id: string;
  ok: boolean;
  result?: unknown;
  error?: { code: string; message: string };
}

interface PendingBridgeRequest {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timer: NodeJS.Timeout;
}

export interface CapturedFrameInput {
  evidence_id: string;
  frame_id?: string;
  source: string;
  captured_at: string;
  device_model: string;
  frame_hex: string;
  sensitivity: string;
  capture_session_id?: string;
  device_type: "OPENVITALS" | "GEN4";
}

export interface RrReferenceSampleInput {
  sample_id: string;
  session_id: string;
  captured_at: string;
  device_name: string;
  device_id: string;
  heart_rate_bpm?: number;
  rr_interval_ms: number;
  notification_sequence: number;
  rr_index: number;
  contact_detected?: boolean;
  energy_expended_j?: number;
  provenance: Record<string, unknown>;
}

export class RustBridgeClient extends EventEmitter {
  private child: ChildProcessWithoutNullStreams | undefined;
  private readonly pending = new Map<string, PendingBridgeRequest>();
  private counter = 0;
  private versionCache?: unknown;

  constructor(private readonly repoRoot: string) {
    super();
  }

  get bridgePath(): string {
    return process.env.OPENVITALS_BRIDGE_BIN
      ?? `cargo run --manifest-path ${path.join(this.repoRoot, "Rust/core/Cargo.toml")} --quiet --bin open-vitals-bridge -- --stdio`;
  }

  start(): void {
    if (this.child) {
      return;
    }

    const bridgeBin = process.env.OPENVITALS_BRIDGE_BIN;
    const command = bridgeBin ?? "cargo";
    const args = bridgeBin
      ? ["--stdio"]
      : [
          "run",
          "--manifest-path",
          path.join(this.repoRoot, "Rust/core/Cargo.toml"),
          "--quiet",
          "--bin",
          "open-vitals-bridge",
          "--",
          "--stdio",
        ];

    const child = spawn(command, args, {
      cwd: this.repoRoot,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;

    const lines = readline.createInterface({ input: child.stdout });
    lines.on("line", (line) => this.handleLine(line));

    child.stderr.on("data", (chunk: Buffer) => {
      const text = chunk.toString("utf8").trim();
      if (text.length > 0) {
        this.emit("stderr", text);
      }
    });

    child.on("exit", (code, signal) => {
      this.child = undefined;
      const error = new Error(`Rust bridge exited code=${code ?? "null"} signal=${signal ?? "null"}`);
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(error);
      }
      this.pending.clear();
      this.emit("exit", error);
    });
  }

  stop(): void {
    this.child?.kill();
    this.child = undefined;
  }

  async version(): Promise<unknown> {
    if (this.versionCache !== undefined) {
      return this.versionCache;
    }
    this.versionCache = await this.request("core.version");
    return this.versionCache;
  }

  buildV5CommandFrame(sequence: number, command: number, dataHex: string): Promise<{ frame_hex: string }> {
    return this.request("protocol.build_v5_command_frame", {
      sequence,
      command,
      data_hex: dataHex,
    });
  }

  parseFrameBatch(frames: string[], deviceType: "OPENVITALS" | "GEN4"): Promise<unknown> {
    return this.request("protocol.parse_frame_hex_batch", {
      frames,
      device_type: deviceType,
    });
  }

  startCaptureSession(args: {
    databasePath: string;
    sessionId: string;
    source: string;
    startedAtUnixMs: number;
    deviceModel: string;
    activeDeviceId?: string;
    provenance: Record<string, unknown>;
  }): Promise<unknown> {
    return this.request("capture.start_session", {
      database_path: args.databasePath,
      session_id: args.sessionId,
      source: args.source,
      started_at_unix_ms: args.startedAtUnixMs,
      device_model: args.deviceModel,
      active_device_id: args.activeDeviceId,
      provenance: args.provenance,
    });
  }

  importFrameBatch(
    databasePath: string,
    frames: CapturedFrameInput[],
  ): Promise<unknown> {
    return this.request("capture.import_frame_batch", {
      database_path: databasePath,
      parser_version: "open-vitals-core/desktop-ble-debugger",
      include_timeline_rows: false,
      compact_raw_payloads: false,
      include_results: true,
      frames,
    }, 120_000);
  }

  finishCaptureSession(args: {
    databasePath: string;
    sessionId: string;
    endedAtUnixMs: number;
    frameCount: number;
  }): Promise<unknown> {
    return this.request("capture.finish_session", {
      database_path: args.databasePath,
      session_id: args.sessionId,
      ended_at_unix_ms: args.endedAtUnixMs,
      frame_count: args.frameCount,
    });
  }

  insertRrReferenceSamples(
    databasePath: string,
    samples: RrReferenceSampleInput[],
  ): Promise<unknown> {
    return this.request("reference_rr.insert_samples", {
      database_path: databasePath,
      samples,
    }, 120_000);
  }

  rrReferenceSummary(args: {
    databasePath: string;
    sessionId?: string;
    start?: string;
    end?: string;
  }): Promise<unknown> {
    return this.request("reference_rr.summary", {
      database_path: args.databasePath,
      ...(args.sessionId ? { session_id: args.sessionId } : {}),
      ...(args.start ? { start: args.start } : {}),
      ...(args.end ? { end: args.end } : {}),
    }, 120_000);
  }

  storageCheck(databasePath: string): Promise<unknown> {
    return this.request("storage.check", {
      database_path: databasePath,
      self_test: true,
    }, 120_000);
  }

  request<T = unknown>(method: string, args: unknown = {}, timeoutMs = 30_000): Promise<T> {
    this.start();
    const child = this.child;
    if (!child) {
      return Promise.reject(new Error("Rust bridge is unavailable"));
    }

    const requestId = `desktop-${Date.now()}-${++this.counter}`;
    const request = {
      schema: "open_vitals.bridge.request.v1",
      request_id: requestId,
      method,
      args,
    };

    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(requestId);
        reject(new Error(`${method} timed out`));
      }, timeoutMs);
      this.pending.set(requestId, {
        resolve: (value) => resolve(value as T),
        reject,
        timer,
      });
      child.stdin.write(`${JSON.stringify(request)}\n`, "utf8");
    });
  }

  private handleLine(line: string): void {
    if (line.trim().length === 0) {
      return;
    }
    let response: BridgeEnvelope;
    try {
      response = JSON.parse(line) as BridgeEnvelope;
    } catch {
      this.emit("stderr", `invalid bridge json: ${line}`);
      return;
    }
    const pending = this.pending.get(response.request_id);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timer);
    this.pending.delete(response.request_id);
    if (response.ok) {
      pending.resolve(response.result);
    } else {
      pending.reject(new Error(response.error?.message ?? "Rust bridge request failed"));
    }
  }
}
