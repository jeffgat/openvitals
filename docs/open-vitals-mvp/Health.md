# OpenVitals Swift MVP: Health

Source map: Flutter `MetricsView`, Flutter V2 metric pages, Flutter `health_monitor_v2_page.dart`, Swift `AppShellView` Health tab.

MVP rule: Health owns metric detail, trend, algorithm, and provenance surfaces. Home can preview metrics, but Health is where users inspect why a number exists.

Current product cut 2026-06-10: the Health tab/landing is removed from the active bottom tab bar. Existing Health route views remain in code and are reached from Home where needed. Packet Inputs and Algorithms are now surfaced on Home; Calibration, Stress, Cardio Load, Energy Bank, Oxygen Saturation, and broader Health landing shortcuts are retained for possible later reintroduction. See `docs/cut-for-later.md`.

Swift evidence 2026-06-01: `HealthView.swift`, `AppRouter.swift`, `xcodebuildmcp build_sim` and `build_run_sim` passed with no warnings/errors. Simulator screenshots cover Health landing and every child route in `docs/open-vitals-mvp/evidence/health-2026-06-01/`.

## Parent View Contract

- [x] Create a dedicated `HealthView.swift` or split `PlaceholderSectionListView(title: "Health")` out of `AppShellView.swift`.
- [x] Cut this tab from the active bottom tab bar on 2026-06-10; keep route views available from Home.
- [x] Define child routes: Health Monitor, Sleep, Recovery, Strain, Stress, Cardio Load, Energy Bank, Packet Inputs, Algorithms, Reference Comparisons, Calibration.
- [x] Define a typed `HealthMetricSnapshot` model shared by cards, trend rows, and detail sheets.
- [x] Remove static runtime fixture values; show unavailable states until live/local/bridge data exists.
- [x] Support deep links or programmatic routes for every child surface.
- [x] Add previews for each major child with populated and missing data.

## Health Landing

- [ ] Cut from active navigation on 2026-06-10; keep implementation for possible later reintroduction.
- [x] Show Health Monitor as the first card.
- [x] Show metric cards for Sleep, Recovery, Strain, Stress, Cardio Load, Energy Bank.
- [x] Show latest status for each: value, unit, status, freshness, provenance.
- [x] Show Packet Inputs readiness summary.
- [x] Show Algorithms/Calibration status summary.
- [x] Group cards by "Today", "Vitals", "Training", and "Algorithms".
- [x] Cache the landing snapshot groups after refresh so packet-backed Stress/Energy summaries are not rebuilt on every SwiftUI body pass.

## Packet-Derived Inputs

- [x] Add Readiness row from `metricInputReadinessSummary()`.
- [x] Add Latest HR row from `latestHeartRateSummary()`.
- [x] Add HR provenance from `latestHeartRateProvenanceSummary()`.
- [x] Add Motion row from `motionFeatureSummary()`.
- [x] Add Motion provenance from `motionFeatureProvenanceSummary()`.
- [x] Add HRV row from `hrvFeatureSummary()`.
- [x] Add HRV provenance from `hrvFeatureProvenanceSummary()`.
- [x] Keep HRV/Recovery unavailable until packet-derived beat intervals are validated; readiness copy should describe missing beat-interval evidence rather than implying one packet family is authoritative.
- [x] Decode K18 historical RR intervals as diagnostic candidates using the observed v18 layout; keep them untrusted and out of HRV/Recovery score inputs until an owned iOS export validates them against RR reference evidence.
- [x] Add K18 sliding 5-minute HRV validation windows with H6M/reference labels, K18-only pass/fail/unknown decisions, failure reasons, and timebase/coverage audits so rest-window parity work can be measured without promoting HRV.
- [x] Add a K18 HRV corpus evaluator that aggregates saved validation reports into true accepts, false accepts, false rejects, precision/recall, failure reasons, and segment-shape medians before any HRV promotion.
- [x] Add Resting HR row from `restingHeartRateFeatureSummary()`.
- [x] Add Resting HR provenance from `restingHeartRateFeatureProvenanceSummary()`.
- [x] Add Window row from `windowFeatureSummary()`.
- [x] Add Window provenance from `windowFeatureProvenanceSummary()`.
- [x] Add Vitals row from `vitalEventFeatureSummary()`.
- [x] Add Vitals provenance from `vitalEventFeatureProvenanceSummary()`.
- [x] Add Next Action row from `packetDerivedFeatureNextActionSummary()`.
- [x] Add action to run/extract packet-derived inputs once Swift exposes the bridge.

