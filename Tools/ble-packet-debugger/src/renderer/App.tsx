import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  AlertTriangle,
  Bluetooth,
  CheckCircle2,
  Database,
  Plug,
  RadioTower,
  RefreshCw,
  Send,
  Square,
  Unplug,
} from "lucide-react";
import type {
  DebuggerAppState,
  DiscoveredDevice,
  PacketRecord,
  StartBandParityProbeOptions,
  StartCaptureOptions,
  StorageCheckResult,
} from "../shared/types";

type DeviceFilterMode = "supported" | "near" | "all";

const DEVICE_FILTER_OPTIONS: Array<{ mode: DeviceFilterMode; label: string }> = [
  { mode: "supported", label: "Supported" },
  { mode: "near", label: "Near" },
  { mode: "all", label: "All" },
];
const NEARBY_RSSI_FLOOR = -70;

const initialState: DebuggerAppState = {
  bluetoothState: "loading",
  connectionState: "idle",
  scanning: false,
  devices: [],
  capture: {
    active: false,
    databasePath: "",
    frameCount: 0,
    rawInserted: 0,
    rawExisting: 0,
    framesInserted: 0,
    framesExisting: 0,
    pendingFrames: 0,
    flushing: false,
    lastImportStatus: "loading",
  },
  packets: [],
  logs: [],
  rust: {
    ready: false,
  },
  diagnostics: {
    fd4bCommandReady: false,
    helloSent: false,
    helloResponseReceived: false,
    commandWritesAccepted: 0,
    commandResponsesReceived: 0,
    customNotifyPacketsReceived: 0,
    fd4bNotifyPacketsReceived: 0,
    notifyRetryAttempts: 0,
    notifyRetryConfirmed: 0,
    notifyRetryErrors: 0,
    requestedCustomNotifyUuids: [],
    subscribedCustomNotifyUuids: [],
    notifySubscriptionErrors: [],
    requiredFd4bNotify: [
      { characteristicUuid: "fd4b0003-cce1-4033-93ce-002d5875f58a", requested: false, subscribed: false },
      { characteristicUuid: "fd4b0004-cce1-4033-93ce-002d5875f58a", requested: false, subscribed: false },
      { characteristicUuid: "fd4b0005-cce1-4033-93ce-002d5875f58a", requested: false, subscribed: false },
      { characteristicUuid: "fd4b0007-cce1-4033-93ce-002d5875f58a", requested: false, subscribed: false },
    ],
    nativeAuthProbe: {
      active: false,
      stage: "idle",
      output: [],
      authErrors: [],
    },
    macPairingStatus: {
      active: false,
      stage: "idle",
      matchedCount: 0,
    },
    bandParityProbe: {
      active: false,
      stage: "idle",
    },
  },
};

