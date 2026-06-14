# Desktop BLE Packet Debugger

This document is the durable reference for the internal macOS BLE packet debugger at `Tools/ble-packet-debugger`.

## Purpose

The debugger speeds up BLE protocol discovery by capturing packets directly on the Mac instead of routing every experiment through the iOS app, phone logs, export bundles, and manual imports. It is developer tooling for owned compatible BLE health devices and reference sensors. Findings from the debugger should be promoted back into Rust parsing/storage first, then into Swift mobile behavior.

Keep this surface operational and brand-neutral. User-facing labels should say "compatible band", "HR strap", "wearable", or "device" unless the user explicitly asks for an internal research note.

## Run And Validate

```sh
cd Tools/ble-packet-debugger
npm install
npm run typecheck
npm run build
npm run dev
```

Use `npm start` for a built Electron run. Development uses the Vite renderer on `127.0.0.1:5176`; built runs force `OPENVITALS_BLE_DEBUGGER_USE_BUILT=1` so Electron loads `dist-renderer` instead of any unrelated local app.

Useful environment variables:

- `OPENVITALS_BLE_DEBUGGER_DB=/absolute/path/open_vitals_ble_debugger.sqlite`: override the local SQLite path.
- `OPENVITALS_BRIDGE_BIN=/absolute/path/open-vitals-bridge`: use a prebuilt Rust bridge instead of spawning `cargo run --bin open-vitals-bridge -- --stdio`.
- `OPENVITALS_REPO_ROOT=/absolute/path/openvitals`: override repo root discovery when running packaged or from an unusual cwd.
- `OPENVITALS_BLE_DEBUGGER_USE_BUILT=1`: load the built renderer instead of the Vite dev server.

Native auth check:

```sh
cd Tools/ble-packet-debugger
npm run probe:corebluetooth
```

Stop the Electron debugger first so only the native probe is connected to the band. This Swift/CoreBluetooth probe prints notification-state errors that the noble macOS binding hides.

The debugger UI also exposes `Native Auth Probe`, which stops the active scan/capture/connection before running the same native probe and streams the output into the log. Use `Check Pairing` to distinguish "advertising nearby" from "registered/bonded with macOS", then use `Bluetooth Settings` from the debugger to open the macOS pairing pane when the native probe reports authentication/encryption failures.

## Architecture

- Electron main process creates the window and IPC surface.
- Electron renderer is React/TypeScript and only talks through the preload bridge.
- Electron preload keeps `contextIsolation: true` and `nodeIntegration: false`; `sandbox: false` is intentional so the preload can import local shared IPC constants.
- A separate plain Node BLE host process uses `@abandonware/noble` for macOS BLE scan/connect/subscribe/write work.
- The host calls `open-vitals-bridge --stdio` through `RustBridgeClient`, so Rust remains the parser/import/storage source of truth.
- Captures are written to local SQLite through Rust bridge methods, not through ad hoc TypeScript SQL.

## What It Can Do

- Scan nearby BLE peripherals and classify them as compatible bands, standard Heart Rate Service straps, or nearby BLE devices.
- Filter the device list by `Supported`, `Near`, or `All`; `Supported` is the default for noisy BLE environments.
- Prefer advertised custom band service evidence before name-based accessory filtering, so band-like names with the custom service remain selectable.
- Connect to compatible bands and standard HR straps from the device list.
- Discover and display GATT services/characteristics, including command, notify, heart-rate, battery, device-info, and other roles.
- Subscribe to custom band notify characteristics and standard Heart Rate Measurement `180D/2A37` notifications.
- Read useful battery and Device Information characteristics when they are readable.
- Accumulate custom band notification chunks into complete frames, then parse them with Rust using `protocol.parse_frame_hex_batch`.
- Show raw, buffered, parsed, and parse-failed packet rows with direction, characteristic, byte count, packet type, sequence, status, summary, warnings, and detail JSON.
- Start and stop capture sessions in local SQLite with provenance `mac.bluetooth.desktop_debugger`.
- Import captured frames through `capture.import_frame_batch`, including writes, reads, notifications, raw evidence, and decoded frames where Rust can parse them.
- Decode standard Heart Rate Measurement notifications live in TypeScript and insert RR-reference samples through the Rust bridge for validation-only evidence.
- Run a storage check through Rust `storage.check`.
- Send an explicit fixed iOS-parity client hello frame once a compatible command characteristic is ready.
- Send explicit physiology/start-stop and high-frequency history-sync probe commands only from UI actions; command frames are built by Rust via `protocol.build_v5_command_frame`.
- Run `Start Band Parity Probe` as a one-button desktop flow: stop existing scan/capture, scan for a custom-service compatible band, connect without auto-hello, start capture, verify `fd4b0002`, verify `fd4b0003/0004/0005/0007` subscriptions, send hello, require a GET_HELLO command response within the iOS-parity wait window, send the iOS-parity physiology command sequence, and watch for custom notify frames.
- Run `Native Auth Probe` from the UI to verify whether CoreBluetooth allows fd4b notifications and writes on the current Mac link.
- Run `Check Pairing` from the UI to check both macOS Bluetooth registration and a short fd4b advertisement scan, so the debugger can report when the band is nearby but not bonded/registered.
- Open macOS Bluetooth Settings from the UI when pairing/bonding is required.
- Show explicit parity diagnostics for hello sent, hello ACK/result code, accepted command writes, parsed command responses, `fd4b0002` command readiness, required fd4b notify requests, confirmed fd4b notify state, notify subscription errors, native auth probe status, pairing-required or advertising-but-unregistered state, custom notify counts, "no hello response after N seconds", and "no custom frames after N seconds".
- When all fd4b notifications are requested but none confirm, and `GET_HELLO` does not ACK, treat the likely failure as link authentication/encryption rather than packet parsing. The native CoreBluetooth probe can confirm this with errors such as "Encryption is insufficient" or "Authentication is insufficient".

