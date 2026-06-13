use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::{
    OpenVitalsResult,
    store::{DecodedFrameRow, OpenVitalsStore},
};

pub const COMMAND_STREAM_PACKET_DELTA_REPORT_SCHEMA: &str =
    "open_vitals.command-stream-packet-delta-report.v1";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CommandStreamPacketDeltaOptions {
    pub start: String,
    pub end: String,
    #[serde(default)]
    pub baseline_start: Option<String>,
    #[serde(default)]
    pub baseline_end: Option<String>,
    #[serde(default)]
    pub capture_session_ids: Vec<String>,
    #[serde(default)]
    pub expected_packet_families: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandStreamPacketDeltaReport {
    pub schema: String,
    pub generated_by: String,
    pub pass: bool,
    pub start: String,
    pub end: String,
    #[serde(default)]
    pub baseline_start: Option<String>,
    #[serde(default)]
    pub baseline_end: Option<String>,
    pub capture_session_ids: Vec<String>,
    pub expected_packet_families: Vec<String>,
    pub observed_family_count: usize,
    pub expected_family_count: usize,
    pub present_expected_count: usize,
    pub increased_expected_count: usize,
    pub total_probe_frames: i64,
    pub total_baseline_frames: i64,
    pub family_deltas: Vec<CommandStreamPacketFamilyDelta>,
    pub issues: Vec<String>,
    pub next_actions: Vec<CommandStreamPacketDeltaNextAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandStreamPacketFamilyDelta {
    pub family: String,
    #[serde(default)]
    pub packet_type: Option<i64>,
    #[serde(default)]
    pub packet_type_name: Option<String>,
    #[serde(default)]
    pub command_or_event: Option<i64>,
    pub expected: bool,
    pub baseline_count: i64,
    pub probe_count: i64,
    pub delta_count: i64,
    pub present: bool,
    pub increased: bool,
    #[serde(default)]
    pub first_seen: Option<String>,
    #[serde(default)]
    pub last_seen: Option<String>,
    #[serde(default)]
    pub probe_first_seen: Option<String>,
    #[serde(default)]
    pub probe_last_seen: Option<String>,
    #[serde(default)]
    pub baseline_first_seen: Option<String>,
    #[serde(default)]
    pub baseline_last_seen: Option<String>,
    pub presence_attribution: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandStreamPacketDeltaNextAction {
    pub family: String,
    pub reason: String,
    pub action: String,
}

#[derive(Debug, Clone, Default)]
struct PacketFamilyAccumulator {
    packet_type: Option<i64>,
    packet_type_name: Option<String>,
    command_or_event: Option<i64>,
    count: i64,
    first_seen: Option<String>,
    last_seen: Option<String>,
}

pub fn run_command_stream_packet_delta_for_store(
    store: &OpenVitalsStore,
    options: CommandStreamPacketDeltaOptions,
) -> OpenVitalsResult<CommandStreamPacketDeltaReport> {
    let mut issues = validate_command_stream_packet_delta_options(&options);
    let expected_packet_families = normalize_expected_packet_families(&options);
    let capture_session_ids = normalize_capture_session_ids(&options.capture_session_ids);

    let probe_counts = if issues
        .iter()
        .any(|issue| issue == "start_required" || issue == "end_required")
    {
        BTreeMap::new()
    } else {
        packet_family_counts_for_window(store, &options.start, &options.end, &capture_session_ids)?
    };
    let baseline_counts = match (
        options
            .baseline_start
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty()),
        options
            .baseline_end
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty()),
    ) {
        (Some(start), Some(end)) => {
            packet_family_counts_for_window(store, start, end, &capture_session_ids)?
        }
        (None, None) => BTreeMap::new(),
        _ => {
            issues.push("baseline_window_requires_start_and_end".to_string());
            BTreeMap::new()
        }
    };

    let mut families = BTreeSet::new();
    families.extend(expected_packet_families.iter().cloned());
    families.extend(probe_counts.keys().cloned());
    families.extend(baseline_counts.keys().cloned());

    let mut family_deltas = Vec::new();
    let mut present_expected_count = 0usize;
    let mut increased_expected_count = 0usize;
    let mut next_actions = Vec::new();
    let total_probe_frames = probe_counts.values().map(|count| count.count).sum();
    let total_baseline_frames = baseline_counts.values().map(|count| count.count).sum();

    for family in families {
        let probe = probe_counts.get(&family);
        let baseline = baseline_counts.get(&family);
        let expected = expected_packet_families.contains(&family);
        let probe_count = probe.map(|count| count.count).unwrap_or(0);
        let baseline_count = baseline.map(|count| count.count).unwrap_or(0);
        let delta_count = probe_count - baseline_count;
        let present = probe_count > 0;
        let increased = if baseline_counts.is_empty() {
            probe_count > 0
        } else {
            delta_count > 0
        };
        let presence_attribution =
            packet_family_presence_attribution(probe_count, baseline_count, delta_count);
        if expected && present {
            present_expected_count += 1;
        }
        if expected && increased {
            increased_expected_count += 1;
        }
        if expected && !present {
            next_actions.push(CommandStreamPacketDeltaNextAction {
                family: family.clone(),
                reason: "expected_family_missing".to_string(),
                action: format!(
                    "Run a gated capture window that should emit {family}, then export the bundle and rerun packet-delta analysis."
                ),
            });
        }

        let representative = probe.or(baseline);
        family_deltas.push(CommandStreamPacketFamilyDelta {
            family,
            packet_type: representative.and_then(|count| count.packet_type),
            packet_type_name: representative.and_then(|count| count.packet_type_name.clone()),
            command_or_event: representative.and_then(|count| count.command_or_event),
            expected,
            baseline_count,
            probe_count,
            delta_count,
            present,
            increased,
            first_seen: earliest_time(
                probe.and_then(|count| count.first_seen.clone()),
                baseline.and_then(|count| count.first_seen.clone()),
            ),
            last_seen: latest_time(
                probe.and_then(|count| count.last_seen.clone()),
                baseline.and_then(|count| count.last_seen.clone()),
            ),
            probe_first_seen: probe.and_then(|count| count.first_seen.clone()),
            probe_last_seen: probe.and_then(|count| count.last_seen.clone()),
            baseline_first_seen: baseline.and_then(|count| count.first_seen.clone()),
            baseline_last_seen: baseline.and_then(|count| count.last_seen.clone()),
            presence_attribution,
        });
    }

    family_deltas.sort_by(|left, right| {
        right
            .expected
            .cmp(&left.expected)
            .then_with(|| right.probe_count.cmp(&left.probe_count))
            .then_with(|| left.family.cmp(&right.family))
    });

    let expected_family_count = expected_packet_families.len();
    let pass = issues.is_empty()
        && if expected_family_count == 0 {
            total_probe_frames > 0
        } else {
            present_expected_count == expected_family_count
        };

    Ok(CommandStreamPacketDeltaReport {
        schema: COMMAND_STREAM_PACKET_DELTA_REPORT_SCHEMA.to_string(),
        generated_by: "open-vitals-command-stream-packet-delta".to_string(),
        pass,
        start: options.start,
        end: options.end,
        baseline_start: options.baseline_start,
        baseline_end: options.baseline_end,
        capture_session_ids,
        expected_packet_families,
        observed_family_count: family_deltas
            .iter()
            .filter(|row| row.probe_count > 0)
            .count(),
        expected_family_count,
        present_expected_count,
        increased_expected_count,
        total_probe_frames,
        total_baseline_frames,
        family_deltas,
        issues,
        next_actions,
    })
}

fn packet_family_counts_for_window(
    store: &OpenVitalsStore,
    start: &str,
    end: &str,
    capture_session_ids: &[String],
) -> OpenVitalsResult<BTreeMap<String, PacketFamilyAccumulator>> {
    let frames = store.decoded_frames_between(start, end)?;
    let mut evidence_session_cache = BTreeMap::<String, Option<String>>::new();
    let mut counts = BTreeMap::<String, PacketFamilyAccumulator>::new();

    for frame in frames {
        if !capture_session_ids.is_empty() {
            let session_id = match evidence_session_cache.get(&frame.evidence_id) {
                Some(session_id) => session_id.clone(),
                None => {
                    let session_id = store
                        .raw_evidence(&frame.evidence_id)?
                        .and_then(|evidence| evidence.capture_session_id);
                    evidence_session_cache.insert(frame.evidence_id.clone(), session_id.clone());
                    session_id
                }
            };
            if !session_id.as_deref().is_some_and(|session_id| {
                capture_session_ids
                    .iter()
                    .any(|candidate| candidate == session_id)
            }) {
                continue;
            }
        }
        for family in packet_families_for_frame(&frame) {
            let representative_command_or_event = data_packet_k(&frame).or(frame.command_or_event);
            let accumulator = counts.entry(family).or_default();
            accumulator.packet_type = accumulator.packet_type.or(frame.packet_type);
            accumulator.packet_type_name = accumulator
                .packet_type_name
                .clone()
                .or_else(|| frame.packet_type_name.clone());
            accumulator.command_or_event = accumulator
                .command_or_event
                .or(representative_command_or_event);
            accumulator.count += 1;
            accumulator.first_seen = earliest_time(
                accumulator.first_seen.clone(),
                Some(frame.captured_at.clone()),
            );
            accumulator.last_seen = latest_time(
                accumulator.last_seen.clone(),
                Some(frame.captured_at.clone()),
            );
        }
    }

    Ok(counts)
}

fn packet_families_for_frame(frame: &DecodedFrameRow) -> Vec<String> {
    let mut families = Vec::new();
    if let Some(packet_type_name) = frame.packet_type_name.as_deref() {
        match packet_type_name {
            "COMMAND_RESPONSE" | "PUFFIN_COMMAND_RESPONSE" => {
                families.push("command_response".to_string());
                families.extend(command_response_packet_families(frame));
            }
            "REALTIME_RAW_DATA" => {
                families.push("realtime_raw_data".to_string());
            }
            "REALTIME_IMU_DATA_STREAM" | "HISTORICAL_IMU_DATA_STREAM" => {
                families.push("imu_data_stream".to_string());
            }
            _ => {}
        }
    }

    if let Some(packet_k) = data_packet_k(frame) {
        match packet_k {
            10 => families.push("K10_raw_stream".to_string()),
            11 => families.push("K11_raw_stream".to_string()),
            16 => families.push("K16_raw_ecg_labrador".to_string()),
            17 => families.push("K17_R17_optical_or_filtered".to_string()),
            18 => families.push("K18_trusted_heart_rate".to_string()),
            20 => families.push("K20_raw_or_research_stream".to_string()),
            21 => families.push("K21_raw_motion_stream".to_string()),
            24 => families.push("K24_normal_history".to_string()),
            26 => families.push("K26_pulse_information".to_string()),
            _ => {}
        }
    }

    families.sort();
    families.dedup();
    families
}

fn data_packet_k(frame: &DecodedFrameRow) -> Option<i64> {
    let value = serde_json::from_str::<serde_json::Value>(&frame.parsed_payload_json).ok()?;
    if value.get("kind").and_then(serde_json::Value::as_str) != Some("data_packet") {
        return None;
    }
    value.get("packet_k").and_then(serde_json::Value::as_i64)
}

fn command_response_packet_families(frame: &DecodedFrameRow) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&frame.parsed_payload_json) else {
        return Vec::new();
    };
    let command = value
        .get("response_to_command")
        .and_then(serde_json::Value::as_i64);
    match command {
        Some(40 | 42 | 44) => vec!["optical_afe_config".to_string()],
        Some(81 | 82) => vec!["raw_stream_packet_counts".to_string()],
        Some(132) => vec!["research_packet_config".to_string()],
        _ => Vec::new(),
    }
}

