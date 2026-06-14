use open_vitals_core::{
    capture_import::{CapturedFrameBatchOptions, CapturedFrameInput, import_captured_frame_batch},
    protocol::{
        DeviceType, PACKET_TYPE_HISTORICAL_DATA, PACKET_TYPE_REALTIME_RAW_DATA,
        build_v5_payload_frame,
    },
    store::{CaptureSessionInput, OpenVitalsStore, RrReferenceSampleInput},
};
use std::process::Output;

#[test]
fn metric_feature_report_cli_builds_motion_report_from_owned_capture() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_motion_frame(&store);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("motion")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-05-30T00:00:00Z")
            .arg("--end")
            .arg("2026-05-31T00:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema"], "open_vitals.motion-feature-report.v1");
    assert_eq!(
        report["generated_by"],
        "open-vitals-motion-feature-extractor"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["feature_count"], 1);
    assert_eq!(report["trusted_feature_count"], 1);
    assert_eq!(report["features"][0]["body_summary_kind"], "raw_motion_k10");
    assert_eq!(report["features"][0]["trusted_metric_input"], true);
}

#[test]
fn metric_feature_report_cli_emits_heart_rate_blockers_without_trusted_evidence() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("heart-rate")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-05-30T00:00:00Z")
            .arg("--end")
            .arg("2026-05-31T00:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema"], "open_vitals.heart-rate-feature-report.v1");
    assert_eq!(report["pass"], false);
    assert_eq!(report["feature_count"], 0);
    assert_eq!(report["trusted_feature_count"], 0);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_trusted_heart_rate_features")
    );
    assert!(
        report["next_actions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|action| action["reason"] == "no_trusted_heart_rate_features")
    );
}

#[test]
fn metric_feature_report_cli_runs_step_packet_discovery_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("step-discovery")
            .arg("--database")
            .arg(&db)
            .arg("--start-time-unix-ms")
            .arg("1780355200000")
            .arg("--end-time-unix-ms")
            .arg("1780441600000")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.step-packet-discovery-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["decoded_frame_count"], 0);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_step_discovery_frames")
    );
}

#[test]
fn metric_feature_report_cli_runs_step_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("step-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start-time-unix-ms")
            .arg("1780355200000")
            .arg("--end-time-unix-ms")
            .arg("1780441600000")
            .arg("--capture-kind")
            .arg("100_counted_steps")
            .arg("--manual-step-delta")
            .arg("100")
            .arg("--official-whoop-step-delta")
            .arg("97")
            .arg("--step-delta-tolerance")
            .arg("5")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.step-capture-validation-report.v1"
    );
    assert_eq!(report["capture_kind"], "100_counted_steps");
    assert_eq!(report["manual_step_delta"], 100);
    assert_eq!(report["official_whoop_step_delta"], 97);
    assert_eq!(report["tolerance_steps"], 5);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_explicit_step_counter_field_found")
    );
}

#[test]
fn metric_feature_report_cli_runs_raw_motion_step_estimate_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("raw-motion-steps")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--manual-step-delta")
            .arg("100")
            .arg("--step-delta-tolerance")
            .arg("10")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.raw-motion-step-estimate-report.v1"
    );
    assert_eq!(
        report["algorithm_id"],
        "open_vitals.steps.raw_motion_estimate.v0"
    );
    assert_eq!(report["source_kind_if_promoted"], "local_estimate");
    assert_eq!(report["manual_step_delta"], 100);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_raw_motion_step_estimator_frames")
    );
}

#[test]
fn metric_feature_report_cli_runs_step_counter_ingest_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("step-counter-ingest")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.step-counter-ingest-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_step_counter_candidates_to_persist")
    );
}

#[test]
fn metric_feature_report_cli_runs_step_counter_daily_rollup_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("step-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start-time-unix-ms")
            .arg("1780355200000")
            .arg("--end-time-unix-ms")
            .arg("1780441600000")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.step-counter-daily-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["daily_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "insufficient_step_counter_samples")
    );
}

#[test]
fn metric_feature_report_cli_runs_step_counter_hourly_rollup_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("hourly-step-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start-time-unix-ms")
            .arg("1780387200000")
            .arg("--end-time-unix-ms")
            .arg("1780390800000")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.step-counter-hourly-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["hourly_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "insufficient_step_counter_samples")
    );
}

#[test]
fn metric_feature_report_cli_runs_activity_unavailable_status_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("steps-unavailable-status")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start-time-unix-ms")
            .arg("1780355200000")
            .arg("--end-time-unix-ms")
            .arg("1780441600000")
            .arg("--min-step-samples")
            .arg("2")
            .arg("--write-metric")
            .output()
            .unwrap();

    assert!(output.status.success(), "{output:?}");
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.activity-unavailable-daily-status-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["unavailable_metric_count"], 1);
    assert_eq!(report["written_metric_count"], 1);
    assert_eq!(report["statuses"][0]["metric_id"], "steps");
    assert_eq!(report["statuses"][0]["source_kind"], "unavailable");

    let store = OpenVitalsStore::open(&db).unwrap();
    assert_eq!(
        store
            .daily_activity_metrics_between(0, i64::MAX)
            .unwrap()
            .into_iter()
            .filter(|row| row.source_kind == "unavailable")
            .count(),
        1
    );
}

