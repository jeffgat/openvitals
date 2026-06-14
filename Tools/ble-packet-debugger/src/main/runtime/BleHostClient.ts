import { EventEmitter } from "node:events";
import path from "node:path";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import readline from "node:readline";
import type { DebuggerAppState } from "../../shared/types";

interface BleHostClientOptions {
  hostPath: string;
  repoRoot: string;
  databasePath: string;
}

interface HostEnvelope {
  id?: string;
  ok?: boolean;
  result?: unknown;
  error?: string;
  event?: string;
  payload?: unknown;
}

interface PendingRequest {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timer: NodeJS.Timeout;
}

export class BleHostClient extends EventEmitter {
  private child: ChildProcessWithoutNullStreams | undefined;
  private readonly pending = new Map<string, PendingRequest>();
  private counter = 0;

  constructor(private readonly options: BleHostClientOptions) {
    super();
  }

  start(): void {
    if (this.child) {
      return;
    }

    const nodeBinary = process.env.OPENVITALS_NODE_BIN ?? "node";
    const child = spawn(nodeBinary, [this.options.hostPath], {
      cwd: path.resolve(this.options.repoRoot, "Tools/ble-packet-debugger"),
      env: {
        ...process.env,
        OPENVITALS_REPO_ROOT: this.options.repoRoot,
        OPENVITALS_BLE_DEBUGGER_DB: this.options.databasePath,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;

    const lines = readline.createInterface({ input: child.stdout });
    lines.on("line", (line) => this.handleLine(line));

    child.stderr.on("data", (chunk: Buffer) => {
      const message = chunk.toString("utf8").trim();
      if (message.length > 0) {
        console.warn(`[ble-host] ${message}`);
      }
    });

    child.on("exit", (code, signal) => {
      this.child = undefined;
      const error = new Error(`BLE host exited code=${code ?? "null"} signal=${signal ?? "null"}`);
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

  request<T = DebuggerAppState>(command: string, payload: unknown = {}, timeoutMs = 30_000): Promise<T> {
    this.start();
    const child = this.child;
    if (!child) {
      return Promise.reject(new Error("BLE host is unavailable"));
    }

    const id = `ui-${Date.now()}-${++this.counter}`;
    const envelope = JSON.stringify({ id, command, payload });
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${command} timed out`));
      }, timeoutMs);
      this.pending.set(id, {
        resolve: (value) => resolve(value as T),
        reject,
        timer,
      });
      child.stdin.write(`${envelope}\n`, "utf8");
    });
  }

  private handleLine(line: string): void {
    if (line.trim().length === 0) {
      return;
    }
    let envelope: HostEnvelope;
    try {
      envelope = JSON.parse(line) as HostEnvelope;
    } catch {
      console.warn(`[ble-host] invalid json: ${line}`);
      return;
    }

    if (envelope.event === "state") {
      this.emit("state", envelope.payload);
      return;
    }

    if (!envelope.id) {
      return;
    }
    const pending = this.pending.get(envelope.id);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timer);
    this.pending.delete(envelope.id);
    if (envelope.ok) {
      pending.resolve(envelope.result);
    } else {
      pending.reject(new Error(envelope.error ?? "BLE host request failed"));
    }
  }
}
