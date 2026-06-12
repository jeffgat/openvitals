use open_vitals_core::protocol::{
    PACKET_TYPE_COMMAND_RESPONSE, build_v5_command_frame, build_v5_payload_frame,
};

const COMMAND_SERVICE_UUID: &str = "61080001-0000-1000-8000-00805f9b34fb";
const COMMAND_CHARACTERISTIC_UUID: &str = "61080002-0000-1000-8000-00805f9b34fb";
const COMMAND_WRITE_TYPE: &str = "with_response";

#[test]
fn command_capture_plan_cli_emits_selected_command_plan() {
    let tempdir = tempfile::tempdir().unwrap();
    let path = tempdir.path().join("command-evidence.json");
    std::fs::write(
        &path,
        serde_json::to_string_pretty(&serde_json::json!({
            "schema": "open_vitals.command-evidence.v1",
            "evidence": [ready_toggle_realtime_hr_evidence()]
        }))
        .unwrap(),
    )
    .unwrap();

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-command-capture-plan"))
        .arg("--evidence")
        .arg(path)
        .arg("--commands")
        .arg("toggle_realtime_hr,start_firmware_load_new")
        .output()
        .unwrap();

    assert!(!output.status.success());
    let plan: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(plan["schema"], "open_vitals.command-capture-plan-report.v1");
    assert_eq!(plan["generated_by"], "open-vitals-command-capture-plan");
    assert_eq!(plan["command_count"], 2);
    assert_eq!(plan["requested_commands_valid"], true);
    assert_eq!(plan["validation_records_valid"], true);
    assert_eq!(plan["all_selected_gates_ready"], false);
    assert_eq!(plan["critical_gates_ready"], false);
    assert_eq!(plan["capture_actions_ready"], false);
    assert_eq!(plan["ready_count"], 1);
    assert_eq!(plan["locked_count"], 1);
    assert_eq!(plan["critical_locked_count"], 1);
    assert_eq!(
        plan["gates"]["toggle_realtime_hr"]["direct_send_allowed"],
        true
    );
    assert_eq!(
        plan["next_command_focus"]["command"],
        "start_firmware_load_new"
    );
}

#[test]
fn command_capture_plan_cli_emits_stream_probe_plan() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-command-capture-plan"))
        .arg("--commands")
        .arg("get_led_drive,enable_optical_data,toggle_persistent_r20,stop_raw_data")
        .output()
        .unwrap();

    assert!(!output.status.success());
    let plan: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let stream_plan = &plan["stream_probe_plan"];
    assert_eq!(
        stream_plan["schema"],
        "open_vitals.command-gated-stream-probe-plan.v1"
    );
    assert_eq!(stream_plan["step_count"], 4);
    assert_eq!(stream_plan["all_stream_gates_ready"], false);
    assert_eq!(stream_plan["persistent_stream_gates_ready"], false);
    assert_eq!(stream_plan["steps"][0]["command"], "get_led_drive");
    assert_eq!(stream_plan["steps"][0]["phase"], "baseline_read");
    assert_eq!(stream_plan["steps"][1]["command"], "enable_optical_data");
    assert_eq!(stream_plan["steps"][1]["phase"], "temporary_stream_toggle");
    assert_eq!(stream_plan["steps"][2]["command"], "toggle_persistent_r20");
    assert_eq!(stream_plan["steps"][2]["phase"], "persistent_config");
    assert_eq!(stream_plan["steps"][3]["command"], "stop_raw_data");
    assert_eq!(stream_plan["steps"][3]["phase"], "shutdown");
    assert!(
        stream_plan["expected_packet_families"]
            .as_array()
            .unwrap()
            .iter()
            .any(|family| family == "K20_raw_or_research_stream")
    );
}

#[test]
fn command_capture_plan_cli_can_ingest_emulator_log_and_write_evidence() {
    let tempdir = tempfile::tempdir().unwrap();
    let log_path = tempdir.path().join("emulator.log");
    let evidence_output = tempdir.path().join("emulator-evidence.json");
    std::fs::write(
        &log_path,
        "write command_to_strap aa0108000001e67123019101363e5c8d\nnotify command_from_strap aa0108000001e67123019101363e5c8d\n",
    )
    .unwrap();

    let output = std::process::Command::new(env!("CARGO_BIN_EXE_open-vitals-command-capture-plan"))
        .arg("--emulator-log")
        .arg(&log_path)
        .arg("--emulator-evidence-output")
        .arg(&evidence_output)
        .arg("--emulator-mirror-local-frame")
        .arg("--visible-user-intent")
        .arg("--commands")
        .arg("get_hello")
        .output()
        .unwrap();

    let plan: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(plan["schema"], "open_vitals.command-capture-plan-report.v1");
    assert!(evidence_output.exists());
}

fn ready_toggle_realtime_hr_evidence() -> serde_json::Value {
    let command = 3u8;
    let frame = hex::encode(build_v5_command_frame(1, command, &[1]));
    let response = hex::encode(build_v5_payload_frame(&[
        PACKET_TYPE_COMMAND_RESPONSE,
        9,
        command,
        1,
        0,
    ]));
    serde_json::json!({
        "command": "toggle_realtime_hr",
        "officialCaptureCount": 1,
        "evidenceSource": "user_owned_official_capture",
        "provenance": {
            "capture_app": "official_device_app",
            "capture_kind": "passive_ble_observation",
            "owner": "user"
        },
        "officialFrameHex": frame,
        "localFrameHex": frame,
        "officialServiceUuid": COMMAND_SERVICE_UUID,
        "localServiceUuid": COMMAND_SERVICE_UUID,
        "officialCharacteristicUuid": COMMAND_CHARACTERISTIC_UUID,
        "localCharacteristicUuid": COMMAND_CHARACTERISTIC_UUID,
        "officialWriteType": COMMAND_WRITE_TYPE,
        "localWriteType": COMMAND_WRITE_TYPE,
        "officialResponseFrameHex": response,
        "responseParser": true,
        "visibleUserIntent": true,
        "triggeringUiAction": "visible capture stream toggle",
        "eventLogging": true,
        "timeoutBehavior": true
    })
}