#[test]
fn metric_feature_report_cli_runs_resting_heart_rate_daily_rollup_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("rhr-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--min-samples")
            .arg("2")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.resting-heart-rate-daily-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["daily_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "insufficient_heart_rate_samples")
    );
}

#[test]
fn metric_feature_report_cli_runs_resting_heart_rate_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("rhr-validation")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--min-samples")
            .arg("2")
            .arg("--official-whoop-resting-hr-bpm")
            .arg("56")
            .arg("--rhr-tolerance-bpm")
            .arg("3")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.resting-heart-rate-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["official_whoop_resting_hr_bpm"], 56.0);
    assert_eq!(report["resting_hr_rollup"]["daily_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "official_label_provenance_missing")
    );
}

#[test]
fn metric_feature_report_cli_runs_energy_daily_rollup_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("energy-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--profile-weight-kg")
            .arg("80")
            .arg("--resting-hr-bpm")
            .arg("60")
            .arg("--max-hr-bpm")
            .arg("180")
            .arg("--min-heart-rate-samples")
            .arg("2")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.energy-daily-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["daily_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "insufficient_heart_rate_samples")
    );
}

#[test]
fn metric_feature_report_cli_runs_energy_unavailable_status_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("calories-unavailable-status")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--profile-weight-kg")
            .arg("80")
            .arg("--resting-hr-bpm")
            .arg("60")
            .arg("--max-hr-bpm")
            .arg("180")
            .arg("--min-heart-rate-samples")
            .arg("2")
            .arg("--write-metric")
            .output()
            .unwrap();

    assert!(output.status.success(), "{output:?}");
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.energy-unavailable-daily-status-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["unavailable_metric_count"], 3);
    assert_eq!(report["written_metric_count"], 3);
    assert!(
        report["statuses"]
            .as_array()
            .unwrap()
            .iter()
            .any(|status| status["metric_id"] == "active_kcal"
                && status["source_kind"] == "unavailable")
    );

    let store = OpenVitalsStore::open(&db).unwrap();
    assert_eq!(
        store
            .daily_activity_metrics_between(0, i64::MAX)
            .unwrap()
            .into_iter()
            .filter(|row| row.source_kind == "unavailable")
            .count(),
        3
    );
}

#[test]
fn metric_feature_report_cli_runs_energy_hourly_rollup_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("hourly-energy-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T12:00:00Z")
            .arg("--end")
            .arg("2026-06-02T13:00:00Z")
            .arg("--profile-weight-kg")
            .arg("80")
            .arg("--resting-hr-bpm")
            .arg("60")
            .arg("--max-hr-bpm")
            .arg("180")
            .arg("--min-heart-rate-samples")
            .arg("2")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.energy-hourly-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["hourly_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "insufficient_heart_rate_samples")
    );
}

#[test]
fn metric_feature_report_cli_runs_energy_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("energy-validation")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--official-whoop-total-kcal")
            .arg("2100")
            .arg("--energy-tolerance-kcal")
            .arg("250")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.energy-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["official_whoop_total_kcal"], 2100.0);
    assert_eq!(report["energy_rollup"]["daily_metric_written"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "energy_rollup_blocked")
    );
}

#[test]
fn metric_feature_report_cli_merges_extra_json_args_for_hrv_options() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
        .arg("--method")
        .arg("hrv")
        .arg("--database")
        .arg(&db)
        .arg("--start")
        .arg("2026-05-30T00:00:00Z")
        .arg("--end")
        .arg("2026-05-31T00:00:00Z")
        .arg("--require-trusted-evidence")
        .arg("--args-json")
        .arg(r#"{"min_owned_captures":1,"min_rr_intervals_to_compute":4,"require_baseline":true,"baseline_min_days":2}"#)
        .output()
        .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema"], "open_vitals.hrv-feature-report.v1");
    assert_eq!(report["pass"], false);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_trusted_hrv_features")
    );
    assert!(
        report["next_actions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|action| action["reason"] == "no_trusted_hrv_features")
    );
}

#[test]
fn metric_feature_report_cli_runs_k26_field_scan_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k26-field-scan")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-frames")
            .arg("2")
            .arg("--max-ranked-candidates")
            .arg("4")
            .arg("--max-frame-summaries")
            .arg("2")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k26-beat-field-scan-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["validation_status"], "blocked");
    assert_eq!(report["k26_frame_count"], 0);
    assert_eq!(report["matched_k26_frame_count"], 0);
    assert_eq!(
        report["raw_field_correlations"].as_array().unwrap().len(),
        0
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_k26_candidate_frames")
    );
}

