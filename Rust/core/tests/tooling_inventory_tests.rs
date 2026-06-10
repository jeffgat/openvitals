use std::path::Path;

const REQUIRED_CLI_BINS: &[&str] = &[
    "open-vitals-fixture-index",
    "open-vitals-capture-sanitize",
    "open-vitals-capture-sqlite-import",
    "open-vitals-parser-fixture-runner",
    "open-vitals-capture-correlation",
    "open-vitals-metric-input-readiness",
    "open-vitals-capture-arrival-plan",
    "open-vitals-command-capture-plan",
    "open-vitals-metric-feature-report",
    "open-vitals-local-health-validation-suite",
    "open-vitals-command-validator",
    "open-vitals-export-validator",
    "open-vitals-reference-algo-runner",
    "open-vitals-algo-benchmark",
    "open-vitals-calibration-evaluator",
    "open-vitals-health-sync-dry-run",
    "open-vitals-debug-ws-contract",
    "open-vitals-debug-ws-serve",
    "open-vitals-ui-coverage-audit",
    "open-vitals-storage-check",
    "open-vitals-property-test-suite",
    "open-vitals-perf-budget",
    "open-vitals-privacy-lint",
];

const REQUIRED_DOC_ENTRIES: &[&str] = &[
    "`open-vitals-metric-input-readiness` / `metrics.input_readiness`",
    "`open-vitals-capture-arrival-plan` / `capture.arrival_plan`",
    "`open-vitals-command-capture-plan` / `commands.capture_plan`",
    "`open-vitals-capture-sqlite-import`",
    "`open-vitals-metric-feature-report motion` / `metrics.motion_features`",
    "`open-vitals-metric-feature-report heart-rate` / `metrics.heart_rate_features`",
    "`open-vitals-metric-feature-report vital-event` / `metrics.vital_event_features`",
    "`open-vitals-metric-feature-report step-discovery` / `metrics.step_packet_discovery`",
    "`open-vitals-metric-feature-report step-validation` / `metrics.step_capture_validation`",
    "`open-vitals-metric-feature-report raw-motion-steps` / `metrics.raw_motion_step_estimate`",
    "`open-vitals-metric-feature-report step-counter-ingest` / `metrics.step_counter_ingest`",
    "`open-vitals-metric-feature-report step-rollup` / `metrics.step_counter_daily_rollup`",
    "`open-vitals-metric-feature-report steps-unavailable-status` / `metrics.activity_unavailable_daily_status`",
    "`open-vitals-metric-feature-report calories-unavailable-status` / `metrics.energy_unavailable_daily_status`",
    "`open-vitals-metric-feature-report hrv` / `metrics.hrv_features`",
    "`open-vitals-metric-feature-report hrv-validation` / `metrics.hrv_capture_validation`",
    "`open-vitals-metric-feature-report respiratory-rate-validation` / `metrics.respiratory_rate_capture_validation`",
    "`open-vitals-metric-feature-report recovery-sensors` / `metrics.recovery_sensor_discovery`",
    "`open-vitals-metric-feature-report recovery-unavailable-status` / `metrics.recovery_unavailable_daily_status`",
    "`open-vitals-metric-feature-report window` / `metrics.window_features`",
    "`open-vitals-metric-feature-report resting-hr` / `metrics.resting_hr_features`",
    "`open-vitals-metric-feature-report rhr-rollup` / `metrics.resting_hr_daily_rollup`",
    "`open-vitals-metric-feature-report rhr-validation` / `metrics.resting_hr_capture_validation`",
    "`open-vitals-metric-feature-report sleep-score` / `metrics.sleep_score_from_features`",
    "`open-vitals-metric-feature-report recovery-score` / `metrics.recovery_score_from_features`",
    "`open-vitals-metric-feature-report strain-score` / `metrics.strain_score_from_features`",
    "`open-vitals-metric-feature-report stress-score` / `metrics.stress_score_from_features`",
    "`open-vitals-local-health-validation-suite`",
];

#[test]
fn required_machine_readable_tools_are_registered_as_cargo_bins() {
    let manifest = read_workspace_file("Cargo.toml");
    for bin in REQUIRED_CLI_BINS {
        assert!(
            manifest.contains(&format!("name = \"{bin}\"")),
            "Cargo.toml missing required OpenVitals tool bin {bin}"
        );
        assert!(
            manifest.contains(&format!("path = \"src/bin/{bin}.rs\"")),
            "Cargo.toml missing expected path for OpenVitals tool bin {bin}"
        );
    }
}

#[test]
fn testing_strategy_names_scriptable_tools_for_bridge_gates() {
    let strategy = read_open_vitals_file("docs/testing-and-tooling-strategy.md");
    for entry in REQUIRED_DOC_ENTRIES {
        assert!(
            strategy.contains(entry),
            "testing strategy missing scriptable tooling entry {entry}"
        );
    }
    assert!(
        strategy.contains("6. `open-vitals-capture-arrival-plan` / `capture.arrival_plan`"),
        "Immediate Tool Order should name the standalone capture arrival plan CLI"
    );
    assert!(
        strategy.contains("25. `open-vitals-debug-ws-serve`"),
        "Immediate Tool Order should include the debug WebSocket serve tool"
    );
}

fn read_workspace_file(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("cannot read {path:?}: {error}"))
}

fn read_open_vitals_file(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("cannot read {path:?}: {error}"))
}
