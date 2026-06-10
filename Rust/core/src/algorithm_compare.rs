use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    OpenVitalsError, OpenVitalsResult,
    metrics::{
        OPENVITALS_HRV_V0_ID, OPENVITALS_HRV_V0_VERSION, OPENVITALS_SLEEP_V0_ID, OPENVITALS_SLEEP_V0_VERSION,
        OPENVITALS_SLEEP_V1_ID, OPENVITALS_SLEEP_V1_VERSION, OPENVITALS_STRAIN_V0_ID, OPENVITALS_STRAIN_V0_VERSION,
        OPENVITALS_STRESS_V0_ID, OPENVITALS_STRESS_V0_VERSION, HrvInput, SleepInput, SleepV1Input,
        StrainInput, StressInput, open_vitals_hrv_v0, open_vitals_sleep_v0, open_vitals_sleep_v1, open_vitals_strain_v0,
        open_vitals_stress_v0,
    },
    reference::{
        REFERENCE_HRV_TIME_DOMAIN_ID, REFERENCE_HRV_TIME_DOMAIN_VERSION,
        REFERENCE_SLEEP_ACTIGRAPHY_ID, REFERENCE_SLEEP_ACTIGRAPHY_VERSION,
        REFERENCE_STRAIN_EDWARDS_ID, REFERENCE_STRAIN_EDWARDS_VERSION, REFERENCE_STRESS_HRV_HR_ID,
        REFERENCE_STRESS_HRV_HR_VERSION, reference_hrv_time_domain,
        reference_sleep_actigraphy_summary, reference_strain_edwards_load,
        reference_stress_hrv_hr_proxy,
    },
};

