# OpenVitals Agent Guide

## What This App Is

OpenVitals is a local-first iOS health monitoring app for compatible user-owned BLE health wearables. Publicly, position it as a general purpose BLE health monitor that helps users inspect live device data, local health metrics, sleep, recovery, strain, stress, cardio, energy, exports, and diagnostics.

Internal context: the app was built by reverse-engineering the WHOOP app/protocol so it can be used with a WHOOP 5 without requiring a subscription. This is for personal use, friends, and family. The project is not intended to monetize, compete with WHOOP, or imply affiliation.

Do not put WHOOP in user-facing copy, marketing copy, README-style positioning, screenshots, UI strings, release notes, or support/about text unless the user explicitly asks for an internal/research note. Use neutral phrasing such as "compatible BLE health device", "wearable", "band", or "device". Internal code names, protocol fixtures, command evidence, and agent-only notes may mention WHOOP when that is necessary to understand the implementation.

## Product Principles

- Local-first by default. Health and fitness data should stay on device unless a feature has explicit consent, privacy notes, and a clear data flow.
- Never fabricate metric values. Runtime surfaces may show live, local, bridge-derived, imported-with-provenance, stale, or unavailable states only.
- Keep health copy careful and non-medical. Avoid diagnostic, treatment, or certainty claims.
- Treat packet captures, logs, exports, HealthKit data, identifiers, and calibration labels as sensitive.
- Raw packets and low-level command details belong under More, Debug, Capture, Export, or similarly operational surfaces, not everyday health views.
- Public positioning should emphasize independence and user-owned devices. Do not imply manufacturer affiliation or use manufacturer-owned source code.

## Code Map

- `OpenVitals/`: SwiftUI app source.
- `OpenVitalsWorkoutLiveActivityExtension/`: Live Activity widget extension.
- `OpenVitals.xcodeproj`: Xcode project.
- `Rust/core/`: Rust protocol, evidence, validation, SQLite, metrics, export, privacy, command, and bridge core.
- `Scripts/build_ios_rust.sh`: Xcode build phase script that builds and stages the Rust static library.
- `Tools/ble-packet-debugger/`: internal Electron/TypeScript macOS BLE packet debugger for direct desktop scan, connect, packet capture, Rust parsing, and local SQLite imports.
- `docs/open-vitals-mvp/`: feature contracts and remaining MVP work.
- `docs/desktop-ble-packet-debugger.md`: desktop debugger architecture, capabilities, workflow, and safety boundaries.
- `docs/testing-and-tooling-strategy.md`: preferred validation/tooling order.
- `docs/learnings.md`: durable lessons discovered while building.
- `docs/blocked.md`: requests blocked on human input, device actions, captures, labels, credentials, or product decisions.

Key Swift entry points:

- `OpenVitalsApp.swift`: app lifecycle, scene phase handling, deep links.
- `RootView.swift`: onboarding gate and sync toast host.
- `AppShellView.swift`: tab shell. Home, Health, and More are currently in the bottom tabs; Coach code exists but is commented out of `bottomTabs`.
- `OpenVitalsAppModel.swift` and extensions: app state, BLE ownership, notification pipeline, lifecycle, packet publishing, health capture, activity recording, overnight guard, and bridge summaries.
- `OpenVitalsBLEClient.swift` and extensions: CoreBluetooth scanning, connect/reconnect, services, commands, historical sync, vitals, logging, and peripheral/central delegates.
- `OpenVitalsRustBridge.swift`: JSON-over-C bridge wrapper around the Rust core.
- `HealthDataStore.swift` and extensions: health metric catalogs, packet inputs, packet scores, snapshots, trends, sleep, vitals, cardio, stress, energy, validation, and coach summaries.
- `HomeDashboardView.swift`, `HealthView.swift`, `CoachView.swift`, `MoreView.swift`: main product surfaces.

## Architecture Notes

The main runtime flow is BLE device data through `OpenVitalsBLEClient`, then `OpenVitalsAppModel` notification and packet pipelines, then local storage/Rust bridge processing, then SwiftUI views through `HealthDataStore` and app model state.

The Rust core is intentionally the trusted place for protocol parsing, capture import/sanitize, metric input readiness, local metric calculations, reference comparisons, calibration, raw export, privacy lint, command validation, debug WebSocket contracts, storage checks, and app bridge responses. Swift should call bridge methods and render typed view models instead of duplicating packet schemas or metric formulas when Rust already owns them.

The app stores local SQLite data under the app's Application Support `OpenVitals/open_vitals.sqlite` path through `HealthDataStore.defaultDatabasePath()`. Built Rust archives are generated artifacts staged under `Rust/iphoneos/` or `Rust/iphonesimulator/` and should not be committed.

