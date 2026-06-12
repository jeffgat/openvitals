use open_vitals_core::{
    capture_import::{CapturedFrameBatchOptions, CapturedFrameInput, import_captured_frame_batch},
    command_stream_delta::{
        CommandStreamPacketDeltaOptions, run_command_stream_packet_delta_for_store,
    },
    protocol::{DeviceType, PACKET_TYPE_HISTORICAL_DATA, build_v5_payload_frame},
    store::{CaptureSessionInput, OpenVitalsStore},
};

#[test]
fn stream_packet_delta_reports_expected_family_increases() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    store
        .start_capture_session(CaptureSessionInput {
            session_id: "probe-session",
            source: "test",
            started_at_unix_ms: 1_781_000_000_000,
            device_model: "test-band",
            active_device_id: None,
            provenance_json: "{}",
        })
        .unwrap();

    let frames = vec![
        data_packet_frame(
            "baseline-k18",
            "2026-06-11T08:00:00Z",
            18,
            Some("probe-session"),
        ),
        data_packet_frame(
            "probe-k18",
            "2026-06-11T08:05:00Z",
            18,
            Some("probe-session"),
        ),
        data_packet_frame(
            "probe-k20",
            "2026-06-11T08:05:05Z",
            20,
            Some("probe-session"),
        ),
        data_packet_frame(
            "probe-k26",
            "2026-06-11T08:05:10Z",
            26,
            Some("probe-session"),
        ),
        data_packet_frame("other-session-k20", "2026-06-11T08:05:15Z", 20, None),
    ];

    let import = import_captured_frame_batch(
        &store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "test",
        },
    )
    .unwrap();
    assert!(import.pass, "{:?}", import.issues);

    let report = run_command_stream_packet_delta_for_store(
        &store,
        CommandStreamPacketDeltaOptions {
            start: "2026-06-11T08:05:00Z".to_string(),
            end: "2026-06-11T08:06:00Z".to_string(),
            baseline_start: Some("2026-06-11T08:00:00Z".to_string()),
            baseline_end: Some("2026-06-11T08:01:00Z".to_string()),
            capture_session_ids: vec!["probe-session".to_string()],
            expected_packet_families: vec![
                "K18_trusted_heart_rate".to_string(),
                "K20_raw_or_research_stream".to_string(),
                "K26_pulse_information".to_string(),
            ],
        },
    )
    .unwrap();

    assert!(report.pass, "{:?}", report.next_actions);
    assert_eq!(report.expected_family_count, 3);
    assert_eq!(report.present_expected_count, 3);
    assert_eq!(report.increased_expected_count, 2);
    assert_eq!(report.total_probe_frames, 3);
    assert!(report.next_actions.is_empty(), "{:?}", report.next_actions);

    let k20 = report
        .family_deltas
        .iter()
        .find(|row| row.family == "K20_raw_or_research_stream")
        .unwrap();
    assert_eq!(k20.baseline_count, 0);
    assert_eq!(k20.probe_count, 1);
    assert_eq!(k20.delta_count, 1);
    assert!(k20.present);
    assert!(k20.increased);

    let k18 = report
        .family_deltas
        .iter()
        .find(|row| row.family == "K18_trusted_heart_rate")
        .unwrap();
    assert_eq!(k18.baseline_count, 1);
    assert_eq!(k18.probe_count, 1);
    assert_eq!(k18.delta_count, 0);
}

#[test]
fn stream_packet_delta_reports_missing_expected_family_next_action() {
    let store = OpenVitalsStore::open_in_memory().unwrap();
    let frames = vec![data_packet_frame(
        "probe-k18",
        "2026-06-11T08:05:00Z",
        18,
        None,
    )];
    let import = import_captured_frame_batch(
        &store,
        &frames,
        CapturedFrameBatchOptions {
            parser_version: "test",
        },
    )
    .unwrap();
    assert!(import.pass, "{:?}", import.issues);

    let report = run_command_stream_packet_delta_for_store(
        &store,
        CommandStreamPacketDeltaOptions {
            start: "2026-06-11T08:05:00Z".to_string(),
            end: "2026-06-11T08:06:00Z".to_string(),
            expected_packet_families: vec!["K17_R17_optical_or_filtered".to_string()],
            ..CommandStreamPacketDeltaOptions::default()
        },
    )
    .unwrap();

    assert!(!report.pass);
    assert_eq!(report.present_expected_count, 0);
    assert_eq!(report.next_actions.len(), 1);
    assert_eq!(
        report.next_actions[0].reason,
        "expected_family_missing".to_string()
    );
}

fn data_packet_frame(
    id: &str,
    captured_at: &str,
    packet_k: u8,
    capture_session_id: Option<&str>,
) -> CapturedFrameInput {
    let mut payload = vec![PACKET_TYPE_HISTORICAL_DATA, packet_k, 0];
    payload.extend_from_slice(&0u32.to_le_bytes());
    payload.extend_from_slice(&0u32.to_le_bytes());
    payload.extend_from_slice(&0u16.to_le_bytes());
    payload.extend_from_slice(&[0, 0, 0, 0]);
    CapturedFrameInput {
        evidence_id: format!("evidence-{id}"),
        frame_id: Some(format!("frame-{id}")),
        source: "test".to_string(),
        captured_at: captured_at.to_string(),
        device_model: "test-band".to_string(),
        frame_hex: hex::encode(build_v5_payload_frame(&payload)),
        sensitivity: "owned_test".to_string(),
        capture_session_id: capture_session_id.map(str::to_string),
        device_type: DeviceType::OpenVitals,
    }
}
