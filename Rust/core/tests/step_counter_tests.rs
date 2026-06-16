use open_vitals_core::{
    protocol::{PACKET_TYPE_HISTORICAL_DATA, build_v5_payload_frame},
    step_counter::{
        ActivityUnavailableDailyStatusOptions, OPENVITALS_ACTIVITY_UNAVAILABLE_STATUS_V0_ID,
        OPENVITALS_ACTIVITY_UNAVAILABLE_STATUS_V0_VERSION, OPENVITALS_STEPS_DEVICE_COUNTER_V0_ID,
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_VERSION, StepCounterDailyRollupOptions,
        StepCounterHourlyRollupOptions, StepCounterIngestOptions, persist_step_counter_discovery,
        rollup_activity_unavailable_daily_status_for_store, rollup_device_step_counter_day,
        rollup_device_step_counter_hour, run_step_counter_ingest_for_store,
    },
    step_discovery::{
        StepCaptureValidationOptions, StepPacketDiscoveryOptions, run_step_capture_validation,
        run_step_packet_discovery,
    },
    store::{
        DailyActivityMetricInput, DecodedFrameRow, OpenVitalsStore, RawEvidenceInput,
        StepCounterSampleInput,
    },
};
use serde_json::json;

#[test]
fn step_counter_ingest_persists_decoded_device_counter_candidates() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    let rows = vec![
        decoded_frame_row(
            "step-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "step_count": 4100,
                    "cadence": 92,
                    "activity": 2
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "step-frame-2",
            "2026-06-02T12:02:00.250Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "step_count": "4200",
                    "cadence": "101.5",
                    "activity": "walking"
                },
                "warnings": []
            }),
        ),
    ];
    let discovery = run_step_packet_discovery(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepPacketDiscoveryOptions::default(),
    )
    .unwrap();

    let report = persist_step_counter_discovery(
        &store,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        discovery,
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.schema, "open_vitals.step-counter-ingest-report.v1");
    assert_eq!(report.counter_candidate_count, 2);
    assert_eq!(report.cadence_sample_count, 2);
    assert_eq!(report.activity_state_sample_count, 2);
    assert_eq!(report.persisted_sample_count, 2);
    assert_eq!(report.inserted_sample_count, 2);
    assert_eq!(store.table_count("step_counter_samples").unwrap(), 2);
    let samples = store
        .step_counter_samples_between(1_780_355_000_000, 1_780_442_000_000)
        .unwrap();
    assert_eq!(samples.len(), 2);
    assert_eq!(samples[0].counter_value, 4100);
    assert_eq!(samples[0].cadence_spm, Some(92.0));
    assert_eq!(samples[0].activity_state.as_deref(), Some("2"));
    assert_eq!(samples[1].counter_value, 4200);
    assert_eq!(samples[1].cadence_spm, Some(101.5));
    assert_eq!(samples[1].activity_state.as_deref(), Some("walking"));
    assert_eq!(samples[0].source_kind, "device_counter");
}

#[test]
fn step_counter_ingest_persists_decoded_step_motion_counter_candidates() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    let rows = vec![
        decoded_frame_row(
            "step-motion-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 18,
                "domain": "normal_history_with_hr_marker",
                "body_summary": {
                    "kind": "normal_history",
                    "heart_rate_bpm": 82,
                    "rr_count": 1,
                    "rr_intervals_ms": [732],
                    "step_motion_counter": 65500
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "step-motion-frame-2",
            "2026-06-02T12:02:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 18,
                "domain": "normal_history_with_hr_marker",
                "body_summary": {
                    "kind": "normal_history",
                    "heart_rate_bpm": 88,
                    "rr_count": 1,
                    "rr_intervals_ms": [681],
                    "step_motion_counter": 30
                },
                "warnings": []
            }),
        ),
    ];
    let discovery = run_step_packet_discovery(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepPacketDiscoveryOptions::default(),
    )
    .unwrap();

    assert!(discovery.pass, "{:?}", discovery.issues);
    assert!(discovery.explicit_step_counter_found);
    assert_eq!(
        discovery
            .candidate_fields
            .iter()
            .filter(|candidate| candidate.match_kind == "step_count")
            .count(),
        2
    );

    let report = persist_step_counter_discovery(
        &store,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        discovery,
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.persisted_sample_count, 2);
    let samples = store
        .step_counter_samples_between(1_780_355_000_000, 1_780_442_000_000)
        .unwrap();
    assert_eq!(samples.len(), 2);
    assert_eq!(samples[0].counter_value, 65_500);
    assert_eq!(samples[0].json_path, "$.body_summary.step_motion_counter");
    assert_eq!(
        samples[0].packet_family,
        "K18/normal_history_with_hr_marker"
    );
    assert_eq!(samples[1].counter_value, 30);
}