#[test]
fn metric_feature_report_cli_runs_k20_optical_channel_scan_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-channel-scan")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-segments")
            .arg("1")
            .arg("--max-ranked-channels")
            .arg("4")
            .arg("--max-segment-summaries")
            .arg("4")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k20-optical-channel-scan-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(
        report["validation_status"],
        "candidate_hr_aligned_needs_rr_reference"
    );
    assert_eq!(report["k20_frame_count"], 12);
    assert_eq!(report["realtime_k20_frame_count"], 12);
    assert_eq!(report["rr_reference_sample_count"], 0);
    assert_eq!(report["rr_reference_matched_segment_count"], 0);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_rr_reference_samples")
    );
    let best = &report["ranked_channels"].as_array().unwrap()[0];
    assert_eq!(best["offset"], 26);
    assert_eq!(best["within_tolerance_fraction"], 1.0);
    assert_eq!(best["rr_reference_matched_segment_count"], 0);
}

#[test]
fn metric_feature_report_cli_runs_k20_field_discovery_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_field_discovery_sequence_with_hr_reference(&store, 16);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-field-discovery")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-frames")
            .arg("8")
            .arg("--max-ranked-fields")
            .arg("20")
            .arg("--max-frame-summaries")
            .arg("4")
            .arg("--max-analyzed-frames")
            .arg("16")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k20-field-discovery-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "field_candidates_ranked");
    assert_eq!(report["k20_frame_count"], 16);
    assert_eq!(report["matched_k20_frame_count"], 16);
    assert_eq!(report["analyzed_k20_frame_count"], 16);

    let ranked_fields = report["ranked_fields"].as_array().unwrap();
    assert!(ranked_fields.iter().any(|field| {
        field["offset"] == 180
            && field["width"] == 1
            && field["pearson_correlation_to_hr_bpm"]
                .as_f64()
                .is_some_and(|correlation| correlation >= 0.99)
    }));
    assert!(
        report["next_actions"]
            .as_array()
            .unwrap()
            .iter()
            .any(|action| action["reason"] == "field_candidates_are_not_rr_validation")
    );
}

#[test]
fn metric_feature_report_cli_runs_k20_waveform_transform_scan_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);
    import_rr_reference_sequence(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-waveform-transform-scan")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-segments")
            .arg("1")
            .arg("--max-ranked-transforms")
            .arg("6")
            .arg("--max-segment-summaries")
            .arg("4")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k20-waveform-transform-scan-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "candidate_hr_and_rr_aligned");
    assert_eq!(report["k20_frame_count"], 12);
    assert_eq!(report["rr_reference_sample_count"], 12);
    let best = &report["ranked_transforms"].as_array().unwrap()[0];
    assert_eq!(best["offset"], 26);
    assert_eq!(best["sample_rate_hz"], 25.0);
    assert_eq!(best["within_tolerance_fraction"], 1.0);
    assert_eq!(best["rr_reference_within_tolerance_fraction"], 1.0);
}

#[test]
fn metric_feature_report_cli_runs_k20_rr_sequence_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);
    import_rr_reference_sequence(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-rr-sequence-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--args-json")
            .arg(
                r#"{"sample_rate_hz_values":[25],"min_peak_spacing_samples_values":[6],"smoothing_window_samples_values":[5],"threshold_stddev_multipliers":[0.25,0.35,0.45],"max_clock_offset_ms":1000,"clock_offset_step_ms":40,"beat_match_tolerance_ms":120,"rmssd_tolerance_ms":20,"min_reference_beats":8,"min_matched_beats":8,"min_match_fraction":0.8,"max_ranked_sequences":4,"max_segment_summaries":2,"max_match_preview":4}"#,
            )
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k20-rr-sequence-validation-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "candidate_sequence_validated");
    assert_eq!(report["k20_frame_count"], 12);
    assert_eq!(report["rr_reference_sample_count"], 12);
    assert_eq!(report["reconstructed_reference_beat_count"], 12);
    let best = &report["ranked_sequences"].as_array().unwrap()[0];
    assert_eq!(best["offset"], 26);
    assert_eq!(best["sample_rate_hz"], 25.0);
    assert_eq!(best["matched_beat_count"], 12);
    assert_eq!(best["match_fraction"], 1.0);
    assert_eq!(best["precision_fraction"], 1.0);
    assert_eq!(best["rmssd_absolute_error_ms"], 0.0);
}

