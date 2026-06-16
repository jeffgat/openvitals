# OpenVitals Swift MVP: More

Source map: Flutter `SettingsView`, `DeviceView`, `CaptureView`, `DebugView`, Swift `MorePlaceholderView`, Swift `DeviceView`, Swift `ConnectionView`.

MVP rule: More owns operational surfaces: device, connection lab, capture/import, Health sync, raw export, algorithm settings, storage, debug, privacy, and support. It should be dense, inspectable, and honest about readiness.

## Parent View Contract

- [ ] Create a dedicated `MoreView.swift` or split `MorePlaceholderView` out of `AppShellView.swift`.
- [ ] Keep this tab behind the Swift `More` tab item.
- [ ] Define child routes: Device, Connection Lab, Capture, Debug, Local Store, Health Sync, Raw Export, Stream Probe Plan, Algorithms, Privacy, Support/About.
- [x] Expose Collect as the middle bottom tab and point it at the same Data Collection route normally opened from More.
- [ ] Keep operational rows compact and list-based.
- [ ] Add status badges for ready, pending, blocked, unavailable, stale.
- [ ] Add previews for default, connected, and debug-heavy states.

## Device

- [ ] Keep current Swift `DeviceView` as the primary Device route.
- [ ] Show status and advanced panels.
- [ ] Keep WHOOP image asset in Swift asset catalog.
- [ ] Show live device name, connection, battery, firmware, model, last sync.
- [ ] Show live HR, Rust status, last parsed frame summary.
- [ ] Show actions: Bluetooth, scan, connect, reconnect, send hello, forget.
- [ ] Show discovered devices list.
- [ ] Show recent event log.
- [ ] Ensure all copy is backed by `OpenVitalsBLEClient` or marked unavailable.

## Connection Lab

- [ ] Keep existing `ConnectionView` as a lab/debug route, not the primary user device view.
- [ ] Show Bluetooth state.
- [ ] Show connection state.
- [ ] Show reconnect state.
- [ ] Show remembered device.
- [ ] Show live HR source/update.
- [ ] Show Rust and client hello summaries.
- [ ] Show discovered devices and event log.
- [ ] Keep command actions available for debugging.

## Capture

- [ ] Port capture/import surface from Flutter `CaptureView`.
- [ ] Show capture session summary from `captureSessionSummary()`.
- [ ] Show live notification capture summary from `liveNotificationCaptureSummary()`.
- [ ] Show selected discovered device.
- [ ] Show recent notifications/events.
- [ ] Add actions for starting/stopping capture where Swift bridge supports it.
- [ ] Add import capture file action.
- [ ] Add import command evidence file action.
- [ ] Add import emulator log action.
- [ ] Add local frame match action.
- [ ] Add validated sample/read command action.
- [x] Add a separate desktop BLE packet debugger under `Tools/ble-packet-debugger` for Mac-side scanning, capture, Rust parsing, and local SQLite imports without routing every packet through the phone.
- [x] Aggregate Capture, Raw Export, and Stream Probe Plan into one Data Collection surface with intent-based controls for Mac Stream, live data, historical catch-up, reference data, and export fallback; keep packet/field/command toggles under advanced tools.
- [x] Match the desktop BLE packet debugger renderer to the iOS dark graphite/champagne OpenVitals palette.
- [x] Add desktop scanner filters for supported, near, and all devices so noisy BLE environments can focus on compatible bands and HR straps.
- [x] Store desktop debugger captures as local SQLite sessions with `mac.bluetooth.desktop_debugger` provenance through the Rust bridge.
- [x] Store standard Heart Rate Service RR samples from HR straps as validation-only reference evidence.
- [x] Add an optional Mac Stream path where explicit iOS capture sessions and lean Overnight Guard historical catch-up mirror frame batches over a token-gated local/Tailscale endpoint into the same desktop debugger SQLite database as HR-strap RR reference data.
- [x] Document the desktop debugger architecture, workflow, safety boundaries, and validation commands in `docs/desktop-ble-packet-debugger.md`.

## Local Store

- [ ] Show SQLite/local store path.
- [ ] Show storage check status from `storageCheckStatusSummary()`.
- [ ] Show schema version.
- [ ] Show storage next action from `storageCheckNextActionSummary()`.
- [ ] Add Check action once Swift bridge supports storage check.
- [ ] Add empty state for no database yet.

