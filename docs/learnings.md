# OpenVitals Learnings

This file is the running memory for durable lessons we learn while building OpenVitals. Add to it when a discovery would save a future agent or contributor from rediscovering context, constraints, tradeoffs, or validation rules.

## How To Add A Learning

Use short entries. Include the area, the context, the learning, and any follow-up.

```md
### Area: Short Title

- Context: What prompted the discovery.
- Learning: What should be remembered.
- Follow-up: What should happen next, if anything.
```

## Product And Positioning

### Public Positioning Is Brand-Neutral

- Context: The app is internally informed by reverse-engineering work for a WHOOP 5 and subscription-free personal use.
- Learning: Publicly, OpenVitals should be described as a local-first, general purpose BLE health monitor for compatible user-owned wearables. Do not mention WHOOP in user-facing copy unless the user explicitly changes the positioning.
- Follow-up: Audit new UI, README changes, release notes, screenshots, support copy, and About/Privacy surfaces for brand-neutral wording.

### This Is Personal-Use Infrastructure First

- Context: The app is being built for ourselves, friends, and family, not as a monetized competitor.
- Learning: Product choices should favor local ownership, transparent data provenance, careful health language, and practical device utility over growth, lock-in, or marketing polish.
- Follow-up: Keep privacy and export flows understandable before adding any network or AI feature.

## Data And Trust

### Missing Data Is A Real State

- Context: The existing MVP docs repeatedly require empty, stale, and unavailable states.
- Learning: OpenVitals must not invent health metrics. A metric should render only when it has live, local, bridge-derived, imported, user-entered, or explicitly stale data with provenance.
- Follow-up: When adding a surface, design its no-data state at the same time as its populated state.

### Provenance Is Product Surface, Not Debug Noise

- Context: Health, Coach, More, and the Rust core all track source, readiness, validation, and next actions.
- Learning: Provenance should stay visible enough that users and developers can tell why a number exists and what evidence is missing.
- Follow-up: Prefer typed provenance fields over summary strings when touching data models.

### Raw Evidence Is Sensitive

- Context: The Rust core includes capture sanitization, raw export, export validation, and privacy lint tooling.
- Learning: Packet payloads, captures, command evidence, logs, identifiers, HealthKit records, and labels should be treated as sensitive artifacts.
- Follow-up: Keep raw bytes in operational/debug/export flows and run privacy lint before sharing export bundles.

## Architecture

### Swift Owns UI And Device Session State

- Context: `OpenVitalsBLEClient`, `OpenVitalsAppModel`, and SwiftUI views manage Bluetooth state, app lifecycle, pipelines, and presentation.
- Learning: Swift should own user interaction, navigation, live session state, and view composition.
- Follow-up: Keep Home, Health, More, and Coach modular; avoid letting one tab depend on another tab's view internals.

### Rust Owns Protocol, Validation, Storage, And Algorithms

- Context: `Rust/core` contains parser, metric, store, export, command validation, calibration, and bridge modules.
- Learning: Packet schemas, local metric formulas, readiness gates, command validation, export validation, privacy lint, and SQLite contracts should stay in Rust when possible.
- Follow-up: Use `OpenVitalsRustBridge` to request bridge outputs instead of duplicating Rust-owned logic in Swift.

### The Bridge Is JSON-Oriented

- Context: `OpenVitalsRustBridge` sends `open_vitals.bridge.request.v1` JSON requests over the C ABI and decodes JSON responses.
- Learning: Bridge methods should be batch-oriented and return renderable values with explicit errors rather than panicking or relying on native exceptions.
- Learning: Batched bridge summaries need the same typed arg shape as their single-method equivalents; passing unavailable-status args into a rollup slot can make Swift persist/render unavailable rows even when promotable metric values exist.
- Follow-up: When adding a bridge method, update Rust tests, Swift call sites, and docs together.

### High-Volume Sync Must Batch UI Work

- Context: Band historical sleep sync can deliver many packet notifications before the final metadata arrives.
- Learning: Pure historical data packets should be coalesced before touching main-thread `@Published` state, and bridge-backed score recomputation should run off the main actor.
- Follow-up: When adding packet-stream features, batch status updates and keep Rust bridge calls on a background queue unless the method is known to be trivial.

### Hot Paths Need Bounded Work

- Context: Sleep sync, packet inputs, diagnostic logging, and live HR/HRV sampling can all run while the UI is visible.
- Learning: Hot paths should avoid whole-database scans, repeated bridge round trips, immediate file synchronization, and whole-file JSON rewrites. Prefer bounded windows, batched bridge responses, buffered writes, and append-oriented persistence.
- Learning: Rolling packet-capture summaries and routine bridge timing breadcrumbs should update lightweight status state or snapshot files, not the displayed event log, OSLog, console stream, diagnostic file log, or overnight event spool.
- Learning: Long-running automatic passive captures should not persist at the same cadence as explicit debug captures or active activities; sample passive evidence and coalesce SQLite/Rust bridge imports so UI navigation stays responsive while live parsing continues.
- Learning: SwiftUI dashboard bodies should compute packet-backed snapshot bundles once per render and pass the results down; repeatedly calling `landingSnapshots`, `healthMonitorSnapshots`, or stress/energy summaries from multiple card sections can multiply main-thread work after a Health refresh.
- Learning: Repeated iOS "System gesture gate timed out" console lines after a Health refresh are strong evidence that SwiftUI/main-actor work is starving touch handling; cache packet-backed landing summaries and keep live packet ingestion off render paths before chasing BLE reconnect logic.
- Follow-up: When adding live packet or diagnostic features, define the time window, batching cadence, and persistence strategy before wiring UI refreshes.