#[test]
fn metric_feature_report_cli_runs_k18_hrv_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k18_rr_validation_sequence(&store, 20);
    import_rr_reference_sequence(&store, 20);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k18-hrv-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-k18-intervals")
            .arg("20")
            .arg("--min-reference-intervals")
            .arg("20")
            .arg("--rmssd-tolerance-ms")
            .arg("1")
            .arg("--sdnn-tolerance-ms")
            .arg("1")
            .arg("--mean-nn-tolerance-ms")
            .arg("1")
            .arg("--binned-mae-tolerance-ms")
            .arg("1")
            .arg("--min-binned-correlation")
            .arg("0")
            .arg("--bin-seconds")
            .arg("2")
            .arg("--max-frame-summaries")
            .arg("4")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema"], "open_vitals.k18-hrv-validation-report.v1");
    assert_eq!(report["pass"], true);
    assert_eq!(
        report["validation_status"],
        "candidate_k18_hrv_validated_repeat_required"
    );
    assert_eq!(report["gated_interval_count"], 20);
    assert_eq!(report["rr_reference_overlap_count"], 20);
    assert_eq!(report["rmssd_error_ms"], 0.0);
    assert_eq!(
        report["promotion_status"],
        "validation_only_repeat_required"
    );
}

#[test]
fn metric_feature_report_cli_runs_k20_peak_inspection_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);
    import_rr_reference_sequence(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-peak-inspection")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--args-json")
            .arg(
                r#"{"channel_offset":26,"sample_rate_hz":25,"min_peak_spacing_samples":6,"polarity":"positive","smoothing_window_samples":5,"threshold_stddev_multiplier":0.25,"clock_offset_ms":-320,"beat_match_tolerance_ms":80,"window_radius_ms":500,"max_events":4,"max_segments":2}"#,
            )
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k20-peak-inspection-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "inspection_ready");
    assert_eq!(report["offset"], 26);
    assert_eq!(report["matched_beat_count"], 12);
    assert_eq!(report["missed_reference_beat_count"], 0);
    assert_eq!(report["extra_candidate_peak_count"], 0);
    assert_eq!(report["match_fraction"], 1.0);
    assert_eq!(report["precision_fraction"], 1.0);
    assert_eq!(
        report["discrimination_summary"]["recommended_filter_family"],
        "event_review"
    );
    assert_eq!(
        report["discrimination_summary"]["threshold_prominence_separation"],
        "insufficient_candidates"
    );
    assert_eq!(report["filter_summaries"].as_array().unwrap().len(), 19);
    assert_eq!(
        report["filter_summaries"][0]["strategy"],
        "score_refractory_450ms"
    );
    assert_eq!(report["filter_summaries"][0]["runtime_eligible"], true);
    assert_eq!(
        report["filter_summaries"][4]["strategy"],
        "hr_expected_window_120ms"
    );
    assert_eq!(report["filter_summaries"][4]["runtime_eligible"], true);
    assert_eq!(
        report["filter_summaries"][7]["strategy"],
        "self_period_window_120ms"
    );
    assert_eq!(report["filter_summaries"][7]["runtime_eligible"], true);
    assert_eq!(
        report["filter_summaries"][10]["strategy"],
        "ordinal_phase_stride2_phase0"
    );
    assert_eq!(report["filter_summaries"][10]["runtime_eligible"], true);
    assert_eq!(
        report["filter_summaries"][13]["strategy"],
        "multi_channel_consensus_min2_80ms_refractory450ms"
    );
    assert_eq!(report["filter_summaries"][13]["runtime_eligible"], true);
    assert_eq!(
        report["filter_summaries"][16]["strategy"],
        "hr_expected_window_reference_phase_upper_bound"
    );
    assert_eq!(report["filter_summaries"][16]["runtime_eligible"], false);
    assert_eq!(
        report["filter_summaries"][17]["strategy"],
        "reference_window_upper_bound_80ms"
    );
    assert_eq!(report["filter_summaries"][17]["runtime_eligible"], false);
    assert_eq!(report["sequence_summaries"].as_array().unwrap().len(), 3);
    assert_eq!(
        report["sequence_summaries"][0]["strategy"],
        "reference_dedup_nearest_200ms"
    );
    assert_eq!(report["sequence_summaries"][0]["runtime_eligible"], false);
    assert_eq!(
        report["sequence_summaries"][1]["strategy"],
        "reference_interval_viterbi_500ms"
    );
    assert_eq!(report["sequence_summaries"][1]["runtime_eligible"], false);
    assert_eq!(
        report["sequence_summaries"][2]["strategy"],
        "fitted_reference_interval_viterbi_offset_sweep"
    );
    assert_eq!(report["sequence_summaries"][2]["runtime_eligible"], false);
    assert_eq!(report["events"].as_array().unwrap().len(), 4);
    assert_eq!(report["events"][0]["kind"], "matched");
    assert_eq!(report["events"][0]["error_ms"], 0.0);
}

#[test]
fn metric_feature_report_cli_runs_beat_evidence_report_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);
    import_rr_reference_sequence(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("beat-evidence")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-segments")
            .arg("1")
            .arg("--min-matching-frames")
            .arg("1")
            .arg("--max-ranked-transforms")
            .arg("6")
            .arg("--max-ranked-channels")
            .arg("4")
            .arg("--max-ranked-fields")
            .arg("4")
            .arg("--max-ranked-candidates")
            .arg("4")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["schema"], "open_vitals.beat-evidence-report.v1");
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "candidate_hr_and_rr_aligned");
    assert_eq!(report["rr_reference_sample_count"], 12);
    assert_eq!(
        report["k20_waveform_transform_scan"]["schema"],
        "open_vitals.k20-waveform-transform-scan-report.v1"
    );
    assert_eq!(report["summary"]["best_waveform_transform"]["offset"], 26);
}

