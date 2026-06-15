use std::{fs, process::Output};

#[test]
fn k18_hrv_corpus_evaluator_blocks_false_accepts() {
    let tempdir = tempfile::tempdir().unwrap();
    let report_path = tempdir.path().join("k18-report.json");
    fs::write(
        &report_path,
        serde_json::json!({
            "schema": "open_vitals.k18-hrv-validation-report.v1",
            "diagnostic_sliding_window_summaries": [
                {
                    "reference_label": "pass",
                    "k18_only_decision": "pass",
                    "failure_reasons": ["pass"],
                    "primary_failure_reason": "pass",
                    "candidate_shape_summary": {
                        "interval_count_expected_ratio": 0.99,
                        "bin_step_mean_absolute_ms": 70.0,
                        "bin_step_rmssd_ms": 90.0,
                        "bin_step_over_100ms_fraction": 0.3,
                        "sample_gap_over_3s_count": 0.0
                    },
                    "candidate_current_binned_comparison": {
                        "mean_absolute_error_ms": 36.0,
                        "pearson_correlation": 0.75
                    },
                    "motion_context_summary": {
                        "max_context_motion_intensity_0_to_1": 0.039
                    },
                    "accepted_rejected_by_current_gate_interval_fraction": 0.3,
                    "max_candidate_sample_gap_seconds": 4.0,
                    "rmssd_error_ms": 4.0,
                    "sdnn_error_ms": 3.0,
                    "mean_nn_error_ms": 2.0,
                    "binned_comparison": {
                        "mean_absolute_error_ms": 10.0,
                        "pearson_correlation": 0.9
                    }
                },
                {
                    "reference_label": "fail",
                    "k18_only_decision": "pass",
                    "failure_reasons": ["binned_shape_mismatch"],
                    "primary_failure_reason": "binned_shape_mismatch",
                    "candidate_shape_summary": {
                        "interval_count_expected_ratio": 0.98,
                        "bin_step_mean_absolute_ms": 60.0,
                        "bin_step_rmssd_ms": 75.0,
                        "bin_step_over_100ms_fraction": 0.2,
                        "sample_gap_over_3s_count": 0.0
                    },
                    "candidate_current_binned_comparison": {
                        "mean_absolute_error_ms": 20.0,
                        "pearson_correlation": 0.85
                    },
                    "motion_context_summary": {
                        "max_context_motion_intensity_0_to_1": 0.039
                    },
                    "accepted_rejected_by_current_gate_interval_fraction": 0.21,
                    "max_candidate_sample_gap_seconds": 3.0,
                    "rmssd_error_ms": 5.0,
                    "sdnn_error_ms": 4.0,
                    "mean_nn_error_ms": 3.0,
                    "binned_comparison": {
                        "mean_absolute_error_ms": 25.0,
                        "pearson_correlation": 0.7
                    }
                }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let output =
        std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-k18-hrv-corpus-evaluator"))
            .arg("--report")
            .arg(&report_path)
            .output()
            .unwrap();

    assert_failure(&output);
    let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        report["schema"],
        "open_vitals.k18-hrv-corpus-evaluation-report.v1"
    );
    assert_eq!(report["pass"], false);
    assert_eq!(report["total_window_count"], 2);
    assert_eq!(report["true_accept_count"], 1);
    assert_eq!(report["false_accept_count"], 1);
    assert_eq!(report["k18_pass_precision_fraction"], 0.5);
    assert!(
        report["promotion_blockers"]
            .as_array()
            .unwrap()
            .iter()
            .any(|blocker| blocker == "k18_pass_in_reference_fail_window")
    );
    let strict_rule = report["rule_candidates"]
        .as_array()
        .unwrap()
        .iter()
        .find(|candidate| candidate["rule_id"] == "k18_pass_strict_temporal_variability_combo")
        .unwrap();
    assert_eq!(strict_rule["selected_count"], 1);
    assert_eq!(strict_rule["selected_reference_pass_count"], 1);
    assert_eq!(strict_rule["selected_reference_fail_count"], 0);
    assert_eq!(
        strict_rule["promotion_status"],
        "candidate_rule_repeat_required"
    );
}

fn assert_failure(output: &Output) {
    assert!(
        !output.status.success(),
        "expected failure\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