#[test]
fn step_counter_ingest_reparses_raw_evidence_when_decoded_rows_are_stale() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    let mut payload = vec![0; 52];
    payload[0] = PACKET_TYPE_HISTORICAL_DATA;
    payload[1] = 18;
    payload[14] = 82;
    payload[15] = 0;
    put_u16(&mut payload, 49, 4_242);
    let frame = build_v5_payload_frame(&payload);
    store
        .insert_raw_evidence(RawEvidenceInput {
            evidence_id: "raw-k18-step-motion-counter",
            source: "synthetic.fixture",
            captured_at: "2026-06-02T12:00:00.000Z",
            device_model: "OpenVitals test wearable",
            payload: &frame,
            sensitivity: "public-test-fixture",
            capture_session_id: None,
        })
        .unwrap();

    let report = run_step_counter_ingest_for_store(
        &store,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepCounterIngestOptions::default(),
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.discovery.decoded_frame_count, 1);
    assert!(report.explicit_step_counter_found);
    assert_eq!(report.persisted_sample_count, 1);
    assert_eq!(report.inserted_sample_count, 1);
    let samples = store
        .step_counter_samples_between(1_780_355_000_000, 1_780_442_000_000)
        .unwrap();
    assert_eq!(samples.len(), 1);
    assert_eq!(samples[0].counter_value, 4_242);
    assert_eq!(
        samples[0].evidence_id.as_deref(),
        Some("raw-k18-step-motion-counter")
    );
    assert_eq!(samples[0].json_path, "$.body_summary.step_motion_counter");
}

#[test]
fn step_discovery_surfaces_unnamed_monotonic_counter_candidates_without_promoting() {
    let rows = vec![
        decoded_frame_row(
            "hidden-step-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "field_7": 4100,
                    "sample_count": 24
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "hidden-step-frame-2",
            "2026-06-02T12:02:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "field_7": 4200,
                    "sample_count": 24
                },
                "warnings": []
            }),
        ),
    ];

    let discovery = run_step_packet_discovery(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepPacketDiscoveryOptions::default(),
    )
    .unwrap();

    assert!(!discovery.pass);
    assert!(!discovery.explicit_step_counter_found);
    assert_eq!(discovery.monotonic_counter_candidate_count, 1);
    assert_eq!(discovery.emitted_monotonic_counter_sample_count, 2);
    assert_eq!(discovery.counter_delta_candidate_count, 1);
    assert_eq!(discovery.monotonic_counter_delta_candidate_count, 1);
    assert_eq!(discovery.candidate_field_count, 2);
    assert_eq!(discovery.candidate_fields.len(), 2);
    assert_eq!(discovery.counter_deltas[0].delta, 100);
    assert_eq!(discovery.counter_deltas[0].rank, 1);
    assert!(discovery.counter_deltas[0].selected);
    assert_eq!(
        discovery.counter_deltas[0].selection_reason,
        "hidden_monotonic_counter_delta"
    );
    assert_eq!(
        discovery.selected_counter_delta.as_ref().unwrap().delta,
        100
    );
    assert_eq!(
        discovery.counter_deltas[0].match_kind,
        "monotonic_counter_candidate"
    );
    assert_eq!(
        discovery.counter_deltas[0].json_path,
        "$.body_summary.field_7"
    );
    assert_eq!(discovery.counter_deltas[0].matches_manual_label, None);
    assert_eq!(discovery.counter_deltas[0].matches_official_label, None);
    assert_eq!(
        discovery.candidate_fields[0].match_kind,
        "monotonic_counter_candidate"
    );
    assert_eq!(
        discovery.candidate_fields[0].source_kind_inference,
        "device_counter_candidate"
    );
    assert_eq!(
        discovery.candidate_fields[0].json_path,
        "$.body_summary.field_7"
    );
    assert!(
        discovery
            .candidate_fields
            .iter()
            .all(|candidate| candidate.field_name != "sample_count")
    );
    assert!(
        discovery
            .issues
            .contains(&"no_explicit_step_counter_field_found".to_string())
    );
    assert!(
        discovery
            .issues
            .contains(&"unnamed_monotonic_counter_candidates_found".to_string())
    );
    let parser_action = discovery
        .next_actions
        .iter()
        .find(|action| action.reason == "unnamed_monotonic_counter_candidates_found")
        .unwrap();
    assert!(
        parser_action
            .action
            .contains("Selected decoded path `$.body_summary.field_7` rank 1 delta 100")
    );
}