#[test]
fn metric_feature_report_cli_compares_k20_channel_scan_to_rr_reference() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 12);
    import_rr_reference_sequence(&store, 12);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-channel-scan")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:01:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-segments")
            .arg("1")
            .arg("--max-ranked-channels")
            .arg("4")
            .arg("--max-segment-summaries")
            .arg("4")
            .output()
            .unwrap();

    assert_success(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["pass"], true);
    assert_eq!(report["validation_status"], "candidate_hr_and_rr_aligned");
    assert_eq!(report["rr_reference_sample_count"], 12);
    assert_eq!(report["rr_reference_matched_segment_count"], 1);
    let best = &report["ranked_channels"].as_array().unwrap()[0];
    assert_eq!(best["offset"], 26);
    assert_eq!(best["within_tolerance_fraction"], 1.0);
    assert_eq!(best["rr_reference_matched_segment_count"], 1);
    assert_eq!(best["rr_reference_within_tolerance_fraction"], 1.0);
    assert_eq!(best["mean_absolute_error_rr_ms"], 0.0);
}

#[test]
fn metric_feature_report_cli_splits_long_k20_channel_scan_into_time_slices() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");
    let store = OpenVitalsStore::open(&db).unwrap();
    import_k20_optical_sequence_with_hr_reference(&store, 260);

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("k20-channel-scan")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-11T12:00:00Z")
            .arg("--end")
            .arg("2026-06-11T12:05:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--min-matching-segments")
            .arg("2")
            .arg("--max-ranked-channels")
            .arg("4")
            .arg("--max-segment-summaries")
            .arg("8")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["pass"], false);
    assert_eq!(
        report["validation_status"],
        "candidate_hr_aligned_needs_rr_reference"
    );
    assert!(report["candidate_segment_count"].as_u64().unwrap() >= 2);
    assert!(report["matched_segment_count"].as_u64().unwrap() >= 2);
    assert_eq!(report["rr_reference_sample_count"], 0);
    assert_eq!(report["rr_reference_matched_segment_count"], 0);
    let best = &report["ranked_channels"].as_array().unwrap()[0];
    assert_eq!(best["offset"], 26);
    assert!(best["matched_segment_count"].as_u64().unwrap() >= 2);
    assert_eq!(best["within_tolerance_fraction"], 1.0);
    assert_eq!(best["rr_reference_matched_segment_count"], 0);
}

#[test]
fn metric_feature_report_cli_runs_hrv_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("hrv-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--capture-kind")
            .arg("overnight_rest")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--min-rr-intervals-to-compute")
            .arg("2")
            .arg("--official-whoop-hrv-rmssd-ms")
            .arg("42")
            .arg("--hrv-tolerance-ms")
            .arg("10")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.hrv-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["capture_kind"], "overnight_rest");
    assert_eq!(report["official_whoop_hrv_rmssd_ms"], 42.0);
    assert_eq!(report["tolerance_ms"], 10.0);
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "official_label_provenance_missing")
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "hrv_feature_report_blocked")
    );
    assert!(
        report["quality_flags"]
            .as_array()
            .unwrap()
            .iter()
            .any(|flag| flag == "hrv_rr_interval_scale_unverified")
    );
}

#[test]
fn metric_feature_report_cli_runs_respiratory_rate_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("respiratory-rate-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--capture-kind")
            .arg("overnight_rest")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--official-whoop-respiratory-rate-rpm")
            .arg("14.5")
            .arg("--respiratory-rate-tolerance-rpm")
            .arg("1")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.respiratory-rate-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["capture_kind"], "overnight_rest");
    assert_eq!(report["official_whoop_respiratory_rate_rpm"], 14.5);
    assert_eq!(report["tolerance_rpm"], 1.0);
    assert_eq!(
        report["promotion_status"],
        "validation_only_respiratory_rate_semantics_still_unverified"
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "official_label_provenance_missing")
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_respiratory_rate_packet_candidate")
    );
}

#[test]
fn metric_feature_report_cli_runs_oxygen_saturation_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("spo2-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--capture-kind")
            .arg("overnight_rest")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--official-whoop-spo2-percent")
            .arg("97.0")
            .arg("--spo2-tolerance-percent")
            .arg("2.0")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.oxygen-saturation-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["capture_kind"], "overnight_rest");
    assert_eq!(report["official_whoop_oxygen_saturation_percent"], 97.0);
    assert_eq!(report["tolerance_percent"], 2.0);
    assert_eq!(report["source_kind"], "unavailable");
    assert_eq!(
        report["promotion_status"],
        "validation_only_oxygen_saturation_decoder_not_implemented"
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "official_label_provenance_missing")
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "oxygen_saturation_decoder_not_implemented")
    );
}

