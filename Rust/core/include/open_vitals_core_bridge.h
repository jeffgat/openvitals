#ifndef OPENVITALS_CORE_BRIDGE_H
#define OPENVITALS_CORE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

char *open_vitals_core_version_json(void);
char *open_vitals_bridge_handle_json(const char *request_json);
void open_vitals_bridge_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