## Packet-Derived Scores

- [x] Add Sleep score row from `sleepFeatureScoreSummary()`.
- [x] Add Sleep model row from `sleepV1ModelStatusSummary()`.
- [x] Add Sleep confidence row from `sleepV1ConfidenceSummary()`.
- [x] Add Sleep data notes row from `sleepV1DataNotesSummary()`.
- [x] Add Sleep schedule row from `sleepV1ScheduleSummary()`.
- [x] Add Sleep debt row from `sleepV1DebtSummary()`.
- [x] Add Sleep HR row from `sleepV1HeartRateSummary()`.
- [x] Add Sleep stages row from `sleepV1StagesSummary()`.
- [x] Add Sleep architecture row from `sleepV1ArchitectureCalibrationSummary()`.
- [x] Add Sleep change row from `sleepV1WhyChangedSummary()`.
- [x] Add Sleep component breakdown rows from `sleepV1ComponentBreakdownRows()`.
- [x] Use `open_vitals.sleep.v0` for packet-derived sleep scoring until the sleep v1 release gate has validated architecture/stage semantics.
- [x] Apply the 2026-06-14 score audit to sleep scoring: duration adequacy, continuity/restfulness, timing consistency, disturbance rate, latency, and diagnostic stage/autonomic fields are now reported with component scores and weights.
- [x] Add Recovery score row from `recoveryFeatureScoreSummary()`.
- [x] Add Recovery vitals row from `recoveryProvidedVitalsSummary()`.
- [x] Add editable recovery vitals inputs: respiratory rate, respiratory baseline, skin temp delta.
- [x] Apply the 2026-06-14 score audit to recovery scoring: missing secondary respiratory-rate or temperature inputs now produce partial scores with `score_status`, missing-input metadata, component coverage, and confidence instead of blocking core HRV/RHR/Sleep/Load recovery.
- [x] Add Strain score row from `strainFeatureScoreSummary()`.
- [x] Apply the 2026-06-14 score audit to strain scoring: score components are normalized to 0-100 before the 0-21 output scale, and results expose cardiovascular-only strain type, confidence, HR-zone load, top-5-minute HR reserve, missing inputs, component scores, and weights.
- [x] Run daily strain scoring against the selected local-day window and keep stale persisted strain runs out of Health/Home surfaces.
- [x] Add Stress score row from `stressFeatureScoreSummary()`.
- [x] Add provenance for sleep, recovery, strain, and stress via `packetScoreProvenanceSummary(family)`.
- [x] Add Next Action row from `packetDerivedScoreNextActionSummary()`.
- [x] Persist Sleep, Recovery, and Strain score runs to local SQLite and reload the latest reports on launch.

## Health Monitor

- [x] Port Health Monitor grid.
- [x] Include Respiratory Rate: value, rpm, normal range, trend sheet.
- [x] Include Resting HR: value, bpm, normal range, trend sheet.
- [x] Include Resting HRV: value, ms, status, trend sheet.
- [ ] Cut Oxygen Saturation from the active Health Monitor surface until packet proof is ready.
- [x] Include Wrist Temperature: value, C, status, trend sheet.
- [x] Include Sleep: duration/value, status, trend sheet.
- [x] Add Cardio Load card route.
- [x] Add Timeline and Primary Sleep child rows.
- [x] Add share/export affordance only after local data supports it.

## Sleep

- [x] Port Sleep overview hero: score, quality label, time in bed, time asleep.
- [x] Add Sleep timeline with stages and add-sleep empty/action state.
- [x] Add Primary Sleep detail: date/time, duration, score, stages.
- [x] Add Sleep insights: score impacts, locked/low-confidence states.
- [x] Add Sleep Needed / Sleep Coach: wind down, target bedtime, need fulfillment.
- [x] Add Alarm/window settings states.
- [x] Add confirmed-user WHOOP alarm controls for V5 alarm set, run-now, and disable writes.
- [x] Add trend rows: Sleep Score, Time Asleep, REM sleep, Deep Sleep, Heart Rate Dip, Sleep Bank, Sleep Time, Wake Time, Time To Fall Asleep.
- [x] Add trend sheets with range selector, chart, analysis, and resources.
- [x] Map data from sleep score output and trusted band sleep records.
- [x] Quarantine platform sleep imports as reference-only evidence; `open_vitals.sleep.v1` views must not refresh from platform sleep sessions.