#[test]
fn metric_feature_report_cli_runs_temperature_capture_validation_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("temperature-validation")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--capture-kind")
            .arg("overnight_rest")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--official-whoop-skin-temperature-delta-c")
            .arg("0.2")
            .arg("--skin-temperature-tolerance-c")
            .arg("0.3")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.temperature-capture-validation-report.v1"
    );
    assert_eq!(
        report["label_policy"],
        "official_whoop_values_are_validation_labels_not_inputs"
    );
    assert_eq!(report["capture_kind"], "overnight_rest");
    assert_eq!(report["official_whoop_skin_temperature_delta_c"], 0.2);
    assert_eq!(report["tolerance_c"], 0.3);
    assert_eq!(report["source_kind"], "unavailable");
    assert_eq!(
        report["promotion_status"],
        "validation_only_temperature_units_still_unverified"
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "official_label_provenance_missing")
    );
    assert!(
        report["issues"]
            .as_array()
            .unwrap()
            .iter()
            .any(|issue| issue == "no_temperature_packet_candidate")
    );
}

#[test]
fn metric_feature_report_cli_runs_recovery_sensor_discovery_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("recovery-sensors")
            .arg("--database")
            .arg(&db)
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-03T00:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.recovery-sensor-discovery-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["widgets"].as_array().unwrap().len(), 4);
    assert!(report["issues"].as_array().unwrap().iter().any(
        |issue| issue == "oxygen_saturation_percent:oxygen_saturation_decoder_not_implemented"
    ));
    assert!(
        report["widgets"]
            .as_array()
            .unwrap()
            .iter()
            .any(|widget| widget["metric_id"] == "hrv_rmssd_ms"
                && widget["source_kind"] == "unavailable"
                && widget["confidence"] == 0.0)
    );
}

#[test]
fn metric_feature_report_cli_runs_recovery_unavailable_status_alias() {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("recovery-unavailable-status")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-02T08:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--min-rr-intervals-to-compute")
            .arg("2")
            .arg("--write-metric")
            .output()
            .unwrap();

    assert!(output.status.success(), "{output:?}");
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.recovery-unavailable-daily-status-report.v1"
    );
    assert_eq!(report["pass"], true);
    assert_eq!(report["unavailable_metric_count"], 4);
    assert_eq!(report["written_metric_count"], 4);
    assert!(
        report["statuses"]
            .as_array()
            .unwrap()
            .iter()
            .any(|status| status["metric_id"] == "skin_temperature_delta_c"
                && status["source_kind"] == "unavailable")
    );

    let store = OpenVitalsStore::open(&db).unwrap();
    assert_eq!(
        store
            .daily_recovery_metrics_between(0, i64::MAX)
            .unwrap()
            .into_iter()
            .filter(|row| row.source_kind == "unavailable")
            .count(),
        4
    );
}

#[test]
fn metric_feature_report_cli_runs_recovery_sensor_daily_rollup_alias_without_promoting_blocked_candidates()
 {
    let tempdir = tempfile::tempdir().unwrap();
    let db = tempdir.path().join("open_vitals.sqlite");

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-metric-feature-report"))
            .arg("--method")
            .arg("recovery-sensor-rollup")
            .arg("--database")
            .arg(&db)
            .arg("--date-key")
            .arg("2026-06-02")
            .arg("--timezone")
            .arg("Europe/London")
            .arg("--start")
            .arg("2026-06-02T00:00:00Z")
            .arg("--end")
            .arg("2026-06-02T08:00:00Z")
            .arg("--min-owned-captures")
            .arg("1")
            .arg("--require-trusted-evidence")
            .arg("--min-rr-intervals-to-compute")
            .arg("2")
            .arg("--write-metric")
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.recovery-sensor-daily-rollup-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["metric_count"], 4);
    assert_eq!(report["promotable_metric_count"], 0);
    assert_eq!(report["promoted_metric_count"], 0);
    assert_eq!(report["written_metric_count"], 0);
    assert!(
        report["statuses"]
            .as_array()
            .unwrap()
            .iter()
            .any(|status| status["metric_id"] == "hrv_rmssd_ms"
                && status["source_kind"] == "unavailable"
                && status["local_value"].is_null())
    );

    let store = OpenVitalsStore::open(&db).unwrap();
    assert_eq!(
        store
            .daily_recovery_metrics_between(0, i64::MAX)
            .unwrap()
            .into_iter()
            .filter(|row| row.source_kind == "device_sensor"
                && (row.hrv_rmssd_ms.is_some()
                    || row.respiratory_rate_rpm.is_some()
                    || row.oxygen_saturation_percent.is_some()
                    || row.skin_temperature_delta_c.is_some()))
            .count(),
        0
    );
}