## Capture Workflow

1. Run the debugger and wait for Bluetooth state `poweredOn`.
2. Use `Supported` to focus on compatible bands and HR straps; switch to `Near` for supported plus stronger-signal nearby devices or `All` for full discovery.
3. Click the target compatible band or HR strap row to connect.
4. Confirm Rust is ready and the database path is correct.
5. Click `Start Capture`.
6. For compatible bands, use `Start Band Parity Probe` when the goal is a clean yes/no desktop parity run.
7. For HR straps, wait for live HR/RR packet rows before relying on RR-reference evidence.
8. Click `Stop Capture` and let the queued import count drain to zero.
9. Use Rust reports, raw export, privacy lint, and metric validation tools before promoting findings to mobile logic.

For a manual fallback run, connect the compatible band, start capture, use `Hello`, `Start Physiology`, `Enter High-Frequency History Sync`, or `Exit High-Frequency History Sync` as needed, and confirm the packet table contains custom notify rows from fd4b characteristics. Command-write rows alone are not a successful band-side capture: `fd4b Req` only means the desktop asked for notifications, `fd4b Notify` means the OS confirmed notification state, `Retry` shows repeated notification-enable attempts that later confirmed, `Writes` only means the local BLE write callback completed, and `Hello ACK` / `Cmd Resp` require parsed fd4b command-response frames from the device. Do not directly write the Client Characteristic Configuration descriptor from the macOS backend; CoreBluetooth throws for CCCD writes and requires notification state through `setNotifyValue`.

## Storage And Provenance

The default database is Electron's `userData` path plus `open_vitals_ble_debugger.sqlite`, unless `OPENVITALS_BLE_DEBUGGER_DB` is set. Capture sessions use ids like `desktop-<timestamp>-<counter>`, source `mac.bluetooth.desktop_debugger`, transport `macos-node-noble`, parser `rust-bridge`, and sensitivity `sensitive`.

Standard HR strap RR intervals are stored as validation-only reference evidence with provenance `standard_ble_heart_rate_service`. They should not become primary OpenVitals HRV metrics unless a Rust metric contract explicitly promotes them.

## Safety Boundaries

- Treat all debugger captures, packet rows, local databases, export bundles, command evidence, identifiers, and labels as sensitive.
- Keep direct writes visible and intentional. Critical or persistent commands need command validation, dry-run bytes, session logging, and rollback expectations before they become normal workflows.
- Do not duplicate packet schemas or metric formulas in TypeScript when Rust already owns them.
- Keep unsupported charger/power accessories classified as nearby BLE unless they advertise the compatible band service. In particular, name-based WBB accessory filtering must run after custom-service matching.
- Keep public copy brand-neutral. Internal code, service UUIDs, and research evidence may retain protocol-specific names when needed to implement or validate behavior.

## Known Gaps

- The debugger is an internal workbench, not a polished end-user app.
- It currently depends on macOS BLE access through `@abandonware/noble`, so OS permission and adapter state matter.
- Compatible band notification availability still depends on the correct command sequence and device state.
- The renderer keeps only the most recent packet rows in memory; SQLite is the durable capture record.
- Raw export and privacy lint are still handled by existing Rust/export tooling outside the debugger.