pub const ALGORITHM_COMPARISON_SCHEMA: &str = "open_vitals.algorithm-comparison-report.v1";
pub const SLEEP_V1_BENCHMARK_COMPARISON_POLICY: &str = "sleep_v1_shared_sleep_wake_summary_fields";
pub const SLEEP_V1_BENCHMARK_REPORT_INTEGRITY_POLICY: &str =
    "sleep_v1_benchmark_requires_current_comparison_output_and_delta_integrity";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlgorithmComparisonDelta {
    pub field: String,
    pub open_vitals_path: String,
    pub reference_path: String,
    pub unit: String,
    pub open_vitals_value: f64,
    pub reference_value: f64,
    pub absolute_delta: f64,
    pub relative_delta_fraction: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlgorithmComparisonReport {
    pub schema: String,
    pub generated_by: String,
    pub family: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime_ms: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_coverage: Option<serde_json::Value>,
    pub reference_contract_valid: bool,
    pub open_vitals_output_ready: bool,
    pub reference_output_ready: bool,
    pub shared_fields_ready: bool,
    pub pass: bool,
    pub open_vitals_algorithm_id: String,
    pub open_vitals_algorithm_version: String,
    pub reference_algorithm_id: String,
    pub reference_algorithm_version: String,
    pub start_time: String,
    pub end_time: String,
    pub comparable_fields: Vec<String>,
    pub deltas: Vec<AlgorithmComparisonDelta>,
    pub non_comparable_fields: Vec<String>,
    pub open_vitals_output: Option<serde_json::Value>,
    pub reference_output: Option<serde_json::Value>,
    pub open_vitals_quality_flags: Vec<String>,
    pub reference_quality_flags: Vec<String>,
    pub quality_flags: Vec<String>,
    pub errors: Vec<String>,
    #[serde(default)]
    pub issues: Vec<String>,
    #[serde(default)]
    pub next_actions: Vec<AlgorithmComparisonNextAction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub acceptance_summary: Option<Value>,
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
pub struct AlgorithmComparisonNextAction {
    pub scope: String,
    pub reason: String,
    pub action: String,
}

pub fn compare_hrv_open_vitals_to_reference(input: &HrvInput) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let open_vitals = open_vitals_hrv_v0(input);
    let reference = reference_hrv_time_domain(input);
    let mut deltas = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));

    if let (Some(open_vitals_output), Some(reference_output)) = (&open_vitals.output, &reference.output) {
        push_delta(
            &mut deltas,
            "mean_nn_ms",
            "open_vitals_output.mean_nn_ms",
            "reference_output.mean_nn_ms",
            "ms",
            open_vitals_output.mean_nn_ms,
            reference_output.mean_nn_ms,
        );
        push_delta(
            &mut deltas,
            "rmssd_ms",
            "open_vitals_output.rmssd_ms",
            "reference_output.rmssd_ms",
            "ms",
            open_vitals_output.rmssd_ms,
            reference_output.rmssd_ms,
        );
        push_delta(
            &mut deltas,
            "sdnn_ms",
            "open_vitals_output.sdnn_ms",
            "reference_output.sdnn_sample_ms",
            "ms",
            open_vitals_output.sdnn_ms,
            reference_output.sdnn_sample_ms,
        );
        push_delta(
            &mut deltas,
            "pnn50_fraction",
            "open_vitals_output.pnn50_fraction",
            "reference_output.pnn50_fraction",
            "fraction",
            open_vitals_output.pnn50_fraction,
            reference_output.pnn50_fraction,
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    comparison_report(ComparisonParts {
        family: "hrv",
        open_vitals_algorithm_id: OPENVITALS_HRV_V0_ID,
        open_vitals_algorithm_version: OPENVITALS_HRV_V0_VERSION,
        reference_algorithm_id: REFERENCE_HRV_TIME_DOMAIN_ID,
        reference_algorithm_version: REFERENCE_HRV_TIME_DOMAIN_VERSION,
        start_time: &input.start_time,
        end_time: &input.end_time,
        deltas,
        non_comparable_fields: Vec::new(),
        open_vitals_output: serialize_optional("openVitals HRV output", &open_vitals.output)?,
        reference_output: serialize_optional("reference HRV output", &reference.output)?,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: true,
        provenance: json!({
            "input_ids": input.input_ids,
            "comparison_policy": "shared_time_domain_fields",
            "expected_values_policy": "hand-derived-reference-deltas"
        }),
    })
}

pub fn compare_sleep_open_vitals_to_reference(
    input: &SleepInput,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let open_vitals = open_vitals_sleep_v0(input);
    let reference = reference_sleep_actigraphy_summary(input);
    let mut deltas = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));

    if let (Some(open_vitals_output), Some(reference_output)) = (&open_vitals.output, &reference.output) {
        push_delta(
            &mut deltas,
            "time_in_bed_minutes",
            "open_vitals_input.time_in_bed_minutes",
            "reference_output.time_in_bed_minutes",
            "minutes",
            input.time_in_bed_minutes,
            reference_output.time_in_bed_minutes,
        );
        push_delta(
            &mut deltas,
            "sleep_minutes",
            "open_vitals_input.sleep_duration_minutes",
            "reference_output.sleep_minutes",
            "minutes",
            input.sleep_duration_minutes,
            reference_output.sleep_minutes,
        );
        push_delta(
            &mut deltas,
            "wake_minutes",
            "open_vitals_input.time_in_bed_minutes - open_vitals_input.sleep_duration_minutes",
            "reference_output.wake_minutes",
            "minutes",
            (input.time_in_bed_minutes - input.sleep_duration_minutes).max(0.0),
            reference_output.wake_minutes,
        );
        push_delta(
            &mut deltas,
            "sleep_efficiency_fraction",
            "open_vitals_output.efficiency_fraction",
            "reference_output.sleep_efficiency_fraction",
            "fraction",
            open_vitals_output.efficiency_fraction,
            reference_output.sleep_efficiency_fraction,
        );
        push_delta(
            &mut deltas,
            "wake_after_sleep_onset_minutes",
            "open_vitals_input.time_in_bed_minutes - open_vitals_input.sleep_duration_minutes",
            "reference_output.wake_after_sleep_onset_minutes",
            "minutes",
            (input.time_in_bed_minutes - input.sleep_duration_minutes).max(0.0),
            reference_output.wake_after_sleep_onset_minutes,
        );
        push_delta(
            &mut deltas,
            "disturbance_count",
            "open_vitals_input.disturbance_count",
            "reference_output.disturbance_count",
            "count",
            input.disturbance_count as f64,
            reference_output.disturbance_count as f64,
        );
        push_delta(
            &mut deltas,
            "fragmentation_index_per_hour",
            "open_vitals_input.disturbance_count / open_vitals_input.sleep_duration_hours",
            "reference_output.fragmentation_index_per_hour",
            "events_per_hour",
            fragmentation_index_per_hour(input.disturbance_count, input.sleep_duration_minutes),
            reference_output.fragmentation_index_per_hour,
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    comparison_report(ComparisonParts {
        family: "sleep",
        open_vitals_algorithm_id: OPENVITALS_SLEEP_V0_ID,
        open_vitals_algorithm_version: OPENVITALS_SLEEP_V0_VERSION,
        reference_algorithm_id: REFERENCE_SLEEP_ACTIGRAPHY_ID,
        reference_algorithm_version: REFERENCE_SLEEP_ACTIGRAPHY_VERSION,
        start_time: &input.start_time,
        end_time: &input.end_time,
        deltas,
        non_comparable_fields: vec![
            "open_vitals_output.score_0_to_100 has no benchmark-only actigraphy score equivalent"
                .to_string(),
            "open_vitals_output.sleep_debt_minutes depends on sleep need, not just the actigraphy window"
                .to_string(),
            "open_vitals_input.midpoint_deviation_minutes is a OpenVitals consistency input with no internal actigraphy-summary equivalent"
                .to_string(),
        ],
        open_vitals_output: serialize_optional("openVitals sleep output", &open_vitals.output)?,
        reference_output: serialize_optional("reference sleep output", &reference.output)?,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: true,
        provenance: json!({
            "input_ids": input.input_ids,
            "comparison_policy": "shared_sleep_window_and_actigraphy_summary_fields",
            "expected_values_policy": "hand-derived-reference-deltas"
        }),
    })
}

pub fn compare_sleep_v1_open_vitals_to_reference(
    input: &SleepV1Input,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let open_vitals = open_vitals_sleep_v1(input);
    let reference = reference_sleep_actigraphy_summary(&input.sleep);
    let mut deltas = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));

    if let (Some(open_vitals_output), Some(reference_output)) = (&open_vitals.output, &reference.output) {
        push_delta(
            &mut deltas,
            "time_in_bed_minutes",
            "open_vitals_output.time_in_bed_minutes",
            "reference_output.time_in_bed_minutes",
            "minutes",
            open_vitals_output.time_in_bed_minutes,
            reference_output.time_in_bed_minutes,
        );
        push_delta(
            &mut deltas,
            "sleep_minutes",
            "open_vitals_output.sleep_duration_minutes",
            "reference_output.sleep_minutes",
            "minutes",
            open_vitals_output.sleep_duration_minutes,
            reference_output.sleep_minutes,
        );
        push_delta(
            &mut deltas,
            "wake_minutes",
            "open_vitals_output.awake_minutes",
            "reference_output.wake_minutes",
            "minutes",
            open_vitals_output.awake_minutes,
            reference_output.wake_minutes,
        );
        push_delta(
            &mut deltas,
            "sleep_efficiency_fraction",
            "open_vitals_output.sleep_efficiency_fraction",
            "reference_output.sleep_efficiency_fraction",
            "fraction",
            open_vitals_output.sleep_efficiency_fraction,
            reference_output.sleep_efficiency_fraction,
        );
        push_delta(
            &mut deltas,
            "wake_after_sleep_onset_minutes",
            "open_vitals_output.wake_after_sleep_onset_minutes",
            "reference_output.wake_after_sleep_onset_minutes",
            "minutes",
            open_vitals_output.wake_after_sleep_onset_minutes,
            reference_output.wake_after_sleep_onset_minutes,
        );
        push_delta(
            &mut deltas,
            "disturbance_count",
            "open_vitals_input.disturbance_count",
            "reference_output.disturbance_count",
            "count",
            input.sleep.disturbance_count as f64,
            reference_output.disturbance_count as f64,
        );
        push_delta(
            &mut deltas,
            "fragmentation_index_per_hour",
            "open_vitals_input.disturbance_count / open_vitals_output.sleep_duration_hours",
            "reference_output.fragmentation_index_per_hour",
            "events_per_hour",
            fragmentation_index_per_hour(
                input.sleep.disturbance_count,
                open_vitals_output.sleep_duration_minutes,
            ),
            reference_output.fragmentation_index_per_hour,
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    let mut report = comparison_report(ComparisonParts {
        family: "sleep",
        open_vitals_algorithm_id: OPENVITALS_SLEEP_V1_ID,
        open_vitals_algorithm_version: OPENVITALS_SLEEP_V1_VERSION,
        reference_algorithm_id: REFERENCE_SLEEP_ACTIGRAPHY_ID,
        reference_algorithm_version: REFERENCE_SLEEP_ACTIGRAPHY_VERSION,
        start_time: &input.sleep.start_time,
        end_time: &input.sleep.end_time,
        deltas,
        non_comparable_fields: vec![
            "open_vitals_output.score_0_to_100 has no benchmark-only actigraphy score equivalent"
                .to_string(),
            "open_vitals_output.rolling_sleep_debt_minutes depends on prior nights and sleep need"
                .to_string(),
            "open_vitals_output.model_status has no benchmark-only actigraphy equivalent".to_string(),
            "open_vitals_output.stage_segments are heuristic and require label calibration".to_string(),
        ],
        open_vitals_output: serialize_optional("openVitals sleep v1 output", &open_vitals.output)?,
        reference_output: serialize_optional("reference sleep output", &reference.output)?,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: true,
        provenance: json!({
            "input_ids": input.sleep.input_ids,
            "comparison_policy": SLEEP_V1_BENCHMARK_COMPARISON_POLICY,
            "validation_policy": SLEEP_V1_BENCHMARK_COMPARISON_POLICY,
            "expected_values_policy": "hand-derived-reference-deltas",
            "report_integrity_policy": SLEEP_V1_BENCHMARK_REPORT_INTEGRITY_POLICY,
            "open_vitals_comparable_inputs": {
                "disturbance_count": input.sleep.disturbance_count,
                "fragmentation_index_per_hour": open_vitals
                    .output
                    .as_ref()
                    .map(|output| fragmentation_index_per_hour(
                        input.sleep.disturbance_count,
                        output.sleep_duration_minutes,
                    ))
            }
        }),
    })?;
    report.acceptance_summary = Some(sleep_v1_benchmark_acceptance_summary(&report));
    Ok(report)
}

pub fn compare_sleep_v1_open_vitals_to_external_reference_report(
    input: &SleepV1Input,
    reference_report: &serde_json::Value,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let reference = ExternalReferenceReport::from_json(reference_report)?;
    if reference.family != "sleep" {
        return Err(OpenVitalsError::message(format!(
            "external reference family {} does not match sleep comparison",
            reference.family
        )));
    }

    let open_vitals = open_vitals_sleep_v1(input);
    let mut deltas = Vec::new();
    let mut non_comparable_fields = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));
    errors.extend(
        reference
            .contract_errors
            .iter()
            .map(|error| format!("reference_contract:{error}")),
    );

    if reference.start_time != input.sleep.start_time || reference.end_time != input.sleep.end_time
    {
        errors.push(format!(
            "reference:window_mismatch:{}..{} != {}..{}",
            reference.start_time, reference.end_time, input.sleep.start_time, input.sleep.end_time
        ));
    }

    if let (Some(open_vitals_output), Some(_reference_output)) = (&open_vitals.output, &reference.output) {
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "time_in_bed_minutes",
            "open_vitals_output.time_in_bed_minutes",
            open_vitals_output.time_in_bed_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "sleep_minutes",
            "open_vitals_output.sleep_duration_minutes",
            open_vitals_output.sleep_duration_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "wake_minutes",
            "open_vitals_output.awake_minutes",
            open_vitals_output.awake_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "sleep_efficiency_fraction",
            "open_vitals_output.sleep_efficiency_fraction",
            open_vitals_output.sleep_efficiency_fraction,
            "fraction",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "wake_after_sleep_onset_minutes",
            "open_vitals_output.wake_after_sleep_onset_minutes",
            open_vitals_output.wake_after_sleep_onset_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "disturbance_count",
            "open_vitals_input.disturbance_count",
            input.sleep.disturbance_count as f64,
            "count",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "fragmentation_index_per_hour",
            "open_vitals_input.disturbance_count / open_vitals_output.sleep_duration_hours",
            fragmentation_index_per_hour(
                input.sleep.disturbance_count,
                open_vitals_output.sleep_duration_minutes,
            ),
            "events_per_hour",
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    non_comparable_fields.extend([
        "open_vitals_output.score_0_to_100 has no external actigraphy summary score equivalent"
            .to_string(),
        "open_vitals_output.rolling_sleep_debt_minutes depends on prior nights and sleep need"
            .to_string(),
        "open_vitals_output.model_status has no external actigraphy equivalent".to_string(),
        "open_vitals_output.stage_segments are heuristic and require label calibration".to_string(),
    ]);

    let mut report = comparison_report(ComparisonParts {
        family: "sleep",
        open_vitals_algorithm_id: OPENVITALS_SLEEP_V1_ID,
        open_vitals_algorithm_version: OPENVITALS_SLEEP_V1_VERSION,
        reference_algorithm_id: &reference.algorithm_id,
        reference_algorithm_version: &reference.algorithm_version,
        start_time: &input.sleep.start_time,
        end_time: &input.sleep.end_time,
        deltas,
        non_comparable_fields,
        open_vitals_output: serialize_optional("openVitals sleep v1 output", &open_vitals.output)?,
        reference_output: reference.output,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: reference.contract_errors.is_empty(),
        provenance: json!({
            "input_ids": input.sleep.input_ids,
            "comparison_policy": SLEEP_V1_BENCHMARK_COMPARISON_POLICY,
            "validation_policy": SLEEP_V1_BENCHMARK_COMPARISON_POLICY,
            "reference_report_schema": reference.schema,
            "reference_report_provenance": reference.provenance,
            "expected_values_policy": "external-reference-report-deltas",
            "report_integrity_policy": SLEEP_V1_BENCHMARK_REPORT_INTEGRITY_POLICY,
            "open_vitals_comparable_inputs": {
                "disturbance_count": input.sleep.disturbance_count,
                "fragmentation_index_per_hour": open_vitals
                    .output
                    .as_ref()
                    .map(|output| fragmentation_index_per_hour(
                        input.sleep.disturbance_count,
                        output.sleep_duration_minutes,
                    ))
            }
        }),
    })?;
    report.acceptance_summary = Some(sleep_v1_benchmark_acceptance_summary(&report));
    Ok(report)
}