fn validate_command_stream_packet_delta_options(
    options: &CommandStreamPacketDeltaOptions,
) -> Vec<String> {
    let mut issues = Vec::new();
    if options.start.trim().is_empty() {
        issues.push("start_required".to_string());
    }
    if options.end.trim().is_empty() {
        issues.push("end_required".to_string());
    }
    if !options.start.trim().is_empty()
        && !options.end.trim().is_empty()
        && options.start.trim() >= options.end.trim()
    {
        issues.push("window_end_must_be_after_start".to_string());
    }
    issues
}

fn normalize_expected_packet_families(options: &CommandStreamPacketDeltaOptions) -> Vec<String> {
    let mut families = BTreeSet::new();
    for family in &options.expected_packet_families {
        let family = family.trim();
        if !family.is_empty() {
            families.insert(family.to_string());
        }
    }
    families.into_iter().collect()
}

fn normalize_capture_session_ids(values: &[String]) -> Vec<String> {
    let mut ids = BTreeSet::new();
    for value in values {
        let value = value.trim();
        if !value.is_empty() {
            ids.insert(value.to_string());
        }
    }
    ids.into_iter().collect()
}

fn packet_family_presence_attribution(
    probe_count: i64,
    baseline_count: i64,
    delta_count: i64,
) -> String {
    match (probe_count, baseline_count, delta_count) {
        (0, 0, _) => "not_seen".to_string(),
        (probe, 0, _) if probe > 0 => "probe_only".to_string(),
        (0, baseline, _) if baseline > 0 => "baseline_only".to_string(),
        (_, _, delta) if delta > 0 => "increased_over_baseline".to_string(),
        (_, _, 0) => "unchanged_from_baseline".to_string(),
        _ => "decreased_from_baseline".to_string(),
    }
}

fn earliest_time(left: Option<String>, right: Option<String>) -> Option<String> {
    match (left, right) {
        (Some(left), Some(right)) => Some(if left <= right { left } else { right }),
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }
}

fn latest_time(left: Option<String>, right: Option<String>) -> Option<String> {
    match (left, right) {
        (Some(left), Some(right)) => Some(if left >= right { left } else { right }),
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }
}
