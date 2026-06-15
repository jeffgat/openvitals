use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

use open_vitals_core::{
    OpenVitalsError, OpenVitalsResult, report::write_json_report, tool_args::path_value,
};
use serde::Serialize;
use serde_json::Value;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}

fn run() -> OpenVitalsResult<()> {
    let args = open_vitals_core::tool_args::args();
    let output = path_value(&args, "--output")?;
    let report_paths = collect_report_paths(&args)?;
    if report_paths.is_empty() {
        return Err(OpenVitalsError::message(
            "--report or --reports-dir is required",
        ));
    }

    let mut evaluator = CorpusEvaluator::default();
    for report_path in report_paths {
        evaluator.ingest_report(&report_path)?;
    }

    let report = evaluator.finish();
    write_json_report(&report, output.as_deref())?;
    if report.pass {
        Ok(())
    } else {
        std::process::exit(1);
    }
}

fn collect_report_paths(args: &[String]) -> OpenVitalsResult<Vec<PathBuf>> {
    let mut paths = Vec::new();
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--report" => {
                index += 1;
                let Some(path) = args.get(index) else {
                    return Err(OpenVitalsError::message("missing value for --report"));
                };
                paths.push(PathBuf::from(path));
            }
            "--reports-dir" => {
                index += 1;
                let Some(path) = args.get(index) else {
                    return Err(OpenVitalsError::message("missing value for --reports-dir"));
                };
                paths.extend(json_files_in_dir(Path::new(path))?);
            }
            _ => {}
        }
        index += 1;
    }
    paths.sort();
    paths.dedup();
    Ok(paths)
}

fn json_files_in_dir(dir: &Path) -> OpenVitalsResult<Vec<PathBuf>> {
    let mut paths = Vec::new();
    for entry in fs::read_dir(dir).map_err(|source| OpenVitalsError::io(dir, source))? {
        let entry = entry.map_err(|source| OpenVitalsError::io(dir, source))?;
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) == Some("json") {
            paths.push(path);
        }
    }
    Ok(paths)
}

#[derive(Default)]
struct CorpusEvaluator {
    input_reports: Vec<String>,
    total_window_count: usize,
    reference_pass_count: usize,
    reference_fail_count: usize,
    reference_unknown_count: usize,
    k18_pass_count: usize,
    k18_fail_count: usize,
    k18_reject_count: usize,
    k18_unknown_count: usize,
    true_accept_count: usize,
    true_reject_count: usize,
    false_accept_count: usize,
    false_reject_count: usize,
    abstained_reference_pass_count: usize,
    decision_cells: BTreeMap<(String, String), usize>,
    failure_reason_counts: BTreeMap<String, usize>,
    false_accept_failure_reason_counts: BTreeMap<String, usize>,
    false_reject_failure_reason_counts: BTreeMap<String, usize>,
    primary_failure_reason_counts: BTreeMap<String, usize>,
    outcomes: BTreeMap<String, OutcomeAccumulator>,
    rules: BTreeMap<String, RuleAccumulator>,
}

impl CorpusEvaluator {
    fn ingest_report(&mut self, path: &Path) -> OpenVitalsResult<()> {
        let raw = fs::read_to_string(path).map_err(|source| OpenVitalsError::io(path, source))?;
        let report: Value =
            serde_json::from_str(&raw).map_err(|source| OpenVitalsError::json(path, source))?;
        self.input_reports.push(path.display().to_string());
        let windows = report
            .get("diagnostic_sliding_window_summaries")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        for window in windows {
            self.ingest_window(&window);
        }
        Ok(())
    }