pub fn compare_sleep_open_vitals_to_external_reference_report(
    input: &SleepInput,
    reference_report: &serde_json::Value,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let reference = ExternalReferenceReport::from_json(reference_report)?;
    if reference.family != "sleep" {
        return Err(OpenVitalsError::message(format!(
            "external reference family {} does not match sleep comparison",
            reference.family
        )));
    }

    let open_vitals = open_vitals_sleep_v0(input);
    let mut deltas = Vec::new();
    let mut non_comparable_fields = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));
    errors.extend(
        reference
            .contract_errors
            .iter()
            .map(|error| format!("reference_contract:{error}")),
    );

    if reference.start_time != input.start_time || reference.end_time != input.end_time {
        errors.push(format!(
            "reference:window_mismatch:{}..{} != {}..{}",
            reference.start_time, reference.end_time, input.start_time, input.end_time
        ));
    }

    if let (Some(open_vitals_output), Some(_reference_output)) = (&open_vitals.output, &reference.output) {
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "time_in_bed_minutes",
            "open_vitals_input.time_in_bed_minutes",
            input.time_in_bed_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "sleep_minutes",
            "open_vitals_input.sleep_duration_minutes",
            input.sleep_duration_minutes,
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "wake_minutes",
            "open_vitals_input.time_in_bed_minutes - open_vitals_input.sleep_duration_minutes",
            (input.time_in_bed_minutes - input.sleep_duration_minutes).max(0.0),
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "sleep_efficiency_fraction",
            "open_vitals_output.efficiency_fraction",
            open_vitals_output.efficiency_fraction,
            "fraction",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "wake_after_sleep_onset_minutes",
            "open_vitals_input.time_in_bed_minutes - open_vitals_input.sleep_duration_minutes",
            (input.time_in_bed_minutes - input.sleep_duration_minutes).max(0.0),
            "minutes",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "disturbance_count",
            "open_vitals_input.disturbance_count",
            input.disturbance_count as f64,
            "count",
        );
        push_sleep_external_delta(
            &mut deltas,
            &mut non_comparable_fields,
            &mut errors,
            &reference,
            "fragmentation_index_per_hour",
            "open_vitals_input.disturbance_count / open_vitals_input.sleep_duration_hours",
            fragmentation_index_per_hour(input.disturbance_count, input.sleep_duration_minutes),
            "events_per_hour",
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    non_comparable_fields.extend([
        "open_vitals_output.score_0_to_100 has no external actigraphy summary score equivalent"
            .to_string(),
        "open_vitals_output.sleep_debt_minutes depends on sleep need, not just the external actigraphy window"
            .to_string(),
        "open_vitals_input.midpoint_deviation_minutes is a OpenVitals consistency input with no external actigraphy-summary equivalent"
            .to_string(),
    ]);

    comparison_report(ComparisonParts {
        family: "sleep",
        open_vitals_algorithm_id: OPENVITALS_SLEEP_V0_ID,
        open_vitals_algorithm_version: OPENVITALS_SLEEP_V0_VERSION,
        reference_algorithm_id: &reference.algorithm_id,
        reference_algorithm_version: &reference.algorithm_version,
        start_time: &input.start_time,
        end_time: &input.end_time,
        deltas,
        non_comparable_fields,
        open_vitals_output: serialize_optional("openVitals sleep output", &open_vitals.output)?,
        reference_output: reference.output,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: reference.contract_errors.is_empty(),
        provenance: json!({
            "input_ids": input.input_ids,
            "comparison_policy": "external_sleep_reference_shared_fields",
            "reference_report_schema": reference.schema,
            "reference_report_provenance": reference.provenance,
            "expected_values_policy": "external-reference-report-deltas"
        }),
    })
}