#[test]
fn step_validation_compares_unnamed_counter_candidates_but_requires_parser_mapping() {
    let rows = vec![
        decoded_frame_row(
            "hidden-validation-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "field_7": 4100
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "hidden-validation-frame-2",
            "2026-06-02T12:02:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "field_7": 4200
                },
                "warnings": []
            }),
        ),
    ];

    let report = run_step_capture_validation(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepCaptureValidationOptions {
            capture_kind: Some("100_counted_steps".to_string()),
            manual_step_delta: Some(100),
            official_whoop_step_delta: Some(97),
            tolerance_steps: 5,
            label_provenance: Some(json!({
                "source": "manual_plus_official_app",
                "official_labels_are_labels": true
            })),
            ..StepCaptureValidationOptions::default()
        },
    )
    .unwrap();

    assert!(!report.pass);
    assert!(!report.explicit_step_counter_found);
    assert_eq!(report.counter_candidate_count, 0);
    assert_eq!(report.monotonic_counter_candidate_count, 1);
    assert_eq!(report.counter_delta_candidate_count, 1);
    assert_eq!(report.matching_counter_delta_count, 1);
    assert_eq!(
        report.counter_deltas[0].match_kind,
        "monotonic_counter_candidate"
    );
    assert_eq!(report.counter_deltas[0].json_path, "$.body_summary.field_7");
    assert_eq!(report.counter_deltas[0].delta, 100);
    assert_eq!(report.counter_deltas[0].rank, 1);
    assert!(report.counter_deltas[0].selected);
    assert_eq!(
        report.counter_deltas[0].selection_reason,
        "hidden_counter_matches_labels_requires_parser_mapping"
    );
    assert_eq!(report.selected_counter_delta.as_ref().unwrap().delta, 100);
    assert_eq!(report.counter_deltas[0].matches_manual_label, Some(true));
    assert_eq!(report.counter_deltas[0].matches_official_label, Some(true));
    assert!(
        report
            .issues
            .contains(&"matching_counter_delta_requires_parser_mapping".to_string())
    );
    let parser_action = report
        .next_actions
        .iter()
        .find(|action| action.reason == "matching_counter_delta_requires_parser_mapping")
        .unwrap();
    assert!(
        parser_action
            .action
            .contains("Selected decoded path `$.body_summary.field_7` rank 1 delta 100")
    );
    assert!(
        report
            .issues
            .contains(&"no_explicit_step_counter_field_found".to_string())
    );
}