export function App(): JSX.Element {
  const [state, setState] = useState<DebuggerAppState>(initialState);
  const [busy, setBusy] = useState<string | undefined>();
  const [databaseDraft, setDatabaseDraft] = useState("");
  const [lastStorageReport, setLastStorageReport] = useState<string>("");
  const [deviceFilter, setDeviceFilter] = useState<DeviceFilterMode>("supported");
  const api = useMemo(() => window.openVitalsDebugger ?? createBrowserFallbackApi(), []);

  useEffect(() => {
    let mounted = true;
    void api.getState().then((next) => {
      if (mounted) {
        setState(next);
        setDatabaseDraft(next.capture.databasePath);
      }
    });
    const unsubscribe = api.onStateChanged((next) => {
      setState(next);
      setDatabaseDraft((current) => current || next.capture.databasePath);
    });
    return () => {
      mounted = false;
      unsubscribe();
    };
  }, [api]);

  const selectedPacket = useMemo(() => {
    return state.packets.find((packet) => packet.id === state.selectedPacketId) ?? state.packets[0];
  }, [state.packets, state.selectedPacketId]);
  const visibleDevices = useMemo(() => {
    return state.devices.filter((device) => deviceMatchesFilter(device, deviceFilter));
  }, [state.devices, deviceFilter]);
  const deviceCountLabel = visibleDevices.length === state.devices.length
    ? String(state.devices.length)
    : `${visibleDevices.length}/${state.devices.length}`;

  async function run(label: string, action: () => Promise<DebuggerAppState | unknown>): Promise<void> {
    setBusy(label);
    try {
      const result = await action();
      if (result && typeof result === "object" && "packets" in result) {
        setState(result as DebuggerAppState);
      }
    } catch (error) {
      setLastStorageReport(error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(undefined);
    }
  }

  return (
    <main className="app-shell">
      <aside className="sidebar">
        <div className="brand-row">
          <div className="brand-mark"><Bluetooth size={18} /></div>
          <div>
            <h1>BLE Packet Debugger</h1>
            <p>{state.bluetoothState}</p>
          </div>
        </div>

        <div className="button-row">
          <button
            className="primary"
            disabled={busy !== undefined || state.scanning}
            title="Start scanning"
            onClick={() => run("scan", () => api.startScan())}
          >
            <RadioTower size={16} /> Scan
          </button>
          <button
            disabled={busy !== undefined || !state.scanning}
            title="Stop scanning"
            onClick={() => run("stop-scan", () => api.stopScan())}
          >
            <Square size={16} /> Stop
          </button>
        </div>

        <section className="panel device-list">
          <div className="panel-heading">
            <span>Devices</span>
            <small>{deviceCountLabel}</small>
          </div>
          <DeviceFilterControl value={deviceFilter} onChange={setDeviceFilter} />
          {state.devices.length === 0 ? (
            <div className="empty">No devices seen yet.</div>
          ) : visibleDevices.length === 0 ? (
            <div className="empty">No devices match this filter.</div>
          ) : (
            visibleDevices.map((device) => (
              <DeviceRow
                key={device.id}
                device={device}
                active={state.connectedDevice?.id === device.id}
                disabled={busy !== undefined}
                onConnect={() => run("connect", () => api.connect(device.id))}
              />
            ))
          )}
        </section>

        <section className="panel">
          <div className="panel-heading">
            <span>Database</span>
            <Database size={15} />
          </div>
          <input
            value={databaseDraft}
            disabled={state.capture.active}
            onChange={(event) => setDatabaseDraft(event.target.value)}
            spellCheck={false}
          />
          <div className="button-row">
            <button
              disabled={busy !== undefined || state.capture.active || databaseDraft === state.capture.databasePath}
              onClick={() => run("set-db", () => api.setDatabasePath(databaseDraft))}
            >
              <Database size={16} /> Set
            </button>
            <button
              disabled={busy !== undefined}
              onClick={() => run("storage", async () => {
                const report = await api.storageCheck();
                setLastStorageReport(JSON.stringify(report.report, null, 2));
                return api.getState();
              })}
            >
              <RefreshCw size={16} /> Check
            </button>
          </div>
          {lastStorageReport ? <pre className="mini-report">{lastStorageReport}</pre> : null}
        </section>
      </aside>

      <section className="workspace">
        <header className="toolbar">
          <StatusPill label={state.connectionState} tone={state.connectionState === "ready" ? "good" : "neutral"} />
          <StatusPill label={state.rust.ready ? `Rust ${state.rust.version ?? "ready"}` : state.rust.lastError ?? "Rust starting"} tone={state.rust.ready ? "good" : "warn"} />
          <div className="toolbar-spacer" />
          <button
            disabled={busy !== undefined || !state.connectedDevice}
            onClick={() => run("disconnect", () => api.disconnect())}
          >
            <Unplug size={16} /> Disconnect
          </button>
          <button
            disabled={busy !== undefined || !state.connectedDevice?.commandReady}
            onClick={() => run("hello", () => api.sendHello())}
          >
            <Send size={16} /> Hello
          </button>
          <button
            disabled={busy !== undefined || !state.connectedDevice?.commandReady}
            title="Run the iOS-parity physiology command sequence after the ready/hello delay"
            onClick={() => run("ios-probe", () => api.startIosParityPhysiologyProbe())}
          >
            <Activity size={16} /> iOS Probe
          </button>
          <button
            className={state.capture.active ? "danger" : "primary"}
            disabled={busy !== undefined}
            onClick={() => run("capture", () => state.capture.active
              ? api.stopCapture()
              : api.startCapture({ databasePath: databaseDraft || state.capture.databasePath }))}
          >
            {state.capture.active ? <Square size={16} /> : <Activity size={16} />}
            {state.capture.active ? "Stop Capture" : "Start Capture"}
          </button>
        </header>

        <section className="probe-strip">
          <div className="probe-actions">
            <button
              className="primary"
              disabled={busy !== undefined || !state.rust.ready}
              title="Run a fresh desktop band parity probe"
              onClick={() => run("band-parity", () => api.startBandParityProbe({
                databasePath: databaseDraft || state.capture.databasePath,
              }))}
            >
              <Activity size={16} /> Start Band Parity Probe
            </button>
            <button
              disabled={busy !== undefined}
              title="Run the native CoreBluetooth authentication/encryption probe"
              onClick={() => run("native-auth", () => api.runNativeAuthProbe())}
            >
              <AlertTriangle size={16} /> Native Auth Probe
            </button>
            <button
              disabled={busy !== undefined}
              title="Check whether macOS Bluetooth already lists the compatible band"
              onClick={() => run("pairing-check", () => api.checkMacPairingStatus())}
            >
              <CheckCircle2 size={16} /> Check Pairing
            </button>
            <button
              disabled={busy !== undefined}
              title="Open macOS Bluetooth Settings"
              onClick={() => run("bluetooth-settings", () => api.openBluetoothSettings())}
            >
              <Bluetooth size={16} /> Bluetooth Settings
            </button>
            <button
              disabled={busy !== undefined || !state.connectedDevice?.commandReady}
              onClick={() => run("start-physiology", () => api.startPhysiologyCapture())}
            >
              <Activity size={16} /> Start Physiology
            </button>
            <button
              disabled={busy !== undefined || !state.connectedDevice?.commandReady}
              onClick={() => run("stop-physiology", () => api.stopPhysiologyCapture())}
            >
              <Square size={16} /> Stop Physiology
            </button>
            <button
              disabled={busy !== undefined || !state.connectedDevice?.commandReady}
              title="Enter High-Frequency History Sync"
              onClick={() => run("enter-history", () => api.enterHighFrequencyHistorySync())}
            >
              <RefreshCw size={16} /> Enter HF Sync
            </button>
            <button
              disabled={busy !== undefined || !state.connectedDevice?.commandReady}
              title="Exit High-Frequency History Sync"
              onClick={() => run("exit-history", () => api.exitHighFrequencyHistorySync())}
            >
              <RefreshCw size={16} /> Exit HF Sync
            </button>
          </div>
          <div className="diagnostic-grid">
            <Diagnostic
              label="Band Probe"
              value={state.diagnostics.bandParityProbe.stage}
              tone={probeTone(state.diagnostics.bandParityProbe)}
            />
            <Diagnostic
              label="Auth Probe"
              value={state.diagnostics.nativeAuthProbe.stage}
              tone={nativeAuthTone(state.diagnostics.nativeAuthProbe)}
            />
            <Diagnostic
              label="Pairing"
              value={pairingStatusValue(state.diagnostics)}
              tone={pairingStatusTone(state.diagnostics)}
            />
            <Diagnostic
              label="fd4b0002"
              value={state.diagnostics.fd4bCommandReady ? "ready" : "missing"}
              tone={state.diagnostics.fd4bCommandReady ? "good" : "warn"}
            />
            <Diagnostic
              label="fd4b Req"
              value={`${state.diagnostics.requiredFd4bNotify.filter((item) => item.requested).length}/4`}
              tone={state.diagnostics.requiredFd4bNotify.every((item) => item.requested) ? "good" : "warn"}
            />
            <Diagnostic
              label="fd4b Notify"
              value={`${state.diagnostics.requiredFd4bNotify.filter((item) => item.subscribed).length}/4`}
              tone={state.diagnostics.requiredFd4bNotify.every((item) => item.subscribed) ? "good" : "warn"}
            />
            <Diagnostic
              label="Retry"
              value={`${state.diagnostics.notifyRetryConfirmed}/${state.diagnostics.notifyRetryAttempts}`}
              tone={notifyRetryTone(state.diagnostics)}
            />
            <Diagnostic
              label="Notify Err"
              value={String(state.diagnostics.notifySubscriptionErrors.length)}
              tone={state.diagnostics.notifySubscriptionErrors.length > 0 ? "bad" : "neutral"}
            />
            <Diagnostic
              label="Hello"
              value={state.diagnostics.helloSent ? "sent" : "pending"}
              tone={state.diagnostics.helloSent ? "good" : "neutral"}
            />
            <Diagnostic
              label="Hello ACK"
              value={helloAckValue(state.diagnostics)}
              tone={helloAckTone(state.diagnostics)}
            />
            <Diagnostic
              label="Writes"
              value={String(state.diagnostics.commandWritesAccepted)}
              tone={state.diagnostics.commandWritesAccepted > 0 ? "good" : "neutral"}
            />
            <Diagnostic
              label="Cmd Resp"
              value={String(state.diagnostics.commandResponsesReceived)}
              tone={state.diagnostics.commandResponsesReceived > 0 ? "good" : state.diagnostics.helloSent ? "warn" : "neutral"}
            />
            <Diagnostic
              label="Custom Notify"
              value={String(state.diagnostics.fd4bNotifyPacketsReceived)}
              tone={state.diagnostics.fd4bNotifyPacketsReceived > 0 ? "good" : "warn"}
            />
          </div>
          {state.diagnostics.bandParityProbe.message ? (
            <p className={`probe-message ${probeTone(state.diagnostics.bandParityProbe)}`}>
              {state.diagnostics.bandParityProbe.message}
            </p>
          ) : null}
          {state.diagnostics.nativeAuthProbe.message ? (
            <p className={`probe-message ${nativeAuthTone(state.diagnostics.nativeAuthProbe)}`}>
              {state.diagnostics.nativeAuthProbe.message}
            </p>
          ) : null}
          {state.diagnostics.macPairingStatus.message ? (
            <p className={`probe-message ${pairingStatusTone(state.diagnostics)}`}>
              {state.diagnostics.macPairingStatus.message}
            </p>
          ) : null}
          {notifyFailureMessage(state.diagnostics) ? (
            <p className="probe-message bad">{notifyFailureMessage(state.diagnostics)}</p>
          ) : null}
        </section>

        <section className="session-strip">
          <Metric label="Capture" value={state.capture.active ? "active" : "idle"} />
          <Metric label="Queued" value={String(state.capture.pendingFrames)} />
          <Metric label="Raw" value={`${state.capture.rawInserted}/${state.capture.rawExisting}`} />
          <Metric label="Decoded" value={`${state.capture.framesInserted}/${state.capture.framesExisting}`} />
          <Metric label="Packets" value={String(state.packets.length)} />
          <Metric label="Import" value={state.capture.lastImportStatus} wide />
        </section>

        <section className="packet-table-wrap">
          <table className="packet-table">
            <thead>
              <tr>
                <th>Time</th>
                <th>Dir</th>
                <th>Characteristic</th>
                <th>Bytes</th>
                <th>Packet</th>
                <th>Seq</th>
                <th>Status</th>
                <th>Summary</th>
              </tr>
            </thead>
            <tbody>
              {state.packets.length === 0 ? (
                <tr>
                  <td colSpan={8} className="empty-cell">No packets captured in this session.</td>
                </tr>
              ) : (
                state.packets.map((packet) => (
                  <PacketRow
                    key={packet.id}
                    packet={packet}
                    selected={selectedPacket?.id === packet.id}
                    onSelect={() => run("select", () => api.selectPacket(packet.id))}
                  />
                ))
              )}
            </tbody>
          </table>
        </section>
      </section>

      <aside className="inspector">
        <div className="panel-heading">
          <span>Inspector</span>
          {selectedPacket?.parserStatus === "parsed" ? <CheckCircle2 size={16} /> : <AlertTriangle size={16} />}
        </div>
        {selectedPacket ? (
          <PacketInspector
            packet={selectedPacket}
            {...(state.lastHelloFrameHex ? { helloFrame: state.lastHelloFrameHex } : {})}
          />
        ) : (
          <div className="empty">Select a packet.</div>
        )}

        <section className="panel log-panel">
          <div className="panel-heading">
            <span>Log</span>
            <small>{state.logs.length}</small>
          </div>
          <div className="log-list">
            {state.logs.slice(0, 80).map((log) => (
              <div className={`log-row ${log.level}`} key={log.id}>
                <span>{timeOnly(log.at)}</span>
                <b>{log.source}</b>
                <p>{log.message}</p>
              </div>
            ))}
          </div>
        </section>
      </aside>
    </main>
  );
}

function DeviceFilterControl(props: {
  value: DeviceFilterMode;
  onChange(mode: DeviceFilterMode): void;
}): JSX.Element {
  return (
    <div className="device-filter" role="group" aria-label="Device filter">
      {DEVICE_FILTER_OPTIONS.map((option) => (
        <button
          key={option.mode}
          className={props.value === option.mode ? "active" : ""}
          type="button"
          onClick={() => props.onChange(option.mode)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function DeviceRow(props: {
  device: DiscoveredDevice;
  active: boolean;
  disabled: boolean;
  onConnect(): void;
}): JSX.Element {
  const { device, active, disabled, onConnect } = props;
  const hasCustomServiceEvidence = device.evidence.toLowerCase().includes("custom service");
  return (
    <button className={`device-row ${active ? "active" : ""}`} disabled={disabled} onClick={onConnect}>
      <div>
        <strong>{displayDeviceName(device)}</strong>
        <span className="device-meta">
          <span>{device.profileLabel}</span>
          {hasCustomServiceEvidence ? <b>custom svc</b> : null}
          <span>{device.evidence}</span>
        </span>
      </div>
      <div className="rssi">{device.rssi} dBm</div>
      {active ? <Plug size={15} /> : null}
    </button>
  );
}

function deviceMatchesFilter(device: DiscoveredDevice, filter: DeviceFilterMode): boolean {
  switch (filter) {
    case "supported":
      return isSupportedDevice(device);
    case "near":
      return isSupportedDevice(device) || isNearDevice(device);
    case "all":
      return true;
  }
}

function isSupportedDevice(device: DiscoveredDevice): boolean {
  return device.profileLabel === "Compatible band" || device.profileLabel === "HR strap";
}

function isNearDevice(device: DiscoveredDevice): boolean {
  return device.rssi <= 0 && device.rssi >= NEARBY_RSSI_FLOOR;
}

function displayDeviceName(device: DiscoveredDevice): string {
  if (device.profileLabel === "Compatible band" && /\bwhoop\b|^wbb/i.test(device.name)) {
    return "Compatible band";
  }
  return device.name;
}

function PacketRow(props: {
  packet: PacketRecord;
  selected: boolean;
  onSelect(): void;
}): JSX.Element {
  const { packet, selected, onSelect } = props;
  return (
    <tr className={selected ? "selected" : ""} onClick={onSelect}>
      <td>{timeOnly(packet.capturedAt)}</td>
      <td><span className={`dir ${packet.direction}`}>{packet.direction}</span></td>
      <td className="mono">{shortUuid(packet.characteristicUuid)}</td>
      <td>{packet.bytes}</td>
      <td>{packet.packetTypeName ?? packet.payloadKind ?? "-"}</td>
      <td>{packet.sequence ?? "-"}</td>
      <td><StatusPill label={packet.parserStatus} tone={statusTone(packet)} compact /></td>
      <td className="summary-cell">{packet.summary}</td>
    </tr>
  );
}

function PacketInspector(props: { packet: PacketRecord; helloFrame?: string }): JSX.Element {
  const { packet, helloFrame } = props;
  return (
    <div className="inspector-body">
      <dl>
        <dt>Captured</dt><dd>{packet.capturedAt}</dd>
        <dt>Source</dt><dd>{packet.source}</dd>
        <dt>Service</dt><dd className="mono">{packet.serviceUuid}</dd>
        <dt>Characteristic</dt><dd className="mono">{packet.characteristicUuid}</dd>
        <dt>Evidence</dt><dd>{packet.evidenceId ?? "-"}</dd>
      </dl>

      {packet.standardHeartRate ? (
        <section className="detail-block">
          <h2>Heart Rate</h2>
          <div className="hr-readout">{packet.standardHeartRate.bpm}<span>bpm</span></div>
          <p>{packet.standardHeartRate.rrIntervalsMs.length} RR intervals</p>
        </section>
      ) : null}

      {packet.warnings.length || packet.importIssues.length ? (
        <section className="detail-block warning-list">
          <h2>Warnings</h2>
          {[...packet.warnings, ...packet.importIssues].map((warning, index) => (
            <p key={`${warning}-${index}`}>{warning}</p>
          ))}
        </section>
      ) : null}

      {helloFrame ? (
        <section className="detail-block">
          <h2>Last Hello Frame</h2>
          <pre className="hex-block">{groupHex(helloFrame)}</pre>
        </section>
      ) : null}

      <section className="detail-block">
        <h2>Frame Hex</h2>
        <pre className="hex-block">{groupHex(packet.frameHex)}</pre>
      </section>

      <section className="detail-block">
        <h2>Parsed</h2>
        <pre>{JSON.stringify(packet.parsedJson ?? null, null, 2)}</pre>
      </section>
    </div>
  );
}

function StatusPill(props: { label: string; tone: "good" | "warn" | "bad" | "neutral"; compact?: boolean }): JSX.Element {
  return <span className={`status-pill ${props.tone} ${props.compact ? "compact" : ""}`}>{props.label}</span>;
}

function Metric(props: { label: string; value: string; wide?: boolean }): JSX.Element {
  return (
    <div className={`metric ${props.wide ? "wide" : ""}`}>
      <span>{props.label}</span>
      <strong>{props.value}</strong>
    </div>
  );
}

function Diagnostic(props: { label: string; value: string; tone: "good" | "warn" | "bad" | "neutral" }): JSX.Element {
  return (
    <div className={`diagnostic ${props.tone}`}>
      <span>{props.label}</span>
      <strong>{props.value}</strong>
    </div>
  );
}

function helloAckValue(diagnostics: DebuggerAppState["diagnostics"]): string {
  if (!diagnostics.helloSent) {
    return "pending";
  }
  if (!diagnostics.helloResponseReceived) {
    return "missing";
  }
  if (diagnostics.helloResponseResultCode === undefined) {
    return "received";
  }
  return diagnostics.helloResponseResultCode === 1 ? "ok" : `code ${diagnostics.helloResponseResultCode}`;
}

function helloAckTone(diagnostics: DebuggerAppState["diagnostics"]): "good" | "warn" | "bad" | "neutral" {
  if (!diagnostics.helloSent) {
    return "neutral";
  }
  if (!diagnostics.helloResponseReceived) {
    return "warn";
  }
  if (diagnostics.helloResponseResultCode === undefined || diagnostics.helloResponseResultCode === 1) {
    return "good";
  }
  return "bad";
}

function notifyRetryTone(diagnostics: DebuggerAppState["diagnostics"]): "good" | "warn" | "bad" | "neutral" {
  if (diagnostics.notifyRetryAttempts === 0) {
    return "neutral";
  }
  if (diagnostics.notifyRetryErrors > 0 && diagnostics.notifyRetryConfirmed === 0) {
    return "bad";
  }
  if (diagnostics.notifyRetryConfirmed > 0) {
    return "good";
  }
  return "warn";
}

function notifyFailureMessage(diagnostics: DebuggerAppState["diagnostics"]): string | undefined {
  if (pairingRequired(diagnostics)) {
    return "fd4b notify is blocked by macOS link security. Pair or bond the band in Bluetooth Settings, then rerun Native Auth Probe.";
  }
  if (diagnostics.notifySubscriptionErrors.length === 0) {
    return undefined;
  }
  const authError = diagnostics.notifySubscriptionErrors.find((item) => /authenticat|encrypt/i.test(item.message));
  if (authError) {
    return `fd4b notify failed: ${authError.message}. Pair or bond the band to this Mac before expecting custom notify frames.`;
  }
  return `fd4b notify failed: ${diagnostics.notifySubscriptionErrors[0]?.message ?? "unknown error"}`;
}

function pairingRequired(diagnostics: DebuggerAppState["diagnostics"]): boolean {
  if (diagnostics.nativeAuthProbe.stage === "auth required") {
    return true;
  }
  if (diagnostics.nativeAuthProbe.authErrors.some((line) => /authenticat|encrypt/i.test(line))) {
    return true;
  }
  return diagnostics.bandParityProbe.stage === "auth required";
}

function pairingStatusValue(diagnostics: DebuggerAppState["diagnostics"]): string {
  const status = diagnostics.macPairingStatus;
  if (status.active || status.stage === "checking") {
    return "checking";
  }
  if (status.known === true && status.connected === true) {
    return "connected";
  }
  if (status.known === true) {
    return "registered";
  }
  if (status.advertising === true || status.stage === "advertising unregistered") {
    return "advertising";
  }
  if (status.known === false || status.stage === "not registered") {
    return "not paired";
  }
  if (pairingRequired(diagnostics)) {
    return "required";
  }
  return "unknown";
}

function pairingStatusTone(diagnostics: DebuggerAppState["diagnostics"]): "good" | "warn" | "bad" | "neutral" {
  const value = pairingStatusValue(diagnostics);
  if (value === "connected" || value === "registered") {
    return "good";
  }
  if (value === "checking") {
    return "warn";
  }
  if (value === "advertising") {
    return "warn";
  }
  if (value === "not paired" || value === "required") {
    return "bad";
  }
  return "neutral";
}

function probeTone(probe: DebuggerAppState["diagnostics"]["bandParityProbe"]): "good" | "warn" | "bad" | "neutral" {
  if (probe.active) {
    return "warn";
  }
  if (probe.success === true) {
    return "good";
  }
  if (probe.success === false) {
    return "bad";
  }
  return "neutral";
}

function nativeAuthTone(probe: DebuggerAppState["diagnostics"]["nativeAuthProbe"]): "good" | "warn" | "bad" | "neutral" {
  if (probe.active) {
    return "warn";
  }
  if (probe.success === true) {
    return "good";
  }
  if (probe.stage === "auth required" || probe.authErrors.length > 0) {
    return "bad";
  }
  if (probe.success === false) {
    return "bad";
  }
  return "neutral";
}

function statusTone(packet: PacketRecord): "good" | "warn" | "bad" | "neutral" {
  if (packet.parserStatus === "parsed") {
    return packet.warnings.length ? "warn" : "good";
  }
  if (packet.parserStatus === "parse_failed") {
    return "bad";
  }
  if (packet.parserStatus === "raw" || packet.parserStatus === "buffered") {
    return "neutral";
  }
  return "warn";
}

function shortUuid(uuid: string): string {
  return uuid.length > 18 ? `${uuid.slice(0, 8)}…${uuid.slice(-4)}` : uuid;
}

function timeOnly(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleTimeString([], { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function groupHex(hex: string): string {
  return hex.match(/.{1,2}/g)?.join(" ") ?? hex;
}

function createBrowserFallbackApi(): NonNullable<Window["openVitalsDebugger"]> {
  let fallbackState: DebuggerAppState = {
    ...initialState,
    bluetoothState: "Electron preload unavailable",
    capture: {
      ...initialState.capture,
      databasePath: "~/Library/Application Support/OpenVitals BLE Packet Debugger/open_vitals_ble_debugger.sqlite",
      lastImportStatus: "browser preview",
    },
    rust: {
      ready: false,
      lastError: "Electron required for BLE capture.",
    },
  };

  const commit = (next: DebuggerAppState): Promise<DebuggerAppState> => {
    fallbackState = next;
    return Promise.resolve(fallbackState);
  };

  return {
    getState: () => Promise.resolve(fallbackState),
    startScan: () => commit({ ...fallbackState, scanning: true, connectionState: "scanning" }),
    stopScan: () => commit({ ...fallbackState, scanning: false, connectionState: "idle" }),
    connect: () => Promise.reject(new Error("BLE connection requires Electron.")),
    disconnect: () => commit({ ...fallbackState, connectionState: "idle" }),
    startCapture: (options?: StartCaptureOptions) => commit({
      ...fallbackState,
      capture: {
        ...fallbackState.capture,
        active: true,
        databasePath: options?.databasePath ?? fallbackState.capture.databasePath,
        lastImportStatus: "browser preview",
      },
    }),
    stopCapture: () => commit({
      ...fallbackState,
      capture: {
        ...fallbackState.capture,
        active: false,
        lastImportStatus: "browser preview",
      },
    }),
    setDatabasePath: (databasePath: string) => commit({
      ...fallbackState,
      capture: {
        ...fallbackState.capture,
        databasePath,
      },
    }),
    storageCheck: (): Promise<StorageCheckResult> => Promise.resolve({
      pass: false,
      report: { status: "electron_required" },
    }),
    sendHello: () => Promise.reject(new Error("BLE writes require Electron.")),
    startIosParityPhysiologyProbe: () => Promise.reject(new Error("BLE writes require Electron.")),
    startBandParityProbe: (_options?: StartBandParityProbeOptions) => {
      return Promise.reject(new Error("BLE writes require Electron."));
    },
    runNativeAuthProbe: () => Promise.reject(new Error("Native auth probe requires Electron.")),
    checkMacPairingStatus: () => Promise.reject(new Error("macOS pairing check requires Electron.")),
    openBluetoothSettings: () => Promise.resolve(),
    startPhysiologyCapture: () => Promise.reject(new Error("BLE writes require Electron.")),
    stopPhysiologyCapture: () => Promise.reject(new Error("BLE writes require Electron.")),
    enterHighFrequencyHistorySync: () => Promise.reject(new Error("BLE writes require Electron.")),
    exitHighFrequencyHistorySync: () => Promise.reject(new Error("BLE writes require Electron.")),
    selectPacket: (packetId: string) => commit({ ...fallbackState, selectedPacketId: packetId }),
    onStateChanged: () => () => undefined,
  };
}
