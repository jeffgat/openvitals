# Protocol Command Map

Generated command identifiers cross-checked against `goose_core::commands::COMMAND_DEFINITIONS`.

| Command ID | Command | Family | Description |
| ---: | --- | --- | --- |
| 1 | `link_valid` | `identity` | Read or confirm the link-valid protocol state. |
| 2 | `get_max_protocol_version` | `identity` | Read the maximum supported strap protocol version. |
| 3 | `toggle_realtime_hr` | `sensor_stream` | Toggle realtime heart-rate packets. |
| 7 | `report_version_info` | `identity` | Read strap version information. |
| 10 | `set_clock` | `clock_sync` | Set strap RTC seconds and subseconds. |
| 11 | `get_clock` | `clock_sync` | Read strap RTC seconds and subseconds. |
| 14 | `toggle_generic_hr_profile` | `sensor_stream` | Toggle the generic BLE heart-rate profile path. |
| 16 | `toggle_r7_data_collection` | `sensor_stream` | Toggle R7 data collection. |
| 19 | `run_haptic_pattern_maverick` | `alarm_haptics` | Run a Maverick haptic pattern. |
| 20 | `abort_historical_transmits` | `historical_sync` | Abort active historical transmissions. |
| 145 | `get_hello` | `identity` | Read strap identity and protocol hello. |
| 26 | `get_battery_level` | `battery` | Read strap battery level. |
| 34 | `get_data_range` | `historical_sync` | Read available historical data range. |
| 22 | `send_historical_data` | `historical_sync` | Request historical data transfer. |
| 23 | `historical_data_result` | `historical_sync` | Send historical data transfer result or acknowledgement. |
| 33 | `set_read_pointer` | `historical_sync` | Move the strap historical read pointer. |
| 35 | `get_hello_harvard` | `identity` | Read legacy Harvard/Gen4 hello information. |
| 36 | `start_firmware_load` | `firmware_dfu` | Start legacy firmware image load. |
| 37 | `load_firmware_data` | `firmware_dfu` | Send a legacy firmware image data chunk. |
| 38 | `process_firmware_image` | `firmware_dfu` | Ask strap to process a legacy firmware image. |
| 39 | `set_led_drive` | `optical_afe_config` | Write optical LED drive configuration. |
| 40 | `get_led_drive` | `optical_afe_config` | Read optical LED drive configuration. |
| 41 | `set_tia_gain` | `optical_afe_config` | Write optical TIA gain configuration. |
| 42 | `get_tia_gain` | `optical_afe_config` | Read optical TIA gain configuration. |
| 43 | `set_bias_offset` | `optical_afe_config` | Write optical bias offset configuration. |
| 44 | `get_bias_offset` | `optical_afe_config` | Read optical bias offset configuration. |
| 52 | `set_dp_type` | `data_packet_config` | Set historical data-packet type selection. |
| 53 | `force_dp_type` | `data_packet_config` | Force historical data-packet type selection. |
| 63 | `send_r10_r11_realtime` | `sensor_stream` | Toggle or request R10/R11 realtime raw packets. |
| 66 | `set_alarm_time` | `alarm_haptics` | Set strap alarm time. |
| 67 | `get_alarm_time` | `alarm_haptics` | Read strap alarm configuration. |
| 68 | `run_alarm` | `alarm_haptics` | Trigger an alarm pattern. |
| 69 | `disable_alarm` | `alarm_haptics` | Disable strap alarm. |
| 79 | `run_haptics_pattern` | `alarm_haptics` | Run a selected haptic pattern. |
| 76 | `get_advertising_name_harvard` | `device_identity` | Read legacy Harvard advertising name. |
| 77 | `set_advertising_name_harvard` | `device_identity` | Set legacy Harvard advertising name. |
| 122 | `stop_haptics` | `alarm_haptics` | Stop active haptics. |
| 80 | `get_all_haptics_pattern` | `alarm_haptics` | Read available strap haptic patterns. |
| 123 | `select_wrist` | `wrist_selection` | Change left/right wrist selection. |
| 81 | `start_raw_data` | `sensor_stream` | Start realtime raw data stream. |
| 82 | `stop_raw_data` | `sensor_stream` | Stop realtime raw data stream. |
| 83 | `verify_firmware_image` | `firmware_dfu` | Verify a firmware image write/read step. |
| 84 | `get_body_location_and_status` | `wrist_selection` | Read body-location and strap status. |
| 96 | `enter_high_freq_sync` | `historical_sync` | Enter high-frequency sync mode. |
| 97 | `exit_high_freq_sync` | `historical_sync` | Exit high-frequency sync mode. |
| 98 | `get_extended_battery_info` | `battery` | Read extended battery and fuel-gauge information. |
| 105 | `toggle_imu_mode_historical` | `sensor_stream` | Toggle historical IMU data stream mode. |
| 106 | `toggle_imu_mode` | `sensor_stream` | Toggle realtime IMU stream mode. |
| 107 | `enable_optical_data` | `sensor_stream` | Enable realtime optical R20 data. |
| 108 | `toggle_optical_mode` | `sensor_stream` | Toggle optical stream mode. |
| 115 | `start_device_config_key_exchange` | `device_config` | Start persistent device-config key exchange. |
| 116 | `send_next_device_config` | `device_config` | Send the next persistent device-config key/value. |
| 117 | `start_feature_flag_key_exchange` | `feature_flags` | Start feature-flag key exchange. |
| 118 | `send_next_feature_flag` | `feature_flags` | Send the next feature-flag key/value. |
| 119 | `set_device_config_value` | `device_config` | Write a device configuration value. |
| 120 | `set_feature_flag_value` | `feature_flags` | Write a feature flag value. |
| 121 | `get_device_config_value` | `device_config` | Read a device configuration value. |
| 124 | `toggle_labrador_data_generation` | `sensor_stream` | Toggle raw ECG/Labrador packet generation. |
| 125 | `toggle_labrador_raw_save` | `sensor_stream` | Toggle raw ECG/Labrador save behavior. |
| 128 | `get_feature_flag_value` | `feature_flags` | Read a feature flag value. |
| 131 | `set_research_packet` | `research_packet` | Write research packet configuration. |
| 132 | `get_research_packet` | `research_packet` | Read research packet configuration. |
| 139 | `toggle_labrador_filtered` | `sensor_stream` | Toggle filtered ECG/Labrador data stream. |
| 140 | `set_advertising_name` | `device_identity` | Set strap advertising name. |
| 141 | `get_advertising_name` | `device_identity` | Read strap advertising name. |
| 142 | `start_firmware_load_new` | `firmware_dfu` | Start a firmware image load. |
| 143 | `load_firmware_data_new` | `firmware_dfu` | Send a firmware image data chunk. |
| 144 | `process_firmware_image_new` | `firmware_dfu` | Ask strap to process a loaded firmware image. |
| 151 | `get_battery_pack_info` | `battery` | Read battery-pack information. |
| 153 | `toggle_persistent_r20` | `persistent_sensor_config` | Toggle persistent optical R20 configuration. |
| 154 | `toggle_persistent_r21` | `persistent_sensor_config` | Toggle persistent IMU R21 configuration. |
| 45 | `enter_ble_dfu` | `firmware_dfu` | Enter BLE DFU mode. |
| 29 | `reboot_strap` | `reboot_maintenance` | Reboot the strap. |
| 32 | `power_cycle_strap` | `reboot_maintenance` | Power-cycle the strap. |
| 25 | `force_trim` | `reboot_maintenance` | Force storage trim. |
