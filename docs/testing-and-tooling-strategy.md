# Testing and Tooling Strategy

This file names the scriptable tools that gate local metric readiness, capture intake, command safety, validation labels, and developer diagnostics.

## Immediate Tool Order

1. `open-vitals-metric-input-readiness` / `metrics.input_readiness`
2. `open-vitals-capture-sqlite-import`
3. `open-vitals-command-capture-plan` / `commands.capture_plan`
4. `open-vitals-metric-feature-report motion` / `metrics.motion_features`
5. `open-vitals-metric-feature-report heart-rate` / `metrics.heart_rate_features`
6. `open-vitals-capture-arrival-plan` / `capture.arrival_plan`
7. `open-vitals-metric-feature-report vital-event` / `metrics.vital_event_features`
8. `open-vitals-metric-feature-report step-discovery` / `metrics.step_packet_discovery`
9. `open-vitals-metric-feature-report step-validation` / `metrics.step_capture_validation`
10. `open-vitals-metric-feature-report raw-motion-steps` / `metrics.raw_motion_step_estimate`
11. `open-vitals-metric-feature-report step-counter-ingest` / `metrics.step_counter_ingest`
12. `open-vitals-metric-feature-report step-rollup` / `metrics.step_counter_daily_rollup`
13. `open-vitals-metric-feature-report steps-unavailable-status` / `metrics.activity_unavailable_daily_status`
14. `open-vitals-metric-feature-report calories-unavailable-status` / `metrics.energy_unavailable_daily_status`
15. `open-vitals-metric-feature-report hrv` / `metrics.hrv_features`
16. `open-vitals-metric-feature-report hrv-validation` / `metrics.hrv_capture_validation`
17. `open-vitals-metric-feature-report respiratory-rate-validation` / `metrics.respiratory_rate_capture_validation`
18. `open-vitals-metric-feature-report recovery-sensors` / `metrics.recovery_sensor_discovery`
19. `open-vitals-metric-feature-report recovery-unavailable-status` / `metrics.recovery_unavailable_daily_status`
20. `open-vitals-metric-feature-report window` / `metrics.window_features`
21. `open-vitals-metric-feature-report resting-hr` / `metrics.resting_hr_features`
22. `open-vitals-metric-feature-report rhr-rollup` / `metrics.resting_hr_daily_rollup`
23. `open-vitals-metric-feature-report rhr-validation` / `metrics.resting_hr_capture_validation`
24. `open-vitals-local-health-validation-suite`
25. `open-vitals-debug-ws-serve`

## Score Promotion Tools

- `open-vitals-metric-feature-report sleep-score` / `metrics.sleep_score_from_features`
- `open-vitals-metric-feature-report recovery-score` / `metrics.recovery_score_from_features`
- `open-vitals-metric-feature-report strain-score` / `metrics.strain_score_from_features`
- `open-vitals-metric-feature-report stress-score` / `metrics.stress_score_from_features`

## Desktop Capture Tool

`Tools/ble-packet-debugger` is the preferred manual capture workbench when an experiment needs direct Mac-side BLE access instead of phone capture/export/import loops.

Use it for:

- Scanning and filtering nearby BLE devices by supported, near, or all.
- Connecting to compatible bands and standard Heart Rate Service straps.
- Capturing custom notify/read/write frames into local SQLite through Rust `capture.import_frame_batch`.
- Collecting standard `180D/2A37` HR/RR reference samples for validation-only comparisons.
- Running iOS-parity hello and physiology probe actions while preserving packet/write evidence.
- Checking local debugger database health with Rust `storage.check`.

Validate debugger changes with:

```sh
cd Tools/ble-packet-debugger
npm run typecheck
npm run build
```

For protocol findings, follow a desktop capture with the relevant Rust report or validation tool from the immediate order above, then export and privacy-lint any bundle before sharing it.