## Recovery

- [x] Port Recovery overview hero: Recovery Score, recovered label, Resting HRV, Resting HR.
- [x] Add Timeline and Primary Sleep child rows.
- [x] Add insights/tags surface.
- [x] Add trend rows: Recovery Score, Resting HRV, Resting HR, Respiratory Rate, Oxygen Saturation, Wrist Temperature.
- [x] Add trend sheets with normal range bands, breakdown, analysis, and resources.
- [x] Map data from recovery score output, HRV/resting HR features, and provided vitals.
- [x] Show unavailable states for respiratory rate, oxygen saturation, or temperature when packet proof is pending.

## Strain

- [x] Port Strain overview hero: Strain Score, target strain, duration, total energy.
- [x] Add Timeline section.
- [x] Add Heart Rate Zones section.
- [x] Add trend rows: Strain Score, Exercise Duration, Daytime HR, Total Energy, Step Count.
- [x] Add trend sheets with strain breakdown, analysis, and resources.
- [x] Map data from strain score output, activity sessions, HR stream, energy, and step count.
- [x] Preserve 0-21 strain semantics while showing percent where the design expects percent.

## Stress

- [x] Port Stress overview hero: Stress score, Medium/Low/High label, Last HRV, Last HR.
- [x] Add Daily chart and timeline.
- [x] Add Stress Breakdown rows: High, Medium, Low.
- [x] Add trend rows: Stress Score, Non-Activity Stress, Sleep Stress.
- [x] Add trend sheets with breakdown, analysis, and resources.
- [x] Map data from stress score output, HRV, HR, activity masking, and sleep windows.

## Cardio Load

- [x] Port Cardio Load overview route.
- [x] Add Cardio Status Breakdown.
- [x] Add status states: Calibrating, Detraining, Maintaining, Peaking, Productive, Fatigued, Overtraining.
- [x] Add weekly chart/timeline.
- [x] Add resources: The Basics: Cardio Load, Cardio Status.
- [x] Define required inputs before showing real values.

## Energy Bank

- [x] Port Energy Bank overview.
- [x] Add Energy and Stress chart values.
- [x] Add Total Charged and Total Drained stats.
- [x] Add Energy Usage list, starting with Primary sleep contribution.
- [x] Define required inputs: stress time series, sleep contribution, activity drains, charge/drain windows.

## Algorithms And References

- [x] List algorithm definitions from `algorithmDefinitions`.
- [x] Show primary selection from `algorithmPreferences`.
- [x] Add algorithm preference picker per metric family.
- [x] List reference definitions from `referenceAlgorithmDefinitions`.
- [x] Add reference comparison rows for HRV, Sleep, Strain, Stress.
- [x] Add run action for reference comparisons after Swift bridge support.
- [x] Show pass/fail/benchmark-only policy clearly.

## Calibration

- [x] Add target family segmented control: recovery, sleep, strain, stress, hrv.
- [x] Add Import Labels action.
- [x] Add Calibrate action.
- [x] Show dataset policy: stored labels + local runs.
- [x] Show user labels count from `calibrationLabelSummary()`.
- [x] Show holdout summary from `calibrationSummary()`.
- [x] Show calibrated score from `calibratedScoreSummary()`.
- [x] Show label policy: `official_labels_are_labels`.
- [x] Show calibration issues and next action.

## Parallel Agent Tasks

- [x] Agent Health-A: Extract Health tab and build landing/card routes.
- [x] Agent Health-B: Implement Packet Inputs and Packet Scores sections.
- [x] Agent Health-C: Implement Health Monitor grid and trend sheet model.
- [x] Agent Health-D: Implement Sleep overview/trends.
- [x] Agent Health-E: Implement Recovery overview/trends.
- [x] Agent Health-F: Implement Strain and Stress overview/trends.
- [x] Agent Health-G: Implement Cardio Load and Energy Bank data contracts and unavailable states.
- [x] Agent Health-H: Implement Algorithms, References, and Calibration.
- [x] Agent Health-I: Add previews and screenshot verification for every child route.

## Acceptance Checks

- [x] Health builds independently of Home/Coach/More changes.
- [x] Every metric row has a clear data source or unavailable reason.
- [x] Every trend sheet can render no-data and populated states.
- [x] Home score cards can deep link into the matching Health child page.
- [x] Simulator screenshots cover Health landing plus Sleep, Recovery, Strain, Stress, and Health Monitor.