pub fn compare_strain_open_vitals_to_reference(
    input: &StrainInput,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let open_vitals = open_vitals_strain_v0(input);
    let reference = reference_strain_edwards_load(input);
    let mut deltas = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));

    if let (Some(open_vitals_output), Some(reference_output)) = (&open_vitals.output, &reference.output) {
        push_delta(
            &mut deltas,
            "zone_load",
            "open_vitals_output.zone_load",
            "reference_output.edwards_load",
            "weighted_zone_minutes",
            open_vitals_output.zone_load,
            reference_output.edwards_load,
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    comparison_report(ComparisonParts {
        family: "strain",
        open_vitals_algorithm_id: OPENVITALS_STRAIN_V0_ID,
        open_vitals_algorithm_version: OPENVITALS_STRAIN_V0_VERSION,
        reference_algorithm_id: REFERENCE_STRAIN_EDWARDS_ID,
        reference_algorithm_version: REFERENCE_STRAIN_EDWARDS_VERSION,
        start_time: &input.start_time,
        end_time: &input.end_time,
        deltas,
        non_comparable_fields: vec![
            "open_vitals_output.score_0_to_21 has no Edwards-zone-load score equivalent".to_string(),
            "open_vitals_output.average_hr_reserve_fraction is not part of Edwards zone load".to_string(),
            "reference_output.edwards_load_per_hour is not emitted by OpenVitals strain v0".to_string(),
        ],
        open_vitals_output: serialize_optional("openVitals strain output", &open_vitals.output)?,
        reference_output: serialize_optional("reference strain output", &reference.output)?,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: true,
        provenance: json!({
            "input_ids": input.input_ids,
            "comparison_policy": "shared_zone_load_only",
            "expected_values_policy": "hand-derived-reference-deltas"
        }),
    })
}

pub fn compare_stress_open_vitals_to_reference(
    input: &StressInput,
) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let open_vitals = open_vitals_stress_v0(input);
    let reference = reference_stress_hrv_hr_proxy(input);
    let mut deltas = Vec::new();
    let mut quality_flags = Vec::new();
    let mut errors = prefixed_errors("openVitals", &open_vitals.errors);
    errors.extend(prefixed_errors("reference", &reference.errors));

    if let (Some(open_vitals_output), Some(reference_output)) = (&open_vitals.output, &reference.output) {
        push_delta(
            &mut deltas,
            "heart_rate_elevation_score",
            "open_vitals_output.heart_rate_elevation_score",
            "reference_output.heart_rate_elevation_score",
            "score_0_to_100",
            open_vitals_output.heart_rate_elevation_score,
            reference_output.heart_rate_elevation_score,
        );
        push_delta(
            &mut deltas,
            "hrv_suppression_score",
            "open_vitals_output.hrv_suppression_score",
            "reference_output.hrv_suppression_score",
            "score_0_to_100",
            open_vitals_output.hrv_suppression_score,
            reference_output.hrv_suppression_score,
        );
    } else {
        quality_flags.push("comparison_outputs_missing".to_string());
    }

    comparison_report(ComparisonParts {
        family: "stress",
        open_vitals_algorithm_id: OPENVITALS_STRESS_V0_ID,
        open_vitals_algorithm_version: OPENVITALS_STRESS_V0_VERSION,
        reference_algorithm_id: REFERENCE_STRESS_HRV_HR_ID,
        reference_algorithm_version: REFERENCE_STRESS_HRV_HR_VERSION,
        start_time: &input.start_time,
        end_time: &input.end_time,
        deltas,
        non_comparable_fields: vec![
            "open_vitals_output.score_0_to_100 includes motion adjustment while the reference proxy is unadjusted".to_string(),
            "open_vitals_output.motion_adjusted_hr_score has no reference proxy equivalent".to_string(),
            "reference_output.unadjusted_stress_score_0_to_100 ignores motion context".to_string(),
        ],
        open_vitals_output: serialize_optional("openVitals stress output", &open_vitals.output)?,
        reference_output: serialize_optional("reference stress output", &reference.output)?,
        open_vitals_quality_flags: open_vitals.quality_flags,
        reference_quality_flags: reference.quality_flags,
        quality_flags,
        errors,
        reference_contract_valid: true,
        provenance: json!({
            "input_ids": input.input_ids,
            "comparison_policy": "shared_hr_elevation_and_hrv_suppression_fields",
            "expected_values_policy": "hand-derived-reference-deltas"
        }),
    })
}