#[test]
fn step_validation_groups_unnamed_counter_candidates_across_array_indices() {
    let rows = vec![
        decoded_frame_row(
            "hidden-array-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "samples": [
                        {
                            "field_7": 4100,
                            "sample_count": 24
                        }
                    ]
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "hidden-array-frame-2",
            "2026-06-02T12:02:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "samples": [
                        {
                            "not_counter": 1
                        },
                        {
                            "field_7": 4200,
                            "sample_count": 24
                        }
                    ]
                },
                "warnings": []
            }),
        ),
    ];

    let report = run_step_capture_validation(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepCaptureValidationOptions {
            capture_kind: Some("100_counted_steps".to_string()),
            manual_step_delta: Some(100),
            official_whoop_step_delta: Some(97),
            tolerance_steps: 5,
            label_provenance: Some(json!({
                "source": "manual_plus_official_app",
                "official_labels_are_labels": true
            })),
            ..StepCaptureValidationOptions::default()
        },
    )
    .unwrap();

    assert!(!report.pass);
    assert_eq!(report.monotonic_counter_candidate_count, 1);
    assert_eq!(report.counter_delta_candidate_count, 1);
    assert_eq!(report.matching_counter_delta_count, 1);
    assert_eq!(report.discovery.counter_delta_candidate_count, 1);
    assert_eq!(report.discovery.monotonic_counter_delta_candidate_count, 1);
    assert_eq!(
        report.discovery.counter_deltas[0].json_path,
        "$.body_summary.samples[].field_7"
    );
    assert_eq!(report.discovery.counter_deltas[0].delta, 100);
    assert_eq!(
        report.discovery.counter_deltas[0].selection_reason,
        "hidden_monotonic_counter_delta"
    );
    assert_eq!(
        report.discovery.counter_deltas[0].matches_manual_label,
        None
    );
    assert_eq!(
        report.counter_deltas[0].json_path,
        "$.body_summary.samples[].field_7"
    );
    assert_eq!(report.counter_deltas[0].sample_count, 2);
    assert_eq!(report.counter_deltas[0].delta, 100);
    assert_eq!(
        report.counter_deltas[0].selection_reason,
        "hidden_counter_matches_labels_requires_parser_mapping"
    );
    assert_eq!(report.counter_deltas[0].matches_manual_label, Some(true));
    assert_eq!(report.counter_deltas[0].matches_official_label, Some(true));
    assert!(
        report
            .issues
            .contains(&"matching_counter_delta_requires_parser_mapping".to_string())
    );
}

#[test]
fn step_validation_does_not_promote_single_frame_array_as_counter_delta() {
    let rows = vec![decoded_frame_row(
        "hidden-array-frame-1",
        "2026-06-02T12:00:00.000Z",
        "HISTORICAL_DATA",
        json!({
            "kind": "data_packet",
            "packet_k": 11,
            "domain": "raw_stream_counted",
            "body_summary": {
                "kind": "raw_stream_counted",
                "samples": [
                    {
                        "field_7": 4100,
                        "sample_count": 24
                    },
                    {
                        "field_7": 4200,
                        "sample_count": 24
                    }
                ]
            },
            "warnings": []
        }),
    )];

    let report = run_step_capture_validation(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepCaptureValidationOptions {
            capture_kind: Some("100_counted_steps".to_string()),
            manual_step_delta: Some(100),
            official_whoop_step_delta: Some(97),
            tolerance_steps: 5,
            label_provenance: Some(json!({
                "source": "manual_plus_official_app",
                "official_labels_are_labels": true
            })),
            ..StepCaptureValidationOptions::default()
        },
    )
    .unwrap();

    assert!(!report.pass);
    assert_eq!(report.monotonic_counter_candidate_count, 0);
    assert_eq!(report.counter_delta_candidate_count, 0);
    assert_eq!(report.matching_counter_delta_count, 0);
    assert!(report.counter_deltas.is_empty());
    assert!(
        report
            .issues
            .contains(&"no_counter_delta_candidates".to_string())
    );
}