## Current Surface Map

### Tabs Are Uneven By Design Right Now

- Context: `AppShellView` defines Home, Health, Coach, and More, but `bottomTabs` currently includes Home, Health, and More while Coach is commented out.
- Learning: Coach code exists, but the user-facing tab shell does not currently expose it as a bottom tab.
- Follow-up: If Coach is re-enabled, check privacy, deterministic recommendation boundaries, and routing before exposing free-form chat behavior.

### Health Is The Most Complete MVP Surface

- Context: `docs/open-vitals-mvp/Health.md` is mostly checked off and references screenshot evidence from 2026-06-01.
- Learning: Health has the strongest implemented contract for metric details, trends, packet inputs, algorithms, references, and calibration.
- Learning: Health refresh should expose packet-input and packet-score bridge status together; otherwise a completed input run can still leave Sleep/Recovery/Strain cards looking unchanged until score recomputation runs.
- Learning: Sleep, Recovery, and Strain cards should reload the latest persisted algorithm runs on launch so restart does not turn previously computed scores into unavailable states.
- Learning: The Home daily-score Sync button should request band historical packets first, then run packet input extraction and packet-score recomputation; Sleep, Recovery, and Strain all depend on packet-derived inputs even though Sleep exposes the most obvious manual sync entry.
- Learning: Historical sync packet counts are not enough for metric readiness; Home score sync needs an active local capture/import session so received historical frames are persisted into SQLite before packet inputs and scores run.
- Learning: A 2026-06-11 manual local bundle had enough motion/window evidence for `open_vitals.sleep.v0`, while `open_vitals.sleep.v1` stayed blocked by its release-gate semantics; Swift should request sleep v0 until v1 is promoted.
- Learning: A 2026-06-11 still physiology capture produced K20/K21/K18/K2 frames but zero K17/R17 frames; a later bundle showed the Labrador data-generation/raw-save/filtered toggles were attempted but returned result code 0 and still produced no trusted beat-interval evidence.
- Learning: HRV readiness should talk about validated beat-interval evidence, not a single guessed packet family; K17 remains one candidate, while K16/raw ECG and K20/raw research bodies need discovery scans before any HRV promotion.
- Learning: The user-facing Debug Capture action should run an aggregate diagnostic capture rather than forcing users to choose between movement, physiology, and temperature probes; keep specialized modes internal for targeted experiments and overnight flows.
- Follow-up: Use Health patterns for provenance and unavailable states when improving Home, More, or Coach.

### More Is The Operational Home

- Context: `docs/open-vitals-mvp/More.md` assigns device, connection lab, capture, local store, health sync, raw export, algorithms, debug, privacy, and support to More.
- Learning: Low-level BLE controls, command gates, raw packets, exports, privacy lint, storage checks, and destructive actions belong in More or Debug-style routes.
- Learning: Clearing local app data is separate from forgetting a remembered BLE device; destructive wipe actions should preserve reconnect keys unless the user explicitly chooses a device-forget path.
- Learning: Remote debug uploads should reuse the explicit local data bundle, require a manual user action, use anon-key RLS/policies, and never embed a service-role key in the app.
- Learning: Remote debug upload UI needs step-specific labels for settings, object upload, manifest upload, and metadata insert; Supabase storage limits can fail before any database row exists.
- Learning: Supabase Free projects cap Storage object uploads at 50 MB globally, so large overnight debug bundles need compression or chunked upload rather than a larger bucket setting.
- Follow-up: Keep everyday health screens calm and move operational detail into More.

### Active UI Palette Comes From The Logo

- Context: The Home, More, and shared Health SwiftUI surfaces were redesigned around the OpenVitals logo colors.
- Learning: Active app chrome should stay in the logo-derived graphite, charcoal, bronze, gold, champagne, and ivory family; avoid reintroducing red/green/blue/purple/pink metric or status tints on everyday health and operational surfaces.
- Follow-up: Use opacity, stroke style, labels, symbols, and provenance copy to distinguish states before adding new hues.

## Validation

### Command Writes Need Multiple Gates

- Context: The Rust core has command evidence, capture plans, direct-send gates, and critical-command requirements.
- Learning: Direct BLE writes should require validated evidence, visible user intent, dry-run bytes, session logging, connected device state, and explicit critical confirmation when relevant.
- Follow-up: Never expose a new direct command button as a casual tap before the Rust gate and UI confirmation path exist.

### Health Sync Needs Semantic Guards

- Context: The Rust health sync dry-run includes permission, unit, idempotency, provenance, backfill, cleanup, and HRV semantic checks.
- Learning: Platform health writes should be dry-run validated first, and RMSSD HRV should not be written into incompatible HealthKit fields.
- Follow-up: Keep HealthKit integration behind explicit authorization and dry-run/reporting surfaces until the mapping is proven.

### Build And Test Expectations Depend On What Changed

- Context: The README asks contributors to build after touching Swift, Rust bridge, project, or signing settings.
- Learning: Docs-only changes do not require an app build, but Swift/Rust/bridge changes should be verified with Xcode and/or `cargo test` as appropriate.
- Follow-up: In final notes, state which checks ran and which were skipped.

### Xcode GUI Builds Need Rust On Script PATH

- Context: GUI-launched Xcode can run the `Build Rust Core` phase without the user's login-shell `PATH`.
- Learning: `Scripts/build_ios_rust.sh` must make common Rust install locations such as `~/.cargo/bin` visible before invoking Cargo, or Xcode reports `cargo: command not found`.
- Follow-up: If a future phase script invokes developer tools installed outside Xcode, add explicit path discovery and a clear missing-tool error.