struct ComparisonParts<'a> {
    family: &'a str,
    open_vitals_algorithm_id: &'a str,
    open_vitals_algorithm_version: &'a str,
    reference_algorithm_id: &'a str,
    reference_algorithm_version: &'a str,
    start_time: &'a str,
    end_time: &'a str,
    deltas: Vec<AlgorithmComparisonDelta>,
    non_comparable_fields: Vec<String>,
    open_vitals_output: Option<serde_json::Value>,
    reference_output: Option<serde_json::Value>,
    open_vitals_quality_flags: Vec<String>,
    reference_quality_flags: Vec<String>,
    quality_flags: Vec<String>,
    errors: Vec<String>,
    reference_contract_valid: bool,
    provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
struct ExternalReferenceReport {
    schema: String,
    family: String,
    algorithm_id: String,
    algorithm_version: String,
    start_time: String,
    end_time: String,
    #[serde(default)]
    provider: Option<String>,
    #[serde(default)]
    provider_version: Option<String>,
    #[serde(default)]
    source: Option<String>,
    #[serde(default)]
    license: Option<String>,
    #[serde(default = "empty_object")]
    output_units: serde_json::Value,
    #[serde(default)]
    output: Option<serde_json::Value>,
    #[serde(default)]
    quality_flags: Vec<String>,
    #[serde(default)]
    errors: Vec<String>,
    #[serde(default = "empty_object")]
    provenance: serde_json::Value,
    #[serde(skip)]
    contract_errors: Vec<String>,
}