    fn ingest_window(&mut self, window: &Value) {
        self.total_window_count += 1;
        let reference_label = string_field(window, "reference_label", "unknown");
        let k18_only_decision = string_field(window, "k18_only_decision", "unknown");
        let outcome_key = format!("{reference_label}->{k18_only_decision}");

        match reference_label.as_str() {
            "pass" => self.reference_pass_count += 1,
            "fail" => self.reference_fail_count += 1,
            _ => self.reference_unknown_count += 1,
        }
        match k18_only_decision.as_str() {
            "pass" => self.k18_pass_count += 1,
            "fail" => self.k18_fail_count += 1,
            "reject" => self.k18_reject_count += 1,
            _ => self.k18_unknown_count += 1,
        }
        match (reference_label.as_str(), k18_only_decision.as_str()) {
            ("pass", "pass") => self.true_accept_count += 1,
            ("fail", "pass") => self.false_accept_count += 1,
            ("fail", "fail" | "reject") => self.true_reject_count += 1,
            ("pass", "fail" | "reject") => self.false_reject_count += 1,
            ("pass", "unknown") => self.abstained_reference_pass_count += 1,
            _ => {}
        }
        *self
            .decision_cells
            .entry((reference_label.clone(), k18_only_decision.clone()))
            .or_default() += 1;

        let failure_reasons = window
            .get("failure_reasons")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        for reason in failure_reasons.iter().filter_map(Value::as_str) {
            *self
                .failure_reason_counts
                .entry(reason.to_string())
                .or_default() += 1;
            if reference_label == "fail" && k18_only_decision == "pass" {
                *self
                    .false_accept_failure_reason_counts
                    .entry(reason.to_string())
                    .or_default() += 1;
            }
            if reference_label == "pass" && matches!(k18_only_decision.as_str(), "fail" | "reject")
            {
                *self
                    .false_reject_failure_reason_counts
                    .entry(reason.to_string())
                    .or_default() += 1;
            }
        }
        if let Some(reason) = window.get("primary_failure_reason").and_then(Value::as_str) {
            *self
                .primary_failure_reason_counts
                .entry(reason.to_string())
                .or_default() += 1;
        }

        self.outcomes
            .entry(outcome_key)
            .or_default()
            .ingest_window(window);

        let features = RuleFeatureSet::from_window(&reference_label, &k18_only_decision, window);
        for rule in rule_definitions() {
            if rule.matches(&features) {
                self.rules
                    .entry(rule.rule_id.to_string())
                    .or_default()
                    .ingest(&features);
            }
        }
    }

    fn finish(mut self) -> K18HrvCorpusEvaluationReport {
        self.input_reports.sort();
        let labeled_k18_pass_count = self.true_accept_count + self.false_accept_count;
        let mut promotion_blockers = Vec::new();
        if self.input_reports.is_empty() {
            promotion_blockers.push("no_input_reports".to_string());
        }
        if self.total_window_count == 0 {
            promotion_blockers.push("no_sliding_windows".to_string());
        }
        if self.reference_pass_count + self.reference_fail_count == 0 {
            promotion_blockers.push("no_reference_labeled_windows".to_string());
        }
        if self.true_accept_count == 0 {
            promotion_blockers.push("no_true_accept_windows".to_string());
        }
        if self.false_accept_count > 0 {
            promotion_blockers.push("k18_pass_in_reference_fail_window".to_string());
        }
        if self.false_reject_count > 0 {
            promotion_blockers.push("k18_rejects_reference_pass_window".to_string());
        }
        if self.abstained_reference_pass_count > 0 {
            promotion_blockers.push("k18_abstains_reference_pass_window".to_string());
        }
        if self.reference_unknown_count > 0 {
            promotion_blockers.push("reference_unknown_windows_present".to_string());
        }
        let pass = promotion_blockers.is_empty();

        K18HrvCorpusEvaluationReport {
            schema: "open_vitals.k18-hrv-corpus-evaluation-report.v1".to_string(),
            generated_by: "open-vitals-k18-hrv-corpus-evaluator".to_string(),
            pass,
            promotion_status: if pass {
                "validation_only_repeat_required".to_string()
            } else {
                "validation_only_blocked".to_string()
            },
            promotion_blockers,
            input_report_count: self.input_reports.len(),
            input_reports: self.input_reports,
            total_window_count: self.total_window_count,
            reference_labeled_window_count: self.reference_pass_count + self.reference_fail_count,
            reference_pass_count: self.reference_pass_count,
            reference_fail_count: self.reference_fail_count,
            reference_unknown_count: self.reference_unknown_count,
            k18_pass_count: self.k18_pass_count,
            k18_fail_count: self.k18_fail_count,
            k18_reject_count: self.k18_reject_count,
            k18_unknown_count: self.k18_unknown_count,
            true_accept_count: self.true_accept_count,
            true_reject_count: self.true_reject_count,
            false_accept_count: self.false_accept_count,
            false_reject_count: self.false_reject_count,
            abstained_reference_pass_count: self.abstained_reference_pass_count,
            labeled_k18_pass_count,
            k18_pass_precision_fraction: ratio_fraction(
                self.true_accept_count,
                labeled_k18_pass_count,
            )
            .map(round_3),
            k18_pass_false_accept_fraction: ratio_fraction(
                self.false_accept_count,
                labeled_k18_pass_count,
            )
            .map(round_3),
            reference_pass_recall_fraction: ratio_fraction(
                self.true_accept_count,
                self.reference_pass_count,
            )
            .map(round_3),
            reference_pass_false_reject_fraction: ratio_fraction(
                self.false_reject_count,
                self.reference_pass_count,
            )
            .map(round_3),
            decision_cells: self
                .decision_cells
                .into_iter()
                .map(
                    |((reference_label, k18_only_decision), count)| K18HrvCorpusDecisionCell {
                        reference_label,
                        k18_only_decision,
                        count,
                    },
                )
                .collect(),
            failure_reason_counts: count_map_to_rows(self.failure_reason_counts),
            false_accept_failure_reason_counts: count_map_to_rows(
                self.false_accept_failure_reason_counts,
            ),
            false_reject_failure_reason_counts: count_map_to_rows(
                self.false_reject_failure_reason_counts,
            ),
            primary_failure_reason_counts: count_map_to_rows(self.primary_failure_reason_counts),
            rule_candidates: rule_definitions()
                .into_iter()
                .map(|rule| {
                    let accumulator = self.rules.remove(rule.rule_id).unwrap_or_default();
                    accumulator.finish(
                        rule.rule_id.to_string(),
                        rule.description.to_string(),
                        self.reference_pass_count,
                    )
                })
                .collect(),
            outcome_summaries: self
                .outcomes
                .into_iter()
                .map(|(outcome, accumulator)| accumulator.finish(outcome))
                .collect(),
        }
    }
}