#[test]
fn step_delta_selection_prefers_labels_then_explicit_counters() {
    let rows = vec![
        decoded_frame_row(
            "mixed-counter-frame-1",
            "2026-06-02T12:00:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "step_count": 4100,
                    "field_7": 900
                },
                "warnings": []
            }),
        ),
        decoded_frame_row(
            "mixed-counter-frame-2",
            "2026-06-02T12:02:00.000Z",
            "HISTORICAL_DATA",
            json!({
                "kind": "data_packet",
                "packet_k": 11,
                "domain": "raw_stream_counted",
                "body_summary": {
                    "kind": "raw_stream_counted",
                    "step_count": 4180,
                    "field_7": 1000
                },
                "warnings": []
            }),
        ),
    ];

    let discovery = run_step_packet_discovery(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepPacketDiscoveryOptions::default(),
    )
    .unwrap();

    assert!(discovery.pass, "{:?}", discovery.issues);
    let selected_discovery_delta = discovery.selected_counter_delta.as_ref().unwrap();
    assert_eq!(selected_discovery_delta.match_kind, "step_count");
    assert_eq!(selected_discovery_delta.delta, 80);
    assert_eq!(selected_discovery_delta.rank, 1);
    assert_eq!(
        selected_discovery_delta.selection_reason,
        "explicit_step_counter_delta"
    );

    let validation = run_step_capture_validation(
        &rows,
        "synthetic.sqlite",
        "2026-06-02T00:00:00Z",
        "2026-06-03T00:00:00Z",
        StepCaptureValidationOptions {
            capture_kind: Some("100_counted_steps".to_string()),
            manual_step_delta: Some(100),
            official_whoop_step_delta: Some(97),
            tolerance_steps: 5,
            label_provenance: Some(json!({
                "source": "manual_plus_official_app",
                "official_labels_are_labels": true
            })),
            ..StepCaptureValidationOptions::default()
        },
    )
    .unwrap();

    assert!(!validation.pass);
    let selected_validation_delta = validation.selected_counter_delta.as_ref().unwrap();
    assert_eq!(
        selected_validation_delta.match_kind,
        "monotonic_counter_candidate"
    );
    assert_eq!(selected_validation_delta.delta, 100);
    assert_eq!(selected_validation_delta.rank, 1);
    assert_eq!(
        selected_validation_delta.selection_reason,
        "hidden_counter_matches_labels_requires_parser_mapping"
    );
    assert!(
        validation
            .issues
            .contains(&"matching_counter_delta_requires_parser_mapping".to_string())
    );
    let explicit_delta = validation
        .counter_deltas
        .iter()
        .find(|candidate| candidate.match_kind == "step_count")
        .unwrap();
    assert_eq!(explicit_delta.rank, 2);
    assert_eq!(explicit_delta.delta, 80);
    assert_eq!(
        explicit_delta.selection_reason,
        "explicit_step_counter_label_mismatch"
    );
}