fn import_motion_frame(store: &OpenVitalsStore) {
    let frames = vec![CapturedFrameInput {
        evidence_id: "metric-feature-cli-motion".to_string(),
        frame_id: Some("metric-feature-cli-motion.frame.0".to_string()),
        source: "ios.corebluetooth.notification".to_string(),
        captured_at: "2026-05-30T12:00:00Z".to_string(),
        device_model: "WHOOP 5.0 OpenVitals".to_string(),
        frame_hex: k10_motion_frame_hex(),
        sensitivity: "user-owned-capture".to_string(),
        capture_session_id: None,
        device_type: DeviceType::OpenVitals,
    }];
    let report = import_captured_frame_batch(
        store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "open-vitals-core/metric-feature-cli-test",
        },
    )
    .unwrap();
    assert!(report.pass, "{:?}", report.issues);
}

fn import_k20_optical_sequence_with_hr_reference(store: &OpenVitalsStore, seconds: usize) {
    let mut frames = Vec::new();
    for second in 0..seconds {
        let minute = second / 60;
        let second_in_minute = second % 60;
        let captured_at = format!("2026-06-11T12:{minute:02}:{second_in_minute:02}Z");
        frames.push(CapturedFrameInput {
            evidence_id: format!("metric-feature-cli-k20.{second}"),
            frame_id: Some(format!("metric-feature-cli-k20.{second}.frame.0")),
            source: "ios.corebluetooth.notification".to_string(),
            captured_at: captured_at.clone(),
            device_model: "WHOOP 5.0 OpenVitals".to_string(),
            frame_hex: k20_optical_frame_hex(second),
            sensitivity: "user-owned-capture".to_string(),
            capture_session_id: None,
            device_type: DeviceType::OpenVitals,
        });
        frames.push(CapturedFrameInput {
            evidence_id: format!("metric-feature-cli-k18.{second}"),
            frame_id: Some(format!("metric-feature-cli-k18.{second}.frame.0")),
            source: "ios.corebluetooth.notification".to_string(),
            captured_at,
            device_model: "WHOOP 5.0 OpenVitals".to_string(),
            frame_hex: k18_history_frame_hex(60),
            sensitivity: "user-owned-capture".to_string(),
            capture_session_id: None,
            device_type: DeviceType::OpenVitals,
        });
    }
    let report = import_captured_frame_batch(
        store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "open-vitals-core/metric-feature-cli-test",
        },
    )
    .unwrap();
    assert!(report.pass, "{:?}", report.issues);
}

fn import_k20_field_discovery_sequence_with_hr_reference(store: &OpenVitalsStore, seconds: usize) {
    let mut frames = Vec::new();
    for second in 0..seconds {
        let minute = second / 60;
        let second_in_minute = second % 60;
        let captured_at = format!("2026-06-11T12:{minute:02}:{second_in_minute:02}Z");
        let heart_rate = 55 + (second % 12) as u8;
        frames.push(CapturedFrameInput {
            evidence_id: format!("metric-feature-cli-k20-field.{second}"),
            frame_id: Some(format!("metric-feature-cli-k20-field.{second}.frame.0")),
            source: "ios.corebluetooth.notification".to_string(),
            captured_at: captured_at.clone(),
            device_model: "WHOOP 5.0 OpenVitals".to_string(),
            frame_hex: k20_field_discovery_frame_hex(second, heart_rate),
            sensitivity: "user-owned-capture".to_string(),
            capture_session_id: None,
            device_type: DeviceType::OpenVitals,
        });
        frames.push(CapturedFrameInput {
            evidence_id: format!("metric-feature-cli-k18-field.{second}"),
            frame_id: Some(format!("metric-feature-cli-k18-field.{second}.frame.0")),
            source: "ios.corebluetooth.notification".to_string(),
            captured_at,
            device_model: "WHOOP 5.0 OpenVitals".to_string(),
            frame_hex: k18_history_frame_hex(heart_rate),
            sensitivity: "user-owned-capture".to_string(),
            capture_session_id: None,
            device_type: DeviceType::OpenVitals,
        });
    }
    let report = import_captured_frame_batch(
        store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "open-vitals-core/metric-feature-cli-test",
        },
    )
    .unwrap();
    assert!(report.pass, "{:?}", report.issues);
}

fn import_k18_rr_validation_sequence(store: &OpenVitalsStore, seconds: usize) {
    let mut frames = Vec::new();
    for second in 0..seconds {
        let minute = second / 60;
        let second_in_minute = second % 60;
        let captured_at = format!("2026-06-11T12:{minute:02}:{second_in_minute:02}Z");
        frames.push(CapturedFrameInput {
            evidence_id: format!("metric-feature-cli-k18-rr.{second}"),
            frame_id: Some(format!("metric-feature-cli-k18-rr.{second}.frame.0")),
            source: "ios.corebluetooth.notification".to_string(),
            captured_at,
            device_model: "WHOOP 5.0 OpenVitals".to_string(),
            frame_hex: k18_history_frame_hex_with_rr_and_timestamp(
                60,
                &[1_000],
                1_781_179_200 + second as u32,
            ),
            sensitivity: "user-owned-capture".to_string(),
            capture_session_id: None,
            device_type: DeviceType::OpenVitals,
        });
    }
    let report = import_captured_frame_batch(
        store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "open-vitals-core/metric-feature-cli-test",
        },
    )
    .unwrap();
    assert!(report.pass, "{:?}", report.issues);
}