#[derive(Default)]
struct RuleAccumulator {
    selected_count: usize,
    selected_reference_pass_count: usize,
    selected_reference_fail_count: usize,
    selected_reference_unknown_count: usize,
}

impl RuleAccumulator {
    fn ingest(&mut self, features: &RuleFeatureSet) {
        self.selected_count += 1;
        match features.reference_label.as_str() {
            "pass" => self.selected_reference_pass_count += 1,
            "fail" => self.selected_reference_fail_count += 1,
            _ => self.selected_reference_unknown_count += 1,
        }
    }

    fn finish(
        self,
        rule_id: String,
        description: String,
        corpus_reference_pass_count: usize,
    ) -> K18HrvCorpusRuleCandidate {
        let selected_labeled_count =
            self.selected_reference_pass_count + self.selected_reference_fail_count;
        let mut promotion_blockers = Vec::new();
        if self.selected_count == 0 {
            promotion_blockers.push("rule_selected_no_windows".to_string());
        }
        if self.selected_reference_pass_count == 0 {
            promotion_blockers.push("rule_selected_no_true_accept_windows".to_string());
        }
        if self.selected_reference_fail_count > 0 {
            promotion_blockers.push("rule_selected_reference_fail_windows".to_string());
        }
        if self.selected_reference_unknown_count > 0 {
            promotion_blockers.push("rule_selected_reference_unknown_windows".to_string());
        }
        let promotion_status = if promotion_blockers.is_empty() {
            "candidate_rule_repeat_required".to_string()
        } else {
            "candidate_rule_blocked".to_string()
        };

        K18HrvCorpusRuleCandidate {
            rule_id,
            description,
            selected_count: self.selected_count,
            selected_reference_pass_count: self.selected_reference_pass_count,
            selected_reference_fail_count: self.selected_reference_fail_count,
            selected_reference_unknown_count: self.selected_reference_unknown_count,
            selected_labeled_count,
            selected_precision_fraction: ratio_fraction(
                self.selected_reference_pass_count,
                selected_labeled_count,
            )
            .map(round_3),
            reference_pass_recall_fraction: ratio_fraction(
                self.selected_reference_pass_count,
                corpus_reference_pass_count,
            )
            .map(round_3),
            promotion_status,
            promotion_blockers,
        }
    }
}

struct RuleDefinition {
    rule_id: &'static str,
    description: &'static str,
    matcher: fn(&RuleFeatureSet) -> bool,
}

impl RuleDefinition {
    fn matches(&self, features: &RuleFeatureSet) -> bool {
        (self.matcher)(features)
    }
}

#[derive(Debug)]
struct RuleFeatureSet {
    reference_label: String,
    k18_only_decision: String,
    candidate_interval_expected_ratio: Option<f64>,
    accepted_rejected_by_current_gate_interval_fraction: Option<f64>,
    candidate_bin_step_mean_absolute_ms: Option<f64>,
    candidate_bin_step_over_100ms_fraction: Option<f64>,
    candidate_current_binned_mae_ms: Option<f64>,
    candidate_sample_gap_over_3s_count: Option<f64>,
    relaxed_locally_plausible_fraction: Option<f64>,
    relaxed_short_excursion_interval_count: Option<f64>,
    relaxed_long_excursion_interval_count: Option<f64>,
    relaxed_local_abs_delta_p95_ms: Option<f64>,
    context_max_motion_intensity_0_to_1: Option<f64>,
}

