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
- Learning: A 2026-06-11 K20-vs-HR validation over the aggregate diagnostic capture found K20 raw/research candidates do not align with trusted HR: direct i16 plausible values averaged ~59 bpm against ~99 bpm HR with only 2/110 matches inside 8 bpm, while peak spacing averaged ~176 bpm with 0/110 matches.
- Learning: The 2026-06-11 full local bundle shows K18 is the trusted heart-rate history reference, while K20 raw/research and K26 pulse-information are the active beat-interval search surfaces; K17/R17 is absent as a data-packet stream.
- Learning: K26 pulse-information is a better lead than K20 but still not promotable. Across the full 2026-06-10/11 bundle, K26 direct i16 candidates matched nearby trusted HR within 8 bpm in ~32% of matched frames and peak-spacing candidates in ~30%, below the 80% promotion threshold.
- Learning: A focused 2026-06-10/11 K26 byte-field scan matched all 901 K26 frames to trusted K18 HR, but no field/scale was promotable: the best variable HR-like field was offset 53 little-endian width 2 scaled by 0.2 at 121/161 within 8 bpm, the best RR-like field was offset 58 little-endian width 4 scaled by 0.5 at 57/96, and the old offset 59 big-endian RR hunch was only 370/901. Keep K26 diagnostic-only until a stronger transform or external RR reference validates it.
- Learning: K26 raw-field correlation is also not enough to justify HRV promotion. The strongest correlations in the 2026-06-10/11 bundle are tail/header-looking fields: offsets 58/59/60 correlate with HR around -0.78 but are flagged as suspected tail metadata with low-cardinality values, while the best non-tail body fields are only about 0.36. Next beat-interval discovery should prioritize K20 field scans and alternate command-gated optical/filtered streams over single-field K26.
- Learning: A quick 2026-06-10/11 K20 raw-field correlation pass also failed to reveal a clean beat-interval field. Only 664/1832 K20 frames had nearby trusted HR; the strongest simple fields were around offset 119/123 with moderate HR/RR correlation (~0.58/0.51), and the most plausible 300-2000 raw range at big-endian offset 25 correlated positively with HR rather than like an RR interval. K20 still needs structured waveform or command-context work, not direct single-field promotion.
- Learning: The 2026-06-11 realtime raw export confirms `REALTIME_RAW_DATA` decodes into K20/K21, not hidden K10/K11/K16/K17 packets. K20 has a 2,115-byte body with six repeatable 25-sample channel blocks around offsets 26, 226, 1292, 1492, 1714, and 1914; K21 is motion with six parsed 100-sample axes.
- Learning: The 2026-06-11 realtime K20/K26 validation still does not unblock HRV. Across 2,600 K20/K26 candidate frames, direct i16 plausible intervals matched nearby trusted HR in only 327/1,433 matched frames within 8 bpm, while peak spacing matched 247/1,121; K20 channel-peak scans can approximate session HR in one later window but produce noisy intervals and fail consistency across windows.
- Learning: The K20 optical-channel scan should stay diagnostic-only until validated against RR evidence. On the 2026-06-10/11 local bundle it found 1,832 K20 frames, 1,361 realtime K20 frames, 58 candidate channel segments, and 34 HR-matched segments, but the best offset-26 positive channel only matched 3/5 usable segments with 33% inside 8 bpm and ~14 bpm mean absolute error.
- Learning: A 2026-06-11 short capture window from 19:10-19:30Z produced 258 decoded frames but only `REALTIME_DATA` K2 plus one event; no K20, K21, K26, or trusted K18 appeared in that window. K20/HRV probes need diagnostic/physiology raw capture or a validated command-gated stream, not walk-mode realtime data alone.
- Learning: The 2026-06-11 automatic Stream Probe diagnostic capture worked operationally: it produced a finished `stream_probe.auto` session from 19:48:34Z to 19:59:49Z with 7,782 decoded rows, including 776 K20, 839 K21, 226 K26, and 5,205 K18 reference frames. Beat-interval candidate discovery passed with 9,963 direct RR-like values and 10,452 peak-spacing candidates, but K20 channel validation stayed diagnostic-only because the short window had only one matched HR segment and the broader day scan remained below the HR-alignment threshold.
- Learning: A longer 2026-06-11 automatic Stream Probe capture also worked: the finished 20:30:52Z-21:00:52Z `stream_probe.auto` session produced 12,147 frames, including 1,798 realtime K20 frames, 1,799 realtime K21 frames, 1,279 historical K20 frames, 120 K26 frames, and 3,141 trusted K18 HR reference frames. Beat-interval discovery found 42,979 direct RR-like values and 53,591 peak-spacing candidates, but K20 channel validation still had only one usable matched segment; the next engineering step is better channel segmentation/alignment, not just a longer capture.
- Learning: The K20 channel analyzer must time-slice long continuous streams before ranking channels. After adding two-minute validation slices, the same 2026-06-11 30-minute probe produced 177 candidate channel segments and 69 HR-matched segments; the best diagnostic candidate was K20 channel offset 226 with positive polarity, 5/6 matched slices inside 8 bpm, mean absolute error 3.9 bpm, and median candidate RR around 880 ms. This is HR-alignment evidence only and still requires an external/validated RR reference before HRV promotion.
- Learning: K20 channel scan now consumes `rr_reference_samples` when present and reports RR-reference overlap separately from trusted-HR overlap. Status `candidate_hr_aligned_needs_rr_reference` means the K20 candidate is still HR-only; status `candidate_hr_and_rr_aligned` means the candidate matched both trusted HR and stored RR-reference medians in the analysis slices, but it remains diagnostic-only until enough real-world windows are collected.
- Learning: K20 scalar/byte-field discovery is now a first-class Rust bridge/CLI report (`metrics.k20_field_discovery`, `k20-field-discovery`). It samples large K20 windows, ranks raw byte/word/dword fields against nearby trusted K18 HR, labels channel-vs-metadata regions, and keeps results diagnostic-only until overlapping RR reference samples validate beat intervals.
- Learning: Running K20 field discovery on the 2026-06-11 full local export found 5,685 K20 frames, 2,863 with nearby trusted HR, and 573 sampled frames. The strongest scalar correlations were overlapping 4-byte fields inside K20 channel 0 (offsets 53/54/61/62/81/82/97/98/105/106/109/110) at about -0.79 vs HR and +0.75 vs HR-derived RR, so the useful signal appears to be optical-channel waveform content rather than a standalone RR metadata field.
- Learning: Running the K20 optical-channel scan on the same 2026-06-11 export found 415 candidate segments and 129 HR-matched segments; K20 channel 1 at offset 226 remained the best waveform lead, but only 6/11 matched slices were inside 8 bpm and no RR reference samples existed, so it stays diagnostic-only.
- Learning: Overnight command evidence confirms realtime HR, R10/R11 realtime, IMU, persistent R21, optical data, optical mode, and persistent R20 were enabled before K20/K26 appeared; future beat-interval discovery should probe adjacent optical/filtered command variants rather than assuming sleep alone emits K17.
- Learning: K20 waveform transform scan is now a first-class Rust bridge/CLI report (`metrics.k20_waveform_transform_scan`, `k20-waveform-transform-scan`) and sweeps sample-rate, spacing, smoothing, threshold, channel, and polarity parameters. On the 2026-06-11 20:30:52Z-21:00:52Z probe it improved the best K20 lead to channel offset 226, negative polarity, 25 Hz, smoothing 5, threshold 0.65, with 6/6 HR-matched slices inside 8 bpm and mean HR error 0.6 bpm, but still no RR-reference overlap.
- Learning: Beat Evidence Report is now a combined bridge/CLI/app report (`metrics.beat_evidence_report`, `beat-evidence`) that runs packet delta, K20 waveform transform scan, K20 channel scan, K20 field discovery, and K26 field scan together. It can identify HR-aligned leads in one place while keeping HRV blocked until true RR-reference samples validate beat intervals.
- Learning: Command-gated stream discovery now belongs in the Rust command capture plan: baseline read-only optical/research config first, temporary stream toggles next, persistent R20/R21/research config last, and shutdown commands after raw stream probes. Each step should declare expected packet-family deltas before it is sent.
- Learning: The user-facing Debug Capture action should run an aggregate diagnostic capture rather than forcing users to choose between movement, physiology, and temperature probes; keep specialized modes internal for targeted experiments and overnight flows.
- Learning: A 2026-06-12 30-minute automatic Stream Probe export produced a stronger K20 waveform lead: channel offset 1292, positive polarity, 20 Hz, smoothing 5, threshold 0.85, 10/11 HR-matched slices inside 8 bpm, mean HR error 5.5 bpm, and median candidate RR around 750 ms. It still has 0 RR-reference samples, so it remains diagnostic-only and cannot feed HRV/recovery yet.
- Follow-up: Use Health patterns for provenance and unavailable states when improving Home, More, or Coach.