fn import_rr_reference_sequence(store: &OpenVitalsStore, seconds: usize) {
    store
        .start_capture_session(CaptureSessionInput {
            session_id: "rr-reference.metric-feature-cli",
            source: "ios.rr_reference_capture",
            started_at_unix_ms: 1_781_182_800_000,
            device_model: "BLE Heart Rate Reference",
            active_device_id: Some("rr-reference-test"),
            provenance_json: r#"{"test":true}"#,
        })
        .unwrap();

    for second in 0..seconds {
        let minute = second / 60;
        let second_in_minute = second % 60;
        let sample_id = format!("rr-reference.metric-feature-cli.{second}");
        let captured_at = format!("2026-06-11T12:{minute:02}:{second_in_minute:02}Z");
        let report = store
            .insert_rr_reference_samples(&[RrReferenceSampleInput {
                sample_id: &sample_id,
                session_id: "rr-reference.metric-feature-cli",
                captured_at: &captured_at,
                device_name: "BLE Heart Rate Reference",
                device_id: "rr-reference-test",
                heart_rate_bpm: Some(60.0),
                rr_interval_ms: 1_000.0,
                notification_sequence: second as i64,
                rr_index: 0,
                contact_detected: Some(true),
                energy_expended_j: None,
                provenance_json: r#"{"test":true}"#,
            }])
            .unwrap();
        assert_eq!(report.inserted_count, 1);
    }
}

fn k10_motion_frame_hex() -> String {
    let mut payload = vec![0; 1288];
    payload[0] = PACKET_TYPE_REALTIME_RAW_DATA;
    payload[1] = 10;
    payload[17] = 72;
    for offset in [85, 285, 485, 688, 888, 1088] {
        for index in 0..100 {
            put_i16(&mut payload, offset + index * 2, 1000);
        }
    }
    hex::encode(build_v5_payload_frame(&payload))
}

fn k20_optical_frame_hex(frame_index: usize) -> String {
    let mut payload = vec![0; 2128];
    payload[0] = PACKET_TYPE_REALTIME_RAW_DATA;
    payload[1] = 20;
    payload[2] = 129;
    put_u32(&mut payload, 3, frame_index as u32);
    let body_offset = 13;
    for offset in [26, 226, 1292, 1492, 1714, 1914] {
        for sample_index in 0..25 {
            let global_sample = frame_index * 25 + sample_index;
            let value = if offset == 26 && global_sample % 25 == 8 {
                210_000
            } else if offset == 26 {
                200_000
            } else {
                50_000 + offset as u32
            };
            put_u32(&mut payload, body_offset + offset + sample_index * 4, value);
        }
    }
    hex::encode(build_v5_payload_frame(&payload))
}

fn k20_field_discovery_frame_hex(frame_index: usize, heart_rate: u8) -> String {
    let mut payload = vec![0; 2128];
    payload[0] = PACKET_TYPE_REALTIME_RAW_DATA;
    payload[1] = 20;
    payload[2] = 129;
    put_u32(&mut payload, 3, frame_index as u32);
    let body_offset = 13;
    payload[body_offset + 180] = heart_rate;
    for offset in [26, 226, 1292, 1492, 1714, 1914] {
        for sample_index in 0..25 {
            let value = 50_000 + offset as u32 + sample_index as u32;
            put_u32(&mut payload, body_offset + offset + sample_index * 4, value);
        }
    }
    payload[body_offset + 180] = heart_rate;
    hex::encode(build_v5_payload_frame(&payload))
}

fn k18_history_frame_hex(heart_rate: u8) -> String {
    let mut payload = vec![0; 112];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 18;
    payload[2] = 128;
    payload[14] = heart_rate;
    hex::encode(build_v5_payload_frame(&payload))
}

fn k18_history_frame_hex_with_rr_and_timestamp(
    heart_rate: u8,
    rr_intervals_ms: &[u16],
    timestamp_seconds: u32,
) -> String {
    let mut payload = vec![0; (16 + rr_intervals_ms.len() * 2).max(112)];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 18;
    payload[2] = 128;
    put_u32(&mut payload, 7, timestamp_seconds);
    payload[14] = heart_rate;
    payload[15] = rr_intervals_ms.len() as u8;
    for (index, value) in rr_intervals_ms.iter().enumerate() {
        put_u16(&mut payload, 16 + index * 2, *value);
    }
    hex::encode(build_v5_payload_frame(&payload))
}

fn put_i16(bytes: &mut [u8], offset: usize, value: i16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn assert_success(output: &Output) {
    assert!(
        output.status.success(),
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn assert_failure(output: &Output) {
    assert!(
        !output.status.success(),
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