impl RuleFeatureSet {
    fn from_window(reference_label: &str, k18_only_decision: &str, window: &Value) -> Self {
        Self {
            reference_label: reference_label.to_string(),
            k18_only_decision: k18_only_decision.to_string(),
            candidate_interval_expected_ratio: number_at(
                window,
                &["candidate_shape_summary", "interval_count_expected_ratio"],
            ),
            accepted_rejected_by_current_gate_interval_fraction: number_at(
                window,
                &["accepted_rejected_by_current_gate_interval_fraction"],
            ),
            candidate_bin_step_mean_absolute_ms: number_at(
                window,
                &["candidate_shape_summary", "bin_step_mean_absolute_ms"],
            ),
            candidate_bin_step_over_100ms_fraction: number_at(
                window,
                &["candidate_shape_summary", "bin_step_over_100ms_fraction"],
            ),
            candidate_current_binned_mae_ms: number_at(
                window,
                &[
                    "candidate_current_binned_comparison",
                    "mean_absolute_error_ms",
                ],
            ),
            candidate_sample_gap_over_3s_count: number_at(
                window,
                &["candidate_shape_summary", "sample_gap_over_3s_count"],
            ),
            relaxed_locally_plausible_fraction: number_at(
                window,
                &["row_context_summary", "relaxed_locally_plausible_fraction"],
            ),
            relaxed_short_excursion_interval_count: number_at(
                window,
                &[
                    "row_context_summary",
                    "relaxed_short_excursion_interval_count",
                ],
            ),
            relaxed_long_excursion_interval_count: number_at(
                window,
                &[
                    "row_context_summary",
                    "relaxed_long_excursion_interval_count",
                ],
            ),
            relaxed_local_abs_delta_p95_ms: number_at(
                window,
                &["row_context_summary", "relaxed_local_abs_delta_p95_ms"],
            ),
            context_max_motion_intensity_0_to_1: number_at(
                window,
                &[
                    "motion_context_summary",
                    "max_context_motion_intensity_0_to_1",
                ],
            ),
        }
    }
}