impl ExternalReferenceReport {
    fn from_json(value: &serde_json::Value) -> OpenVitalsResult<Self> {
        let mut report: ExternalReferenceReport =
            serde_json::from_value(value.clone()).map_err(|error| {
                OpenVitalsError::message(format!("invalid external reference report: {error}"))
            })?;
        if !matches!(
            report.schema.as_str(),
            "open_vitals.reference-algo-report.v1" | "open_vitals.external-reference-output.v1"
        ) {
            return Err(OpenVitalsError::message(format!(
                "unsupported external reference report schema {}",
                report.schema
            )));
        }
        report.contract_errors = report.contract_errors();
        Ok(report)
    }

    fn contract_errors(&self) -> Vec<String> {
        let mut errors = Vec::new();
        if !non_empty_object(&self.provenance) {
            errors.push("missing_provenance".to_string());
        }
        match self.schema.as_str() {
            "open_vitals.external-reference-output.v1" => {
                require_optional_non_empty("provider", &self.provider, &mut errors);
                require_optional_non_empty("provider_version", &self.provider_version, &mut errors);
                require_optional_non_empty("source", &self.source, &mut errors);
                require_optional_non_empty("license", &self.license, &mut errors);
                if !self.output_units.is_object() {
                    errors.push("output_units_must_be_object".to_string());
                }
            }
            "open_vitals.reference-algo-report.v1" => {
                if self
                    .provenance
                    .get("provider_kind")
                    .and_then(|value| value.as_str())
                    .is_none_or(str::is_empty)
                {
                    errors.push("missing_provider_kind".to_string());
                }
            }
            _ => {}
        }

        if let Some(output) = &self.output {
            if !output.is_object() {
                errors.push("output_must_be_object".to_string());
            }
            for (field, expected_unit) in SLEEP_EXTERNAL_COMPARABLE_UNITS {
                if output.get(*field).is_some() {
                    match self.unit_for_field(field) {
                        Some(actual_unit) if actual_unit == *expected_unit => {}
                        Some(actual_unit) => errors.push(format!(
                            "output_unit_mismatch:{field}:expected_{expected_unit}:actual_{actual_unit}"
                        )),
                        None => errors.push(format!("missing_output_unit:{field}")),
                    }
                }
            }
        } else if self.errors.is_empty() {
            errors.push("output_required_when_errors_empty".to_string());
        }
        errors.sort();
        errors.dedup();
        errors
    }

    fn unit_for_field(&self, field: &str) -> Option<&str> {
        self.output_units
            .get(field)
            .and_then(|value| value.as_str())
            .or_else(|| {
                self.provenance
                    .get("output_units")
                    .and_then(|value| value.get(field))
                    .and_then(|value| value.as_str())
            })
    }
}

fn comparison_report(parts: ComparisonParts<'_>) -> OpenVitalsResult<AlgorithmComparisonReport> {
    let mut quality_flags = parts.quality_flags;
    let mut errors = parts.errors;
    for delta in &parts.deltas {
        if !delta.absolute_delta.is_finite()
            || !delta
                .relative_delta_fraction
                .map(|value| value.is_finite())
                .unwrap_or(true)
        {
            errors.push(format!("non_finite_delta:{}", delta.field));
        }
    }
    errors.sort();
    errors.dedup();
    if parts.deltas.is_empty() {
        quality_flags.push("no_comparable_fields_ready".to_string());
    }
    let next_actions = algorithm_comparison_next_actions(&quality_flags, &errors);
    let open_vitals_output_ready = parts.open_vitals_output.is_some();
    let reference_output_ready = parts.reference_output.is_some();
    let shared_fields_ready = !parts.deltas.is_empty();
    let reference_contract_valid = parts.reference_contract_valid;
    let data_coverage = comparison_data_coverage(
        parts.family,
        parts.open_vitals_algorithm_id,
        parts.open_vitals_output.as_ref(),
    );

    Ok(AlgorithmComparisonReport {
        schema: ALGORITHM_COMPARISON_SCHEMA.to_string(),
        generated_by: "open_vitals.algorithm_compare".to_string(),
        family: parts.family.to_string(),
        runtime_ms: None,
        data_coverage,
        reference_contract_valid,
        open_vitals_output_ready,
        reference_output_ready,
        shared_fields_ready,
        pass: errors.is_empty() && shared_fields_ready && reference_contract_valid,
        open_vitals_algorithm_id: parts.open_vitals_algorithm_id.to_string(),
        open_vitals_algorithm_version: parts.open_vitals_algorithm_version.to_string(),
        reference_algorithm_id: parts.reference_algorithm_id.to_string(),
        reference_algorithm_version: parts.reference_algorithm_version.to_string(),
        start_time: parts.start_time.to_string(),
        end_time: parts.end_time.to_string(),
        comparable_fields: parts
            .deltas
            .iter()
            .map(|delta| delta.field.clone())
            .collect(),
        deltas: parts.deltas,
        non_comparable_fields: parts.non_comparable_fields,
        open_vitals_output: parts.open_vitals_output,
        reference_output: parts.reference_output,
        open_vitals_quality_flags: parts.open_vitals_quality_flags,
        reference_quality_flags: parts.reference_quality_flags,
        quality_flags,
        errors,
        issues: Vec::new(),
        next_actions,
        acceptance_summary: None,
        provenance: parts.provenance,
    })
}