## Health Sync

- [ ] Show backfill window from `healthSyncBackfillWindowSummary()`.
- [ ] Show backfill validation issue from `healthSyncBackfillWindowIssueSummary()`.
- [ ] Add editable backfill start/end fields.
- [ ] Show selected metric families from `healthSyncMetricFamilySummary()`.
- [ ] Add family toggles: heart_rate, resting_heart_rate, hrv, steps, activity.
- [ ] Show metric source rows via `healthSyncMetricSourceSummary(family)`.
- [ ] Show unavailable families: respiratory_rate, oxygen_saturation, skin_temperature, sleep, active_energy.
- [ ] Show Health adapter availability.
- [ ] Show Health authorization state.
- [ ] Show existing OpenVitals records.
- [ ] Show platform sleep imports only as reference/quarantined evidence.
- [ ] Add Apple Health dry run action only for outbound/profile-boundary audits.
- [ ] Add Health Connect dry run action only if Android/shared build ever needs it.
- [ ] Add refresh Health adapter action.
- [ ] Show platform reports from `healthSyncReports`.

## Raw Export

- [ ] Show export window from `rawExportWindowSummary()`.
- [ ] Show export window issues from `rawExportWindowIssueSummary()`.
- [ ] Show export scope from `rawExportScopeSummary()`.
- [ ] Add editable fields: start, end, capture sessions, packet types, sensor signals, metric families, algorithm ids, algorithm versions.
- [ ] Add raw bytes toggle.
- [ ] Add data family chips: raw_evidence, decoded_frames, packet_timeline, metric_inputs, algorithm_runs, calibration_labels, calibration_runs, sqlite.
- [ ] Show recent capture sessions as shortcut rows for the export window.
- [ ] Add Export action.
- [ ] Show bundle path, zip path, row counts, export status.
- [ ] Show bundle validation, zip validation, privacy lint, and sanitized privacy statuses.
- [x] Add a manual Supabase debug upload action that creates the local data bundle, uploads bundle/manifest objects, and records a queryable metadata row.
- [x] Show Supabase debug upload states with explicit settings, object upload, manifest upload, metadata row, skipped, and failed labels instead of generic pending/ready badges.
- [x] Snapshot the app SQLite database during local data export and skip live SQLite sidecars so exported bundles contain an internally consistent database copy.
- [x] Show staged local-data export progress for database snapshot, bundle writing, validation, manifest hashing, and completion.

## Stream Probe Plan

- [x] Add a Developer route that renders the Rust command capture plan for command-gated stream discovery.
- [x] Show editable probe and baseline windows, expected packet families, ordered probe steps, safety gates, and expected evidence deltas.
- [x] Add a packet-family delta analyzer that compares baseline/probe evidence and supports optional capture-session filters.
- [x] Add a K20 optical-channel scanner that ranks channel peak-spacing candidates against nearby trusted heart-rate evidence while keeping results diagnostic-only.
- [x] Add a K20 scalar/byte-field discovery report that ranks sampled K20 fields against nearby trusted heart-rate evidence while keeping results diagnostic-only.
- [x] Add a K20 waveform transform scanner that sweeps channel, polarity, sample-rate, spacing, smoothing, and threshold parameters against nearby trusted HR and optional RR reference evidence.
- [x] Add a combined Beat Evidence Report that runs packet delta, K20 waveform/channel/field scans, and K26 field scan from one button while keeping all outputs diagnostic-only.
- [x] Add a guided RR + automatic probe action that scans/selects the reference strap, waits for live RR samples, starts the band probe, stops RR capture after the probe, and waits for RR storage before export.
- [x] Use a 15-minute automatic stream probe window so K18 historical device-time rows have enough chance to overlap an external RR reference run.
- [x] Add an advisory K18 export-readiness check that compares latest quality-gated K18 RR sample time against the probe/reference target end while still allowing export of captured evidence.
- [x] Freeze the RR reference window at automatic probe timeout, keep band capture open for K18 catch-up polling, extend the wait when readiness reports K18-specific lag/missing RR evidence, then stop the band capture once K18 is ready or the extended catch-up timeout expires.
- [x] Start the underlying band diagnostic capture with a longer fail-safe timeout than the 15-minute probe window so the app-level capture timer does not stop K18 catch-up at the same moment the reference window freezes.
- [x] Emit K18 HRV sliding-window validation tables from Rust with reference labels, K18-only decisions, explicit failure reasons, and timebase/coverage audits so the stream-probe workflow can distinguish true rest-window passes, false accepts, and row-dropout failures.
- [x] Add a K18 HRV corpus evaluator for saved validation reports so repeated stream-probe exports produce aggregate precision/recall, blocker, failure-reason, and shape-feature summaries.
- [x] Add rule-candidate scoring to the K18 HRV corpus evaluator so simple runtime-safe selectors can be rejected before they reach app HRV surfaces.
- [x] Add K18 row-context diagnostics for relaxed bounded intervals versus local current-gated medians so row-excursion rules can be evaluated before promotion.
- [x] Add a Clear Debug Data action that removes stored debug sessions, probe/capture evidence, RR reference rows, and generated export bundles from the device.
- [x] Add a storage-capped Bedtime Export lane to Stream Probe Plan that starts Overnight Guard in lean raw-spool mode, runs bounded morning historical catch-up, and exposes the scoped bundle/manifest share links for sleep-like capture validation.
- [x] Add Bedtime Export storage preflight and runtime safety stops: the lane now surfaces free-space/spool status, blocks start/export below the minimum free-space threshold, and gracefully stops collection before critical free-space or spool-cap limits can threaten the device.
- [x] Keep the route analysis-only; live device command sends remain blocked behind command validation, explicit user intent, dry-run bytes, and rollback expectations.
- [ ] Add a validated command execution flow only after command evidence and UI confirmations are ready.