fn rule_definitions() -> Vec<RuleDefinition> {
    vec![
        RuleDefinition {
            rule_id: "k18_pass_baseline",
            description: "Current K18-only pass decision.",
            matcher: |features| features.k18_only_decision == "pass",
        },
        RuleDefinition {
            rule_id: "k18_pass_candidate_ratio_ge_0_95",
            description: "K18 pass with candidate interval count at least 95% of expectation from mean NN.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_interval_expected_ratio
                        .is_some_and(|value| value >= 0.95)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_no_3s_gap_and_ratio_ge_0_95",
            description: "K18 pass with no candidate sample gap over 3 seconds and at least 95% expected interval coverage.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_interval_expected_ratio
                        .is_some_and(|value| value >= 0.95)
                    && features
                        .candidate_sample_gap_over_3s_count
                        .is_some_and(|value| value == 0.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_relaxed_fraction_ge_0_30",
            description: "K18 pass where relaxed bounded rows contribute at least 30% of candidate intervals.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .accepted_rejected_by_current_gate_interval_fraction
                        .is_some_and(|value| value >= 0.30)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_bin_step_mae_ge_75",
            description: "K18 pass with candidate median-bin step MAE at least 75 ms.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_bin_step_mean_absolute_ms
                        .is_some_and(|value| value >= 75.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_step100_fraction_ge_0_25",
            description: "K18 pass with at least 25% of candidate median-bin steps over 100 ms.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_bin_step_over_100ms_fraction
                        .is_some_and(|value| value >= 0.25)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_candidate_current_mae_ge_25",
            description: "K18 pass where bounded candidate bins differ from current-gated bins by at least 25 ms MAE.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_current_binned_mae_ms
                        .is_some_and(|value| value >= 25.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_high_shape_combo",
            description: "K18 pass with high candidate coverage, relaxed-row contribution, and median-bin variability.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_interval_expected_ratio
                        .is_some_and(|value| value >= 0.95)
                    && features
                        .accepted_rejected_by_current_gate_interval_fraction
                        .is_some_and(|value| value >= 0.30)
                    && features
                        .candidate_bin_step_mean_absolute_ms
                        .is_some_and(|value| value >= 75.0)
                    && features
                        .candidate_current_binned_mae_ms
                        .is_some_and(|value| value >= 25.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_strict_temporal_variability_combo",
            description: "K18 pass with high coverage, no candidate gaps over 3 seconds, low motion, relaxed-row contribution, and strong candidate/current temporal variability separation.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_interval_expected_ratio
                        .is_some_and(|value| value >= 0.95)
                    && features
                        .candidate_sample_gap_over_3s_count
                        .is_some_and(|value| value == 0.0)
                    && features
                        .context_max_motion_intensity_0_to_1
                        .is_some_and(|value| value <= 0.04)
                    && features
                        .accepted_rejected_by_current_gate_interval_fraction
                        .is_some_and(|value| value >= 0.25)
                    && features
                        .candidate_bin_step_mean_absolute_ms
                        .is_some_and(|value| value >= 65.0)
                    && features
                        .candidate_current_binned_mae_ms
                        .is_some_and(|value| value >= 35.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_low_motion_no_gap_ratio_ge_0_95",
            description: "K18 pass with low motion context, no candidate sample gap over 3 seconds, and at least 95% expected interval coverage.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .candidate_interval_expected_ratio
                        .is_some_and(|value| value >= 0.95)
                    && features
                        .candidate_sample_gap_over_3s_count
                        .is_some_and(|value| value == 0.0)
                    && features
                        .context_max_motion_intensity_0_to_1
                        .is_some_and(|value| value <= 0.04)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_relaxed_rows_locally_plausible",
            description: "K18 pass where at least 95% of relaxed bounded intervals are within local current-gate tolerance.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .relaxed_locally_plausible_fraction
                        .is_some_and(|value| value >= 0.95)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_no_relaxed_excursions",
            description: "K18 pass with no relaxed bounded interval outside local current-gate tolerance.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .relaxed_short_excursion_interval_count
                        .is_some_and(|value| value == 0.0)
                    && features
                        .relaxed_long_excursion_interval_count
                        .is_some_and(|value| value == 0.0)
            },
        },
        RuleDefinition {
            rule_id: "k18_pass_relaxed_delta_p95_le_220",
            description: "K18 pass where relaxed bounded intervals have local p95 absolute delta no more than 220 ms.",
            matcher: |features| {
                features.k18_only_decision == "pass"
                    && features
                        .relaxed_local_abs_delta_p95_ms
                        .is_some_and(|value| value <= 220.0)
            },
        },
    ]
}

#[derive(Default)]
struct OutcomeAccumulator {
    count: usize,
    candidate_covered_window_fractions: Vec<f64>,
    candidate_first_sample_offset_seconds: Vec<f64>,
    candidate_last_sample_offset_seconds: Vec<f64>,
    candidate_sample_gap_over_3s_counts: Vec<f64>,
    candidate_sample_gap_over_10s_counts: Vec<f64>,
    candidate_sample_gap_over_3s_total_seconds: Vec<f64>,
    candidate_interval_expected_ratios: Vec<f64>,
    candidate_bin_step_mean_absolute_ms: Vec<f64>,
    candidate_bin_step_rmssd_ms: Vec<f64>,
    candidate_bin_step_over_100ms_fractions: Vec<f64>,
    candidate_current_binned_mae_ms: Vec<f64>,
    candidate_current_binned_correlations: Vec<f64>,
    relaxed_locally_plausible_fractions: Vec<f64>,
    relaxed_short_excursion_counts: Vec<f64>,
    relaxed_long_excursion_counts: Vec<f64>,
    relaxed_local_abs_delta_p95_ms: Vec<f64>,
    context_max_motion_intensities: Vec<f64>,
    start_transition_deltas: Vec<f64>,
    end_transition_deltas: Vec<f64>,
    accepted_rejected_by_current_gate_interval_fractions: Vec<f64>,
    max_candidate_sample_gap_seconds: Vec<f64>,
    rmssd_errors_ms: Vec<f64>,
    sdnn_errors_ms: Vec<f64>,
    mean_nn_errors_ms: Vec<f64>,
    binned_mae_ms: Vec<f64>,
    binned_correlations: Vec<f64>,
}

impl OutcomeAccumulator {
    fn ingest_window(&mut self, window: &Value) {
        self.count += 1;
        push_number(
            &mut self.candidate_covered_window_fractions,
            value_at(
                window,
                &["candidate_shape_summary", "covered_window_fraction"],
            ),
        );
        push_number(
            &mut self.candidate_first_sample_offset_seconds,
            value_at(
                window,
                &["candidate_shape_summary", "first_sample_offset_seconds"],
            ),
        );
        push_number(
            &mut self.candidate_last_sample_offset_seconds,
            value_at(
                window,
                &["candidate_shape_summary", "last_sample_offset_seconds"],
            ),
        );
        push_number(
            &mut self.candidate_sample_gap_over_3s_counts,
            value_at(
                window,
                &["candidate_shape_summary", "sample_gap_over_3s_count"],
            ),
        );
        push_number(
            &mut self.candidate_sample_gap_over_10s_counts,
            value_at(
                window,
                &["candidate_shape_summary", "sample_gap_over_10s_count"],
            ),
        );
        push_number(
            &mut self.candidate_sample_gap_over_3s_total_seconds,
            value_at(
                window,
                &[
                    "candidate_shape_summary",
                    "sample_gap_over_3s_total_seconds",
                ],
            ),
        );
        push_number(
            &mut self.candidate_interval_expected_ratios,
            value_at(
                window,
                &["candidate_shape_summary", "interval_count_expected_ratio"],
            ),
        );
        push_number(
            &mut self.candidate_bin_step_mean_absolute_ms,
            value_at(
                window,
                &["candidate_shape_summary", "bin_step_mean_absolute_ms"],
            ),
        );
        push_number(
            &mut self.candidate_bin_step_rmssd_ms,
            value_at(window, &["candidate_shape_summary", "bin_step_rmssd_ms"]),
        );
        push_number(
            &mut self.candidate_bin_step_over_100ms_fractions,
            value_at(
                window,
                &["candidate_shape_summary", "bin_step_over_100ms_fraction"],
            ),
        );
        push_number(
            &mut self.candidate_current_binned_mae_ms,
            value_at(
                window,
                &[
                    "candidate_current_binned_comparison",
                    "mean_absolute_error_ms",
                ],
            ),
        );
        push_number(
            &mut self.candidate_current_binned_correlations,
            value_at(
                window,
                &["candidate_current_binned_comparison", "pearson_correlation"],
            ),
        );
        push_number(
            &mut self.relaxed_locally_plausible_fractions,
            value_at(
                window,
                &["row_context_summary", "relaxed_locally_plausible_fraction"],
            ),
        );
        push_number(
            &mut self.relaxed_short_excursion_counts,
            value_at(
                window,
                &[
                    "row_context_summary",
                    "relaxed_short_excursion_interval_count",
                ],
            ),
        );
        push_number(
            &mut self.relaxed_long_excursion_counts,
            value_at(
                window,
                &[
                    "row_context_summary",
                    "relaxed_long_excursion_interval_count",
                ],
            ),
        );
        push_number(
            &mut self.relaxed_local_abs_delta_p95_ms,
            value_at(
                window,
                &["row_context_summary", "relaxed_local_abs_delta_p95_ms"],
            ),
        );
        push_number(
            &mut self.context_max_motion_intensities,
            value_at(
                window,
                &[
                    "motion_context_summary",
                    "max_context_motion_intensity_0_to_1",
                ],
            ),
        );
        push_number(
            &mut self.start_transition_deltas,
            value_at(
                window,
                &["motion_context_summary", "start_transition_delta_0_to_1"],
            ),
        );
        push_number(
            &mut self.end_transition_deltas,
            value_at(
                window,
                &["motion_context_summary", "end_transition_delta_0_to_1"],
            ),
        );
        push_number(
            &mut self.accepted_rejected_by_current_gate_interval_fractions,
            window.get("accepted_rejected_by_current_gate_interval_fraction"),
        );
        push_number(
            &mut self.max_candidate_sample_gap_seconds,
            window.get("max_candidate_sample_gap_seconds"),
        );
        push_number(&mut self.rmssd_errors_ms, window.get("rmssd_error_ms"));
        push_number(&mut self.sdnn_errors_ms, window.get("sdnn_error_ms"));
        push_number(&mut self.mean_nn_errors_ms, window.get("mean_nn_error_ms"));
        push_number(
            &mut self.binned_mae_ms,
            value_at(window, &["binned_comparison", "mean_absolute_error_ms"]),
        );
        push_number(
            &mut self.binned_correlations,
            value_at(window, &["binned_comparison", "pearson_correlation"]),
        );
    }

    fn finish(mut self, outcome: String) -> K18HrvCorpusOutcomeSummary {
        K18HrvCorpusOutcomeSummary {
            outcome,
            count: self.count,
            median_candidate_covered_window_fraction: median_and_sort(
                &mut self.candidate_covered_window_fractions,
            ),
            median_candidate_first_sample_offset_seconds: median_and_sort(
                &mut self.candidate_first_sample_offset_seconds,
            ),
            median_candidate_last_sample_offset_seconds: median_and_sort(
                &mut self.candidate_last_sample_offset_seconds,
            ),
            median_candidate_sample_gap_over_3s_count: median_and_sort(
                &mut self.candidate_sample_gap_over_3s_counts,
            ),
            median_candidate_sample_gap_over_10s_count: median_and_sort(
                &mut self.candidate_sample_gap_over_10s_counts,
            ),
            median_candidate_sample_gap_over_3s_total_seconds: median_and_sort(
                &mut self.candidate_sample_gap_over_3s_total_seconds,
            ),
            median_candidate_interval_expected_ratio: median_and_sort(
                &mut self.candidate_interval_expected_ratios,
            ),
            median_candidate_bin_step_mean_absolute_ms: median_and_sort(
                &mut self.candidate_bin_step_mean_absolute_ms,
            ),
            median_candidate_bin_step_rmssd_ms: median_and_sort(
                &mut self.candidate_bin_step_rmssd_ms,
            ),
            median_candidate_bin_step_over_100ms_fraction: median_and_sort(
                &mut self.candidate_bin_step_over_100ms_fractions,
            ),
            median_candidate_current_binned_mae_ms: median_and_sort(
                &mut self.candidate_current_binned_mae_ms,
            ),
            median_candidate_current_binned_correlation: median_and_sort(
                &mut self.candidate_current_binned_correlations,
            ),
            median_relaxed_locally_plausible_fraction: median_and_sort(
                &mut self.relaxed_locally_plausible_fractions,
            ),
            median_relaxed_short_excursion_count: median_and_sort(
                &mut self.relaxed_short_excursion_counts,
            ),
            median_relaxed_long_excursion_count: median_and_sort(
                &mut self.relaxed_long_excursion_counts,
            ),
            median_relaxed_local_abs_delta_p95_ms: median_and_sort(
                &mut self.relaxed_local_abs_delta_p95_ms,
            ),
            median_context_max_motion_intensity_0_to_1: median_and_sort(
                &mut self.context_max_motion_intensities,
            ),
            median_start_transition_delta_0_to_1: median_and_sort(
                &mut self.start_transition_deltas,
            ),
            median_end_transition_delta_0_to_1: median_and_sort(&mut self.end_transition_deltas),
            median_accepted_rejected_by_current_gate_interval_fraction: median_and_sort(
                &mut self.accepted_rejected_by_current_gate_interval_fractions,
            ),
            median_max_candidate_sample_gap_seconds: median_and_sort(
                &mut self.max_candidate_sample_gap_seconds,
            ),
            median_rmssd_error_ms: median_and_sort(&mut self.rmssd_errors_ms),
            median_sdnn_error_ms: median_and_sort(&mut self.sdnn_errors_ms),
            median_mean_nn_error_ms: median_and_sort(&mut self.mean_nn_errors_ms),
            median_binned_mae_ms: median_and_sort(&mut self.binned_mae_ms),
            median_binned_correlation: median_and_sort(&mut self.binned_correlations),
        }
    }
}

#[derive(Debug, Serialize)]
struct K18HrvCorpusEvaluationReport {
    schema: String,
    generated_by: String,
    pass: bool,
    promotion_status: String,
    promotion_blockers: Vec<String>,
    input_report_count: usize,
    input_reports: Vec<String>,
    total_window_count: usize,
    reference_labeled_window_count: usize,
    reference_pass_count: usize,
    reference_fail_count: usize,
    reference_unknown_count: usize,
    k18_pass_count: usize,
    k18_fail_count: usize,
    k18_reject_count: usize,
    k18_unknown_count: usize,
    true_accept_count: usize,
    true_reject_count: usize,
    false_accept_count: usize,
    false_reject_count: usize,
    abstained_reference_pass_count: usize,
    labeled_k18_pass_count: usize,
    k18_pass_precision_fraction: Option<f64>,
    k18_pass_false_accept_fraction: Option<f64>,
    reference_pass_recall_fraction: Option<f64>,
    reference_pass_false_reject_fraction: Option<f64>,
    decision_cells: Vec<K18HrvCorpusDecisionCell>,
    failure_reason_counts: Vec<K18HrvCorpusCount>,
    false_accept_failure_reason_counts: Vec<K18HrvCorpusCount>,
    false_reject_failure_reason_counts: Vec<K18HrvCorpusCount>,
    primary_failure_reason_counts: Vec<K18HrvCorpusCount>,
    rule_candidates: Vec<K18HrvCorpusRuleCandidate>,
    outcome_summaries: Vec<K18HrvCorpusOutcomeSummary>,
}

#[derive(Debug, Serialize)]
struct K18HrvCorpusDecisionCell {
    reference_label: String,
    k18_only_decision: String,
    count: usize,
}

#[derive(Debug, Serialize)]
struct K18HrvCorpusCount {
    key: String,
    count: usize,
}

#[derive(Debug, Serialize)]
struct K18HrvCorpusRuleCandidate {
    rule_id: String,
    description: String,
    selected_count: usize,
    selected_reference_pass_count: usize,
    selected_reference_fail_count: usize,
    selected_reference_unknown_count: usize,
    selected_labeled_count: usize,
    selected_precision_fraction: Option<f64>,
    reference_pass_recall_fraction: Option<f64>,
    promotion_status: String,
    promotion_blockers: Vec<String>,
}

#[derive(Debug, Serialize)]
struct K18HrvCorpusOutcomeSummary {
    outcome: String,
    count: usize,
    median_candidate_covered_window_fraction: Option<f64>,
    median_candidate_first_sample_offset_seconds: Option<f64>,
    median_candidate_last_sample_offset_seconds: Option<f64>,
    median_candidate_sample_gap_over_3s_count: Option<f64>,
    median_candidate_sample_gap_over_10s_count: Option<f64>,
    median_candidate_sample_gap_over_3s_total_seconds: Option<f64>,
    median_candidate_interval_expected_ratio: Option<f64>,
    median_candidate_bin_step_mean_absolute_ms: Option<f64>,
    median_candidate_bin_step_rmssd_ms: Option<f64>,
    median_candidate_bin_step_over_100ms_fraction: Option<f64>,
    median_candidate_current_binned_mae_ms: Option<f64>,
    median_candidate_current_binned_correlation: Option<f64>,
    median_relaxed_locally_plausible_fraction: Option<f64>,
    median_relaxed_short_excursion_count: Option<f64>,
    median_relaxed_long_excursion_count: Option<f64>,
    median_relaxed_local_abs_delta_p95_ms: Option<f64>,
    median_context_max_motion_intensity_0_to_1: Option<f64>,
    median_start_transition_delta_0_to_1: Option<f64>,
    median_end_transition_delta_0_to_1: Option<f64>,
    median_accepted_rejected_by_current_gate_interval_fraction: Option<f64>,
    median_max_candidate_sample_gap_seconds: Option<f64>,
    median_rmssd_error_ms: Option<f64>,
    median_sdnn_error_ms: Option<f64>,
    median_mean_nn_error_ms: Option<f64>,
    median_binned_mae_ms: Option<f64>,
    median_binned_correlation: Option<f64>,
}

fn string_field(value: &Value, field: &str, fallback: &str) -> String {
    value
        .get(field)
        .and_then(Value::as_str)
        .unwrap_or(fallback)
        .to_string()
}

fn value_at<'a>(value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    path.iter()
        .try_fold(value, |current, key| current.get(*key))
}

fn number_at(value: &Value, path: &[&str]) -> Option<f64> {
    value_at(value, path).and_then(Value::as_f64)
}

fn push_number(values: &mut Vec<f64>, value: Option<&Value>) {
    if let Some(value) = value.and_then(Value::as_f64)
        && value.is_finite()
    {
        values.push(value);
    }
}

fn count_map_to_rows(map: BTreeMap<String, usize>) -> Vec<K18HrvCorpusCount> {
    let mut rows = map
        .into_iter()
        .map(|(key, count)| K18HrvCorpusCount { key, count })
        .collect::<Vec<_>>();
    rows.sort_by(|left, right| {
        right
            .count
            .cmp(&left.count)
            .then_with(|| left.key.cmp(&right.key))
    });
    rows
}

fn ratio_fraction(numerator: usize, denominator: usize) -> Option<f64> {
    (denominator > 0).then(|| numerator as f64 / denominator as f64)
}

fn median_and_sort(values: &mut [f64]) -> Option<f64> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(|left, right| left.total_cmp(right));
    let middle = values.len() / 2;
    if values.len() % 2 == 0 {
        Some(round_3((values[middle - 1] + values[middle]) / 2.0))
    } else {
        Some(round_3(values[middle]))
    }
}

fn round_3(value: f64) -> f64 {
    (value * 1000.0).round() / 1000.0
}
