# OpenVitals BLE Packet Debugger

Internal macOS desktop workbench for scanning compatible BLE health devices, capturing notifications and reads, parsing OpenVitals-compatible frames through the Rust core, and writing evidence into a local OpenVitals SQLite database.

See `../../docs/desktop-ble-packet-debugger.md` for the full architecture, workflow, and safety notes.

## Run

```sh
cd Tools/ble-packet-debugger
npm install
npm run typecheck
npm run build
npm run dev
```

Use `npm start` for the built Electron app. The dev script uses the Vite renderer on `127.0.0.1:5176`; the built start path forces `OPENVITALS_BLE_DEBUGGER_USE_BUILT=1` so Electron does not accidentally load another local app.

For a native CoreBluetooth auth check outside the UI, stop the Electron debugger so it releases the band, then run:

```sh
npm run probe:corebluetooth
```

This probes the same fd4b service directly through Swift/CoreBluetooth and prints notification-state and write errors that noble does not expose.

The debugger launches an Electron renderer plus a plain Node BLE host process. The host calls `Rust/core` through `open-vitals-bridge --stdio`, so parser and database writes stay aligned with the iOS app.

## Capabilities

- Scan nearby BLE devices and classify compatible bands, standard Heart Rate Service straps, and nearby BLE devices.
- Filter the scanner by `Supported`, `Near`, or `All`; `Supported` is the default for noisy environments.
- Connect from the device list and display discovered command, notify, heart-rate, battery, device-info, and other characteristics.
- Subscribe to custom notify characteristics and standard Heart Rate Measurement `180D/2A37` notifications.
- Decode standard HR/RR samples live and write RR-reference samples through the Rust bridge for validation-only evidence.
- Accumulate custom notification chunks into frames, parse them with Rust, and show packet type, sequence, status, warnings, and detail JSON.
- Start/stop local SQLite capture sessions and import captured frames through `capture.import_frame_batch`.
- Run Rust storage checks against the selected local database.
- Send explicit hello and iOS-parity physiology probe actions for protocol experiments.
- Run `Start Band Parity Probe` to stop prior scan/capture, scan for a custom-service band, connect, start capture before writes, verify fd4b command/notify characteristics, send hello, require a GET_HELLO command response, send the physiology sequence, and report whether fd4b custom notify frames arrived.
- Run `Native Auth Probe` from the UI to release the active BLE session, run the Swift/CoreBluetooth auth check, and stream authentication/encryption evidence into the debugger log and diagnostics.
- Run `Check Pairing` from the UI to check whether macOS Bluetooth already lists the compatible band as registered or connected, and to distinguish "nearby advertising fd4b" from "bonded/registered with macOS".
- Open macOS Bluetooth Settings from the debugger when pairing/bonding is needed for fd4b notification security.
- Use fallback `Start Physiology`, `Stop Physiology`, `Enter High-Frequency History Sync`, and `Exit High-Frequency History Sync` buttons for manual probe runs.

## Notes

- The default database path is Electron `userData` plus `open_vitals_ble_debugger.sqlite`; override it with `OPENVITALS_BLE_DEBUGGER_DB`.
- Use `OPENVITALS_BRIDGE_BIN` to point at a prebuilt `open-vitals-bridge`; otherwise the app spawns `cargo run --bin open-vitals-bridge -- --stdio`.
- Direct writes are limited to explicit UI actions. Sensor/probe command frames are built by Rust so sequence, payload, and checksum behavior stay aligned with mobile.
- The diagnostics split notification requests, confirmed notification state, subscription errors, retry attempts, native auth probe state, macOS pairing status, OS-level write acceptance, and band-side protocol responses. `fd4b Req` means the desktop requested notifications, `fd4b Notify` means the OS confirmed notification state, `Notify Err` counts explicit subscribe failures, `Auth Probe` reports the native CoreBluetooth security check, `Pairing` reports whether macOS lists the compatible band, whether it is only advertising nearby, or whether probe evidence says pairing is required, `Retry` reports later notification-enable attempts that became confirmed, `Writes` means the BLE write callback completed, and `Hello ACK` / `Cmd Resp` mean custom fd4b response frames were parsed from notifications. Do not write the Client Characteristic Configuration descriptor directly on macOS; CoreBluetooth requires notification state to be configured through `setNotifyValue`.
- Packet captures, RR-reference samples, command evidence, and local databases are sensitive artifacts.
- If fd4b notification requests are sent but notification state is not confirmed and `GET_HELLO` gets no response, run `npm run probe:corebluetooth`. A result like `Encryption is insufficient` or `Authentication is insufficient` means the Mac has an unauthenticated BLE link; pairing/bonding must be solved before custom notify packets can arrive.