#[test]
fn step_counter_daily_rollup_writes_device_counter_activity_metric() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(
        &store,
        "s1",
        1_780_387_200_000,
        4_100,
        Some(92.0),
        Some("walking"),
    );
    insert_step_sample(
        &store,
        "s2",
        1_780_387_260_000,
        4_160,
        Some(98.0),
        Some("walking"),
    );
    insert_step_sample(
        &store,
        "s3",
        1_780_387_320_000,
        4_205,
        Some(104.0),
        Some("stairs"),
    );

    let report = rollup_device_step_counter_day(
        &store,
        StepCounterDailyRollupOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: true,
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(
        report.schema,
        "open_vitals.step-counter-daily-rollup-report.v1"
    );
    assert_eq!(report.sample_count, 3);
    assert_eq!(report.cadence_sample_count, 3);
    assert_eq!(report.activity_state_sample_count, 3);
    assert_eq!(report.usable_segment_count, 2);
    assert_eq!(report.steps, Some(105));
    assert_eq!(report.average_cadence_spm, Some(98.0));
    assert_eq!(report.activity_state_counts.get("walking"), Some(&2));
    assert_eq!(report.activity_state_counts.get("stairs"), Some(&1));
    assert_eq!(report.confidence, 0.95);
    assert!(report.daily_metric_written);
    assert!(report.metric_provenance_written);

    let metric = store
        .daily_activity_metric(report.daily_metric_id.as_ref().unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(metric.steps, Some(105));
    assert_eq!(metric.average_cadence_spm, Some(98.0));
    assert_eq!(metric.source_kind, "device_counter");
    assert!(
        metric
            .provenance_json
            .contains("open_vitals.steps.device_counter.v0")
    );
    let metric_provenance: serde_json::Value =
        serde_json::from_str(&metric.provenance_json).unwrap();
    assert_eq!(
        metric_provenance["algorithm"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_ID
    );
    assert_eq!(
        metric_provenance["algorithm_version"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_VERSION
    );
    assert_eq!(metric_provenance["source_kind"], "device_counter");
    let provenance_rows = store
        .metric_provenance_for_metric("daily_activity", &metric.daily_metric_id)
        .unwrap();
    assert_eq!(provenance_rows.len(), 1);
    let provenance_json: serde_json::Value =
        serde_json::from_str(&provenance_rows[0].provenance_json).unwrap();
    assert_eq!(
        provenance_json["algorithm"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_ID
    );
    assert_eq!(
        provenance_json["algorithm_version"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_VERSION
    );
}

#[test]
fn step_counter_daily_rollup_refreshes_existing_device_counter_activity_metric() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(
        &store,
        "s1",
        1_780_387_200_000,
        4_100,
        Some(92.0),
        Some("walking"),
    );
    insert_step_sample(
        &store,
        "s2",
        1_780_387_260_000,
        4_160,
        Some(98.0),
        Some("walking"),
    );

    let options = StepCounterDailyRollupOptions {
        date_key: "2026-06-02",
        timezone: "Europe/London",
        start_time_unix_ms: 1_780_355_200_000,
        end_time_unix_ms: 1_780_441_600_000,
        min_sample_count: 2,
        write_metric: true,
    };
    let first = rollup_device_step_counter_day(&store, options.clone()).unwrap();
    assert_eq!(first.steps, Some(60));
    assert!(first.daily_metric_written);

    insert_step_sample(
        &store,
        "s3",
        1_780_387_320_000,
        4_205,
        Some(104.0),
        Some("stairs"),
    );
    let second = rollup_device_step_counter_day(&store, options).unwrap();
    assert_eq!(second.steps, Some(105));
    assert!(second.daily_metric_written);

    let metric = store
        .daily_activity_metric(second.daily_metric_id.as_ref().unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(metric.steps, Some(105));
    assert_eq!(metric.average_cadence_spm, Some(98.0));
    assert_eq!(store.table_count("daily_activity_metrics").unwrap(), 1);
    let provenance_rows = store
        .metric_provenance_for_metric("daily_activity", &metric.daily_metric_id)
        .unwrap();
    assert_eq!(provenance_rows.len(), 1);
}

#[test]
fn step_counter_hourly_rollup_writes_device_counter_activity_metric() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(
        &store,
        "s1",
        1_780_387_200_000,
        4_100,
        Some(88.0),
        Some("walking"),
    );
    insert_step_sample(
        &store,
        "s2",
        1_780_387_260_000,
        4_175,
        Some(94.0),
        Some("walking"),
    );
    insert_step_sample(
        &store,
        "s3",
        1_780_387_320_000,
        4_205,
        Some(100.0),
        Some("stairs"),
    );

    let report = rollup_device_step_counter_hour(
        &store,
        StepCounterHourlyRollupOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_387_200_000,
            end_time_unix_ms: 1_780_390_800_000,
            min_sample_count: 2,
            write_metric: true,
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(
        report.schema,
        "open_vitals.step-counter-hourly-rollup-report.v1"
    );
    assert_eq!(report.sample_count, 3);
    assert_eq!(report.steps, Some(105));
    assert_eq!(report.average_cadence_spm, Some(94.0));
    assert_eq!(report.activity_state_counts.get("walking"), Some(&2));
    assert_eq!(report.activity_state_counts.get("stairs"), Some(&1));
    assert!(report.hourly_metric_written);
    assert!(report.metric_provenance_written);

    let metric = store
        .hourly_activity_metric(report.hourly_metric_id.as_ref().unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(metric.steps, Some(105));
    assert_eq!(metric.average_cadence_spm, Some(94.0));
    assert_eq!(metric.source_kind, "device_counter");
    assert_eq!(store.table_count("hourly_activity_metrics").unwrap(), 1);
    let provenance_rows = store
        .metric_provenance_for_metric("hourly_activity", &metric.hourly_metric_id)
        .unwrap();
    assert_eq!(provenance_rows.len(), 1);
    let provenance_json: serde_json::Value =
        serde_json::from_str(&provenance_rows[0].provenance_json).unwrap();
    assert_eq!(
        provenance_json["algorithm"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_ID
    );
    assert_eq!(
        provenance_json["algorithm_version"],
        OPENVITALS_STEPS_DEVICE_COUNTER_V0_VERSION
    );
}

#[test]
fn step_counter_daily_rollup_handles_counter_reset_without_negative_steps() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(&store, "s1", 1_780_387_200_000, 990, None, None);
    insert_step_sample(&store, "s2", 1_780_387_260_000, 1_000, None, None);
    insert_step_sample(&store, "s3", 1_780_387_320_000, 3, None, None);
    insert_step_sample(&store, "s4", 1_780_387_380_000, 20, None, None);

    let report = rollup_device_step_counter_day(
        &store,
        StepCounterDailyRollupOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: false,
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.steps, Some(27));
    assert_eq!(report.reset_count, 1);
    assert!(
        report
            .quality_flags
            .contains(&"counter_reset_detected".to_string())
    );
    assert!(report.confidence < 0.95);
    assert_eq!(store.table_count("daily_activity_metrics").unwrap(), 0);
}

#[test]
fn step_counter_daily_rollup_handles_u16_wraparound() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(&store, "s1", 1_780_387_200_000, 65_500, None, None);
    insert_step_sample(&store, "s2", 1_780_387_260_000, 30, None, None);
    insert_step_sample(&store, "s3", 1_780_387_320_000, 90, None, None);

    let report = rollup_device_step_counter_day(
        &store,
        StepCounterDailyRollupOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: false,
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(report.steps, Some(126));
    assert_eq!(report.usable_segment_count, 2);
    assert_eq!(report.reset_count, 0);
    assert!(
        report
            .quality_flags
            .contains(&"counter_u16_wrap_detected".to_string())
    );
    assert!(
        !report
            .quality_flags
            .contains(&"counter_reset_detected".to_string())
    );
}

#[test]
fn step_counter_daily_rollup_blocks_without_two_samples() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    insert_step_sample(&store, "s1", 1_780_387_200_000, 990, None, None);

    let report = rollup_device_step_counter_day(
        &store,
        StepCounterDailyRollupOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: true,
        },
    )
    .unwrap();

    assert!(!report.pass);
    assert_eq!(report.steps, None);
    assert_eq!(report.confidence, 0.0);
    assert!(
        report
            .issues
            .contains(&"insufficient_step_counter_samples".to_string())
    );
    assert_eq!(store.table_count("daily_activity_metrics").unwrap(), 0);
}

#[test]
fn activity_unavailable_status_writes_steps_activity_metric_with_provenance() {
    let store = OpenVitalsStore::open_in_memory().unwrap();

    let report = rollup_activity_unavailable_daily_status_for_store(
        &store,
        ActivityUnavailableDailyStatusOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: true,
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.issues);
    assert_eq!(
        report.schema,
        "open_vitals.activity-unavailable-daily-status-report.v1"
    );
    assert_eq!(report.available_step_metric_count, 0);
    assert_eq!(report.unavailable_metric_count, 1);
    assert_eq!(report.written_metric_count, 1);
    assert_eq!(report.metric_provenance_written_count, 1);
    assert_eq!(report.step_counter_daily_rollup.pass, false);
    let status = &report.statuses[0];
    assert_eq!(status.metric_id, "steps");
    assert_eq!(status.source_kind, "unavailable");
    assert_eq!(status.promotion_status, "blocked");
    assert_eq!(status.sample_count, 0);
    assert!(
        status
            .blocker_reasons
            .contains(&"insufficient_step_counter_samples".to_string())
    );
    assert!(
        status
            .quality_flags
            .contains(&"activity_steps_unavailable".to_string())
    );

    let metric = store
        .daily_activity_metric(status.daily_metric_id.as_ref().unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(metric.steps, None);
    assert_eq!(metric.active_kcal, None);
    assert_eq!(metric.source_kind, "unavailable");
    assert_eq!(metric.confidence, 0.0);
    let metric_provenance: serde_json::Value =
        serde_json::from_str(&metric.provenance_json).unwrap();
    assert_eq!(
        metric_provenance["algorithm"],
        OPENVITALS_ACTIVITY_UNAVAILABLE_STATUS_V0_ID
    );
    assert_eq!(
        metric_provenance["algorithm_version"],
        OPENVITALS_ACTIVITY_UNAVAILABLE_STATUS_V0_VERSION
    );
    assert_eq!(metric_provenance["source_kind"], "unavailable");

    let provenance_rows = store
        .metric_provenance_for_metric("daily_activity", &metric.daily_metric_id)
        .unwrap();
    assert_eq!(provenance_rows.len(), 1);
    assert_eq!(provenance_rows[0].source_kind, "unavailable");
}

#[test]
fn activity_unavailable_status_skips_steps_when_available_metric_exists() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    store
        .upsert_daily_activity_metric(DailyActivityMetricInput {
            daily_metric_id: "daily-activity-steps-2026-06-02-europe-london-local-estimate-v0",
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            steps: Some(1234),
            active_kcal: None,
            resting_kcal: None,
            total_kcal: None,
            average_cadence_spm: Some(88.0),
            source_kind: "local_estimate",
            confidence: 0.72,
            inputs_json: r#"{"validated":true}"#,
            quality_flags_json: r#"["validated_local_step_estimate"]"#,
            provenance_json: r#"{"algorithm":"open_vitals.steps.raw_motion_estimate.v0","source_kind":"local_estimate"}"#,
        })
        .unwrap();

    let report = rollup_activity_unavailable_daily_status_for_store(
        &store,
        ActivityUnavailableDailyStatusOptions {
            date_key: "2026-06-02",
            timezone: "Europe/London",
            start_time_unix_ms: 1_780_355_200_000,
            end_time_unix_ms: 1_780_441_600_000,
            min_sample_count: 2,
            write_metric: true,
        },
    )
    .unwrap();

    assert!(report.pass);
    assert_eq!(report.available_step_metric_count, 1);
    assert_eq!(report.unavailable_metric_count, 0);
    assert_eq!(report.written_metric_count, 0);
    assert!(report.statuses.is_empty());
    assert_eq!(store.table_count("daily_activity_metrics").unwrap(), 1);
}

fn insert_step_sample(
    store: &OpenVitalsStore,
    sample_id: &str,
    sample_time_unix_ms: i64,
    value: i64,
    cadence_spm: Option<f64>,
    activity_state: Option<&str>,
) {
    store
        .insert_step_counter_sample(StepCounterSampleInput {
            sample_id,
            sample_time_unix_ms,
            counter_value: value,
            cadence_spm,
            activity_state,
            source_kind: "device_counter",
            packet_family: "K11/raw_stream_counted",
            json_path: "$.body_summary.step_count",
            frame_id: None,
            evidence_id: None,
            capture_session_id: None,
            quality_flags_json: "[]",
            provenance_json: r#"{"owner":"user","test":true}"#,
        })
        .unwrap();
}

fn decoded_frame_row(
    frame_id: &str,
    captured_at: &str,
    packet_type_name: &str,
    parsed_payload: serde_json::Value,
) -> DecodedFrameRow {
    DecodedFrameRow {
        frame_id: frame_id.to_string(),
        evidence_id: format!("{frame_id}.evidence"),
        captured_at: captured_at.to_string(),
        device_type: "OPENVITALS".to_string(),
        raw_len: 0,
        header_len: 0,
        declared_len: 0,
        payload_hex: String::new(),
        payload_crc_hex: String::new(),
        header_crc_valid: true,
        payload_crc_valid: true,
        packet_type: None,
        packet_type_name: Some(packet_type_name.to_string()),
        sequence: None,
        command_or_event: None,
        parsed_payload_json: parsed_payload.to_string(),
        parser_version: "open-vitals-core/step-counter-test".to_string(),
        warnings_json: "[]".to_string(),
    }
}

fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}