pub(crate) fn sleep_v1_benchmark_acceptance_summary(report: &AlgorithmComparisonReport) -> Value {
    let coverage = report
        .data_coverage
        .as_ref()
        .and_then(|coverage| coverage.get("open_vitals_output_data_coverage_fraction"))
        .and_then(Value::as_f64);
    json!({
        "policy": "sleep_v1_benchmark_must_match_reference_contract_deltas_and_embedded_output",
        "pass": report.pass,
        "benchmark_ready": report.pass
            && report.reference_contract_valid
            && report.open_vitals_output_ready
            && report.reference_output_ready
            && report.shared_fields_ready
            && report.quality_flags.is_empty()
            && report.open_vitals_quality_flags.is_empty()
            && report.reference_quality_flags.is_empty()
            && report.errors.is_empty()
            && report.issues.is_empty()
            && report.next_actions.is_empty(),
        "reference_contract_valid": report.reference_contract_valid,
        "open_vitals_output_ready": report.open_vitals_output_ready,
        "reference_output_ready": report.reference_output_ready,
        "shared_fields_ready": report.shared_fields_ready,
        "open_vitals_algorithm_id": report.open_vitals_algorithm_id,
        "open_vitals_algorithm_version": report.open_vitals_algorithm_version,
        "reference_algorithm_id": report.reference_algorithm_id,
        "reference_algorithm_version": report.reference_algorithm_version,
        "start_time": report.start_time,
        "end_time": report.end_time,
        "comparable_fields": report.comparable_fields,
        "delta_count": report.deltas.len(),
        "non_comparable_field_count": report.non_comparable_fields.len(),
        "data_coverage_fraction": coverage,
        "open_vitals_quality_flag_count": report.open_vitals_quality_flags.len(),
        "reference_quality_flag_count": report.reference_quality_flags.len(),
        "quality_flag_count": report.quality_flags.len(),
        "issue_count": report.issues.len(),
        "error_count": report.errors.len(),
        "next_action_count": report.next_actions.len(),
    })
}

fn comparison_data_coverage(
    family: &str,
    open_vitals_algorithm_id: &str,
    open_vitals_output: Option<&serde_json::Value>,
) -> Option<serde_json::Value> {
    if family != "sleep" || open_vitals_algorithm_id != OPENVITALS_SLEEP_V1_ID {
        return None;
    }
    let coverage = open_vitals_output?
        .get("data_coverage_fraction")
        .and_then(serde_json::Value::as_f64)?;
    if !coverage.is_finite() || !(0.0..=1.0).contains(&coverage) {
        return None;
    }
    Some(json!({
        "open_vitals_output_data_coverage_fraction": coverage,
    }))
}

fn push_delta(
    deltas: &mut Vec<AlgorithmComparisonDelta>,
    field: &str,
    open_vitals_path: &str,
    reference_path: &str,
    unit: &str,
    open_vitals_value: f64,
    reference_value: f64,
) {
    let absolute_delta = open_vitals_value - reference_value;
    let relative_delta_fraction = if reference_value.abs() < f64::EPSILON {
        None
    } else {
        Some(absolute_delta / reference_value.abs())
    };
    deltas.push(AlgorithmComparisonDelta {
        field: field.to_string(),
        open_vitals_path: open_vitals_path.to_string(),
        reference_path: reference_path.to_string(),
        unit: unit.to_string(),
        open_vitals_value,
        reference_value,
        absolute_delta,
        relative_delta_fraction,
    });
}

fn push_sleep_external_delta(
    deltas: &mut Vec<AlgorithmComparisonDelta>,
    non_comparable_fields: &mut Vec<String>,
    errors: &mut Vec<String>,
    reference: &ExternalReferenceReport,
    field: &str,
    open_vitals_path: &str,
    open_vitals_value: f64,
    unit: &str,
) {
    let Some(reference_output) = reference.output.as_ref() else {
        non_comparable_fields.push(format!(
            "reference_output.{field} missing because external sleep reference has no output"
        ));
        return;
    };
    if let Some(reference_value) = reference_output.get(field).and_then(|value| value.as_f64()) {
        match reference.unit_for_field(field) {
            Some(actual_unit) if actual_unit == unit => {}
            Some(actual_unit) => {
                errors.push(format!(
                    "reference_contract:output_unit_mismatch:{field}:expected_{unit}:actual_{actual_unit}"
                ));
                non_comparable_fields.push(format!(
                    "reference_output.{field} has unit {actual_unit}, expected {unit}"
                ));
                return;
            }
            None => {
                errors.push(format!("reference_contract:missing_output_unit:{field}"));
                non_comparable_fields.push(format!(
                    "reference_output.{field} missing output unit metadata"
                ));
                return;
            }
        }
        push_delta(
            deltas,
            field,
            open_vitals_path,
            &format!("reference_output.{field}"),
            unit,
            open_vitals_value,
            reference_value,
        );
    } else {
        non_comparable_fields.push(format!(
            "reference_output.{field} missing from external sleep reference report"
        ));
    }
}