### More Is The Operational Home

- Context: `docs/open-vitals-mvp/More.md` assigns device, connection lab, capture, local store, health sync, raw export, algorithms, debug, privacy, and support to More.
- Learning: Low-level BLE controls, command gates, raw packets, exports, privacy lint, storage checks, and destructive actions belong in More or Debug-style routes.
- Learning: Clearing local app data is separate from forgetting a remembered BLE device; destructive wipe actions should preserve reconnect keys unless the user explicitly chooses a device-forget path.
- Learning: Remote debug uploads should reuse the explicit local data bundle, require a manual user action, use anon-key RLS/policies, and never embed a service-role key in the app.
- Learning: Remote debug upload UI needs step-specific labels for settings, object upload, manifest upload, and metadata insert; Supabase storage limits can fail before any database row exists.
- Learning: Supabase Free projects cap Storage object uploads at 50 MB globally, so large overnight debug bundles need compression or chunked upload rather than a larger bucket setting.
- Learning: Stream Probe Plan belongs in More/Developer as an analysis surface first: render the Rust capture plan, compare packet-family deltas across probe and baseline windows, and keep live command sends behind command validation.
- Learning: Packet-family deltas for data streams should classify frames from parsed payload `packet_k`; command response names are useful context, but they do not prove which data-packet family was emitted.
- Learning: The app now has a separate RR reference peripheral route under More > Developer > Stream Probe Plan. It scans for standard BLE Heart Rate Service `180D` devices, subscribes to measurement characteristic `2A37`, stores RR intervals in `rr_reference_samples`, and keeps that evidence validation-only rather than promoting it directly into user-facing HRV.
- Learning: RR reference capture must connect and subscribe to the BLE reference device before waiting on local SQLite session creation. If storage is locked or slow, RR samples should still appear live and queue for later insertion; otherwise the UI can show a selected reference device while no notifications are actually subscribed.
- Learning: Automatic Stream Probe should not immediately create the full local data bundle while RR reference capture is still flushing. The large export can compete with local SQLite/session writes and leave valid live RR samples queued but not stored; stop the probe, let RR storage finish, then run Raw Export manually.
- Learning: The RR-reference validation workflow should be a guided flow, not two independent debug tools. The normal path is: scan/select reference strap, wait for real RR samples, start the band probe, stop the reference capture after the probe, wait for stored RR samples, then let the user manually create/share the local bundle.
- Learning: Raw/local exports must snapshot SQLite with `sqlite3_backup` instead of copying the live database file directly. A 2026-06-12 local bundle included a structurally valid manifest but an embedded `open_vitals.sqlite` whose `raw_evidence` and `decoded_frames` tables failed `pragma integrity_check`; `.recover` salvaged the data, but future exports should ship a clean snapshot and skip WAL/SHM sidecars.
- Learning: Historical `GET_DATA_RANGE` can time out even when the device is still capable of sending packet bodies. Full sync should degrade to a direct packet-transfer request after bounded range retries, while range-only diagnostics should still fail loudly.
- Learning: Large local data exports need staged UI progress. Snapshotting SQLite, base64 bundle writing, validation, and final manifest hashing can each take visible time; show phase labels and determinate byte progress where possible instead of a generic spinner.
- Follow-up: Keep everyday health screens calm and move operational detail into More.

### Active UI Palette Comes From The Logo

- Context: The Home, More, and shared Health SwiftUI surfaces were redesigned around the OpenVitals logo colors.
- Learning: Active app chrome should stay in the logo-derived graphite, charcoal, bronze, gold, champagne, and ivory family; avoid reintroducing red/green/blue/purple/pink metric or status tints on everyday health and operational surfaces.
- Follow-up: Use opacity, stroke style, labels, symbols, and provenance copy to distinguish states before adding new hues.

## Validation

### Command Writes Need Multiple Gates

- Context: The Rust core has command evidence, capture plans, direct-send gates, and critical-command requirements.
- Learning: Direct BLE writes should require validated evidence, visible user intent, dry-run bytes, session logging, connected device state, and explicit critical confirmation when relevant.
- Learning: Stream probes must use the same command gates as direct writes; do not treat optical, Labrador, raw, IMU, research, or persistent stream commands as harmless debug toggles.
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