## Algorithms

- [ ] Show algorithm preference picker per family.
- [ ] Add "Defaults" action from `applyRecommendedAlgorithmDefaults()`.
- [ ] Show reference benchmark details per family.
- [ ] Link to Health > Algorithms for deeper metric context.
- [ ] Keep operational setting here and metric explanation in Health.

## Debug

- [ ] Port `DebugView` as an explicit route.
- [ ] Show Rust bridge/core version.
- [ ] Show frame parse status, CRC, payload, warnings, timeline.
- [ ] Show debug WebSocket status and next action.
- [ ] Show UI coverage status and deferred surfaces.
- [ ] Show property suite and perf budget status.
- [ ] Show command evidence import/gate sweep/capture plan.
- [ ] Show command shortcuts grouped by identity, battery, historical sync, haptics, sensors, config, firmware, reboot.
- [ ] Keep destructive commands gated behind explicit confirmation.
- [x] Make the primary Debug capture action aggregate movement, HR, physiological, pulse, temperature/history, and metadata evidence so normal capture mode collects the broadest useful packet set.
- [x] Show command response names/result codes for physiology probes and include K16/K20/K17 beat-interval candidates in capture diagnostics.
- [x] Add confirmed local app data wipe that clears app storage and cached scores while preserving the remembered BLE device and never sending a wearable erase command.

## Privacy And Support

- [ ] Add Privacy route with local-data/export/privacy-lint summaries.
- [ ] Add Support route with logs/export bundle paths.
- [ ] Add About route with app version, Rust core version, and license placeholders.
- [ ] Add data deletion/export links when implemented.

## Parallel Agent Tasks

- [ ] Agent More-A: Extract More tab and build route list.
- [ ] Agent More-B: Finalize Device route and Connection Lab split.
- [ ] Agent More-C: Implement Capture route.
- [ ] Agent More-D: Implement Local Store and Health Sync.
- [ ] Agent More-E: Implement Raw Export.
- [ ] Agent More-F: Implement Algorithms settings.
- [ ] Agent More-G: Implement Debug route and command groups.
- [ ] Agent More-H: Implement Privacy, Support, About.
- [ ] Agent More-I: Add previews and simulator screenshot verification.

## Acceptance Checks

- [ ] More can be worked on without changing Home/Health/Coach code.
- [ ] Device route continues to update live BLE state.
- [ ] Every operational action is disabled unless its backing bridge exists and inputs are valid.
- [ ] Raw export and Health sync clearly show pending/unavailable states.
- [ ] Debug/destructive commands are not reachable by accidental taps.