fn fragmentation_index_per_hour(disturbance_count: u32, sleep_duration_minutes: f64) -> f64 {
    if sleep_duration_minutes > 0.0 {
        disturbance_count as f64 / (sleep_duration_minutes / 60.0)
    } else {
        0.0
    }
}

fn prefixed_errors(prefix: &str, errors: &[String]) -> Vec<String> {
    errors
        .iter()
        .map(|error| format!("{prefix}:{error}"))
        .collect()
}

fn serialize_optional<T: Serialize>(
    label: &str,
    output: &Option<T>,
) -> OpenVitalsResult<Option<serde_json::Value>> {
    output
        .as_ref()
        .map(serde_json::to_value)
        .transpose()
        .map_err(|error| OpenVitalsError::message(format!("cannot serialize {label}: {error}")))
}

fn empty_object() -> serde_json::Value {
    json!({})
}

const SLEEP_EXTERNAL_COMPARABLE_UNITS: &[(&str, &str)] = &[
    ("time_in_bed_minutes", "minutes"),
    ("sleep_minutes", "minutes"),
    ("wake_minutes", "minutes"),
    ("sleep_efficiency_fraction", "fraction"),
    ("wake_after_sleep_onset_minutes", "minutes"),
    ("disturbance_count", "count"),
    ("fragmentation_index_per_hour", "events_per_hour"),
];

fn non_empty_object(value: &serde_json::Value) -> bool {
    value.as_object().is_some_and(|object| !object.is_empty())
}

fn require_optional_non_empty(field: &str, value: &Option<String>, errors: &mut Vec<String>) {
    if value.as_deref().is_none_or(|value| value.trim().is_empty()) {
        errors.push(format!("missing_{field}"));
    }
}

pub(crate) fn algorithm_comparison_next_actions(
    quality_flags: &[String],
    errors: &[String],
) -> Vec<AlgorithmComparisonNextAction> {
    let mut actions = Vec::new();
    for flag in quality_flags {
        actions.push(algorithm_comparison_quality_action(flag));
    }
    for error in errors {
        actions.push(algorithm_comparison_error_action(error));
    }
    actions
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn algorithm_comparison_quality_action(flag: &str) -> AlgorithmComparisonNextAction {
    match flag {
        "comparison_outputs_missing" => AlgorithmComparisonNextAction {
            scope: "outputs".to_string(),
            reason: "comparison_outputs_missing".to_string(),
            action: "Fix OpenVitals/reference input requirements so both algorithms emit outputs before comparing shared fields.".to_string(),
        },
        "no_comparable_fields_ready" => AlgorithmComparisonNextAction {
            scope: "comparable_fields".to_string(),
            reason: "no_comparable_fields_ready".to_string(),
            action: "Use a supported family and valid inputs that produce at least one shared comparable field.".to_string(),
        },
        other => AlgorithmComparisonNextAction {
            scope: "comparison".to_string(),
            reason: other.to_string(),
            action: "Inspect the comparison quality flag and decide whether the benchmark inputs or field mapping need repair.".to_string(),
        },
    }
}

fn algorithm_comparison_error_action(error: &str) -> AlgorithmComparisonNextAction {
    if let Some(field) = error.strip_prefix("non_finite_delta:") {
        AlgorithmComparisonNextAction {
            scope: field.to_string(),
            reason: "non_finite_delta".to_string(),
            action: "Check the OpenVitals and reference outputs for non-finite values before trusting this delta.".to_string(),
        }
    } else if let Some(error) = error.strip_prefix("reference_contract:") {
        let reason = if error.starts_with("missing_output_unit:") {
            "reference_output_unit_missing"
        } else if error.starts_with("output_unit_mismatch:") {
            "reference_output_unit_mismatch"
        } else if error == "missing_provenance" {
            "reference_provenance_missing"
        } else if error.starts_with("missing_") {
            "reference_metadata_missing"
        } else {
            "reference_contract_invalid"
        };
        AlgorithmComparisonNextAction {
            scope: "reference_contract".to_string(),
            reason: reason.to_string(),
            action: format!(
                "Regenerate the reference report through open-vitals-reference-algo-runner or a validated adapter so provider metadata, output units, and provenance satisfy the benchmark contract; issue `{error}`."
            ),
        }
    } else if let Some(error) = error.strip_prefix("openVitals:") {
        AlgorithmComparisonNextAction {
            scope: "openVitals".to_string(),
            reason: "open_vitals_algorithm_error".to_string(),
            action: format!(
                "Fix the OpenVitals algorithm input or implementation error `{error}` before using this comparison."
            ),
        }
    } else if let Some(error) = error.strip_prefix("reference:") {
        AlgorithmComparisonNextAction {
            scope: "reference".to_string(),
            reason: "reference_algorithm_error".to_string(),
            action: format!(
                "Fix the reference benchmark input or mapping error `{error}` before using this comparison."
            ),
        }
    } else {
        AlgorithmComparisonNextAction {
            scope: "comparison".to_string(),
            reason: "algorithm_comparison_error".to_string(),
            action: "Inspect the comparison error and repair the benchmark inputs or field mapping before trusting the report.".to_string(),
        }
    }
}