The desktop BLE packet debugger mirrors the capture side of the app without routing packets through the phone. It runs an Electron renderer, a plain Node BLE host using `@abandonware/noble`, and `open-vitals-bridge --stdio` for Rust-owned parsing and SQLite writes. It can scan and filter supported/nearby/all BLE devices, connect to compatible bands and standard Heart Rate Service straps, subscribe to useful notify/read characteristics, show live raw/decoded packet rows, send explicit hello/probe commands, store capture sessions with sensitive raw evidence, and insert standard RR-reference samples for validation.

## Feature Boundaries

- Home is the daily command center: live device state, today's scores, outlook, timeline, shortcuts, and evidence footer.
- Health owns metric detail: Health Monitor, Sleep, Recovery, Strain, Stress, Cardio Load, Energy Bank, Packet Inputs, Algorithms, References, and Calibration.
- More owns operations: Device, Connection Lab, Capture, Local Store, Health Sync, Raw Export, Algorithms settings, Debug, Privacy, Support, and About.
- Desktop debugger work is internal developer tooling. Keep its UI and docs brand-neutral, operational, and privacy-conscious; use it to accelerate protocol discovery and feed findings back into Rust/Swift mobile logic.
- Coach should remain deterministic and provenance-backed until there is a backend, privacy policy, persistence strategy, and consent path for free-form AI chat.

## Data And Safety Rules

- Show provenance for values whenever possible: live BLE, local SQLite, Rust bridge, HealthKit, imported capture, user label, benchmark/reference, stale, or unavailable.
- Keep platform sleep imports quarantined as reference evidence unless the active metric contract explicitly permits them.
- Do not write RMSSD HRV into a HealthKit field with incompatible semantics.
- Direct BLE writes must remain gated by command validation, visible user intent, dry-run bytes, session logging, and explicit confirmation for critical/destructive actions.
- Desktop debugger packet captures, RR-reference samples, command writes, local SQLite files, and export bundles are sensitive. Store them locally by default, label provenance clearly, and run privacy lint before sharing.
- Keep destructive/debug commands behind More/Debug-style operational routes with clear disabled states until backing gates pass.
- Run privacy lint on raw exports before treating them as shareable artifacts.

## Build And Test Commands

Simulator build:

```sh
xcodebuild \
  -project OpenVitals.xcodeproj \
  -scheme OpenVitals \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/open-vitals-deriveddata \
  build
```

Physical device build:

```sh
xcodebuild \
  -project OpenVitals.xcodeproj \
  -scheme OpenVitals \
  -configuration Debug \
  -destination 'platform=iOS,id=<device-id>' \
  -derivedDataPath /tmp/open-vitals-deriveddata-device \
  -allowProvisioningUpdates \
  build
```

Rust targets needed for iOS builds:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
```

Rust checks:

```sh
cd Rust/core
cargo test
```

Useful Rust validation tools live in `Rust/core/src/bin/`. Common gates include `open-vitals-metric-input-readiness`, `open-vitals-capture-sqlite-import`, `open-vitals-command-capture-plan`, `open-vitals-metric-feature-report`, `open-vitals-local-health-validation-suite`, `open-vitals-export-validator`, `open-vitals-privacy-lint`, `open-vitals-property-test-suite`, and `open-vitals-perf-budget`.

Desktop BLE debugger:

```sh
cd Tools/ble-packet-debugger
npm install
npm run typecheck
npm run build
npm run dev
```

Use `OPENVITALS_BLE_DEBUGGER_DB=/absolute/path/open_vitals_ble_debugger.sqlite` to point the debugger at a specific local database, and `OPENVITALS_BRIDGE_BIN=/absolute/path/open-vitals-bridge` to use a prebuilt Rust bridge instead of `cargo run`.

## Working Rules For Future Agents

- Read the relevant MVP doc before changing a feature surface, then update it when the task changes status or scope.
- Read `docs/desktop-ble-packet-debugger.md` before changing the desktop BLE debugger's capture, parser, storage, command, or device-filtering behavior, then update it when capabilities or safety boundaries change.
- Update `docs/learnings.md` when a discovery will matter after the current task.
- Update `docs/blocked.md` when a request is blocked on human input or action, and remove/update entries once the blocker is resolved.
- Keep changes scoped and match the existing SwiftUI/Rust style.
- Build after touching Swift, Rust bridge, Xcode project settings, signing, build scripts, or bridge headers. For docs-only changes, say that no build was run.
- Protect user changes. The worktree may already be dirty; do not revert unrelated edits.
- Prefer typed models and explicit unavailable states over raw strings or preview/sample values in runtime UI.
- Keep public copy brand-neutral and privacy-conscious.
