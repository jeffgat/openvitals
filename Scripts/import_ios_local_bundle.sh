#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  Scripts/import_ios_local_bundle.sh <bundle.openvitalsbundle.json> [options]

Extracts the iOS local OpenVitals SQLite database from an app export bundle,
verifies its SHA-256 when present, prints a quick packet summary, and merges the
phone evidence tables into the desktop debugger SQLite database unless
--no-import is supplied.

Options:
  --db <path>           Target desktop/debugger SQLite path.
                       Defaults to OPENVITALS_BLE_DEBUGGER_DB or the Electron userData DB.
  --extract-dir <path>  Directory for extracted SQLite and merge report.
                       Defaults to a fresh /tmp directory.
  --no-import           Only extract and summarize the SQLite snapshot.
  -h, --help            Show this help.
USAGE
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_DB="${HOME}/Library/Application Support/@open-vitals/ble-packet-debugger/open_vitals_ble_debugger.sqlite"

BUNDLE_PATH=""
TARGET_DB="${OPENVITALS_BLE_DEBUGGER_DB:-${DEFAULT_DB}}"
EXTRACT_DIR=""
IMPORT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      TARGET_DB="${2:-}"
      shift 2
      ;;
    --extract-dir)
      EXTRACT_DIR="${2:-}"
      shift 2
      ;;
    --no-import)
      IMPORT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "${BUNDLE_PATH}" ]]; then
        echo "Only one bundle path is supported." >&2
        usage >&2
        exit 2
      fi
      BUNDLE_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "${BUNDLE_PATH}" ]]; then
  echo "Missing bundle path." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "${BUNDLE_PATH}" ]]; then
  echo "Bundle not found: ${BUNDLE_PATH}" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to read ${BUNDLE_PATH}" >&2
  exit 2
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "shasum is required to verify the extracted SQLite snapshot" >&2
  exit 2
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 is required to inspect the extracted SQLite snapshot" >&2
  exit 2
fi

if [[ -z "${EXTRACT_DIR}" ]]; then
  EXTRACT_DIR="$(mktemp -d /tmp/openvitals-ios-local-bundle.XXXXXX)"
else
  mkdir -p "${EXTRACT_DIR}"
fi

SQLITE_PATH="${EXTRACT_DIR}/open_vitals.sqlite"
METADATA_PATH="${EXTRACT_DIR}/open_vitals_sqlite_metadata.json"
MERGE_REPORT_PATH="${EXTRACT_DIR}/merge-report.tsv"
STORAGE_REPORT_PATH="${EXTRACT_DIR}/target-storage-check.json"
RAW_NOTIFICATIONS_PATH="${EXTRACT_DIR}/overnight-raw-notifications.jsonl"
SIDECAR_IMPORT_REQUEST_PATH="${EXTRACT_DIR}/sidecar-import-request.json"
SIDECAR_IMPORT_REPORT_PATH="${EXTRACT_DIR}/sidecar-import-report.json"

SQLITE_FILTER='
  [.files[]
    | select(
        (((.relative_path // .path // "") == "Application Support/OpenVitals/open_vitals.sqlite")
        or ((.relative_path // .path // "") | endswith("/open_vitals.sqlite")))
      )
  ][0]'

if ! jq -e "${SQLITE_FILTER} | type == \"object\"" "${BUNDLE_PATH}" >/dev/null; then
  echo "Bundle does not include Application Support/OpenVitals/open_vitals.sqlite" >&2
  exit 1
fi

jq "${SQLITE_FILTER} | del(.base64)" "${BUNDLE_PATH}" > "${METADATA_PATH}"

decode_base64() {
  if printf '' | base64 -D >/dev/null 2>&1; then
    base64 -D
  elif printf '' | base64 --decode >/dev/null 2>&1; then
    base64 --decode
  else
    echo "base64 decoder not found; expected macOS base64 -D or GNU base64 --decode" >&2
    return 2
  fi
}

jq -r "${SQLITE_FILTER} | .base64 // empty" "${BUNDLE_PATH}" | decode_base64 > "${SQLITE_PATH}"

EXPECTED_SHA="$(jq -r '.sha256 // ""' "${METADATA_PATH}")"
ACTUAL_SHA="$(shasum -a 256 "${SQLITE_PATH}" | awk '{print $1}')"

if [[ -n "${EXPECTED_SHA}" && "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]]; then
  echo "SQLite SHA-256 mismatch" >&2
  echo "expected: ${EXPECTED_SHA}" >&2
  echo "actual:   ${ACTUAL_SHA}" >&2
  exit 1
fi

echo "Extracted SQLite: ${SQLITE_PATH}"
echo "SQLite SHA-256: ${ACTUAL_SHA}"
echo "Metadata: ${METADATA_PATH}"
echo

sqlite3 -readonly -header -column "${SQLITE_PATH}" <<'SQL'
SELECT 'raw_evidence' AS metric, COUNT(*) AS count, MIN(captured_at) AS first_at, MAX(captured_at) AS last_at
FROM raw_evidence;

SELECT 'decoded_frames' AS metric, COUNT(*) AS count, NULL AS first_at, NULL AS last_at
FROM decoded_frames;

SELECT
  COALESCE(d.packet_type_name, 'unknown') AS packet_type,
  COALESCE('K' || json_extract(d.parsed_payload_json, '$.packet_k'), '-') AS family,
  COUNT(*) AS frames,
  MIN(
    CASE
      WHEN json_extract(d.parsed_payload_json, '$.timestamp_seconds') IS NOT NULL
      THEN datetime(json_extract(d.parsed_payload_json, '$.timestamp_seconds'), 'unixepoch') || 'Z'
    END
  ) AS first_sample_at,
  MAX(
    CASE
      WHEN json_extract(d.parsed_payload_json, '$.timestamp_seconds') IS NOT NULL
      THEN datetime(json_extract(d.parsed_payload_json, '$.timestamp_seconds'), 'unixepoch') || 'Z'
    END
  ) AS last_sample_at,
  MIN(r.captured_at) AS first_at,
  MAX(r.captured_at) AS last_at
FROM decoded_frames d
JOIN raw_evidence r ON r.evidence_id = d.evidence_id
WHERE d.packet_type_name IN ('HISTORICAL_DATA', 'HISTORICAL_IMU_DATA_STREAM', 'REALTIME_RAW_DATA')
GROUP BY d.packet_type_name, json_extract(d.parsed_payload_json, '$.packet_k')
ORDER BY d.packet_type_name, family;
SQL

if [[ "${IMPORT}" -eq 0 ]]; then
  echo
  echo "Skipped import because --no-import was supplied."
  exit 0
fi

mkdir -p "$(dirname -- "${TARGET_DB}")"

echo
echo "Preparing target database: ${TARGET_DB}"

(
  cd "${REPO_ROOT}/Rust/core"
  cargo run --quiet --bin open-vitals-storage-check -- \
    --db "${TARGET_DB}" \
    --output "${STORAGE_REPORT_PATH}" >/dev/null
)

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

SOURCE_SQL="$(sql_quote "${SQLITE_PATH}")"

sqlite3 "${TARGET_DB}" > "${MERGE_REPORT_PATH}" <<SQL
.headers on
.mode tabs
PRAGMA foreign_keys = OFF;
ATTACH DATABASE '${SOURCE_SQL}' AS src;
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO capture_sessions SELECT * FROM src.capture_sessions;
SELECT 'capture_sessions' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO raw_evidence SELECT * FROM src.raw_evidence;
SELECT 'raw_evidence' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO decoded_frames SELECT * FROM src.decoded_frames;
SELECT 'decoded_frames' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO band_sync_frame_identities SELECT * FROM src.band_sync_frame_identities;
SELECT 'band_sync_frame_identities' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO band_sync_checkpoints SELECT * FROM src.band_sync_checkpoints;
SELECT 'band_sync_checkpoints' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO rr_reference_samples SELECT * FROM src.rr_reference_samples;
SELECT 'rr_reference_samples' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO ble_raw_notifications SELECT * FROM src.ble_raw_notifications;
SELECT 'ble_raw_notifications' AS table_name, changes() AS inserted;
INSERT OR IGNORE INTO historical_range_polls SELECT * FROM src.historical_range_polls;
SELECT 'historical_range_polls' AS table_name, changes() AS inserted;
COMMIT;
DETACH DATABASE src;
PRAGMA foreign_keys = ON;
SQL

FOREIGN_KEY_ISSUES="$(sqlite3 "${TARGET_DB}" "PRAGMA foreign_key_check;" || true)"
if [[ -n "${FOREIGN_KEY_ISSUES}" ]]; then
  echo "Target database has foreign-key issues after merge:" >&2
  echo "${FOREIGN_KEY_ISSUES}" >&2
  exit 1
fi

echo "Merge report: ${MERGE_REPORT_PATH}"
cat "${MERGE_REPORT_PATH}"

RAW_NOTIFICATIONS_FILTER='
  [.files[]
    | select(((.relative_path // .path // "") | endswith("/raw-notifications.jsonl")))
  ][0]'

if ! jq -e "${RAW_NOTIFICATIONS_FILTER} | type == \"object\"" "${BUNDLE_PATH}" >/dev/null; then
  echo
  echo "No overnight raw-notifications sidecar found; SQLite merge complete."
  exit 0
fi

jq -r "${RAW_NOTIFICATIONS_FILTER} | .base64 // empty" "${BUNDLE_PATH}" | decode_base64 > "${RAW_NOTIFICATIONS_PATH}"

SIDECAR_FRAME_COUNT="$(jq -cs '[.[] | select(.frame_hex and (.packet_k == 18 or .packet_k == 20 or .packet_k == 21))] | length' "${RAW_NOTIFICATIONS_PATH}")"
if [[ "${SIDECAR_FRAME_COUNT}" -eq 0 ]]; then
  echo
  echo "Overnight raw-notifications sidecar found, but it has no complete K18/K20/K21 frames."
  exit 0
fi

SIDECAR_SESSION_ID="$(jq -sr 'map(select(.session_id))[0].session_id // ""' "${RAW_NOTIFICATIONS_PATH}")"
SIDECAR_STARTED_AT="$(jq -sr 'map(select(.captured_at))[0].captured_at // ""' "${RAW_NOTIFICATIONS_PATH}")"
SIDECAR_ENDED_AT="$(jq -sr 'map(select(.captured_at))[-1].captured_at // ""' "${RAW_NOTIFICATIONS_PATH}")"
SIDECAR_SESSION_SQL="$(sql_quote "${SIDECAR_SESSION_ID}")"
SIDECAR_STARTED_SQL="$(sql_quote "${SIDECAR_STARTED_AT}")"
SIDECAR_ENDED_SQL="$(sql_quote "${SIDECAR_ENDED_AT}")"

sqlite3 "${TARGET_DB}" <<SQL
INSERT OR IGNORE INTO capture_sessions (
  session_id,
  source,
  started_at_unix_ms,
  ended_at_unix_ms,
  device_model,
  active_device_id,
  status,
  frame_count,
  provenance_json
) VALUES (
  '${SIDECAR_SESSION_SQL}',
  'ios.overnight_guard.sidecar',
  CAST(strftime('%s', '${SIDECAR_STARTED_SQL}') AS INTEGER) * 1000,
  CAST(strftime('%s', '${SIDECAR_ENDED_SQL}') AS INTEGER) * 1000,
  'compatible BLE health device',
  NULL,
  'final_sync_complete',
  ${SIDECAR_FRAME_COUNT},
  '{"source":"openvitalsbundle.raw-notifications.jsonl","frame_filter":"K18/K20/K21"}'
);
SQL

jq -cs --arg db "${TARGET_DB}" '
  [.[] | select(.frame_hex and (.packet_k == 18 or .packet_k == 20 or .packet_k == 21)) | {
    evidence_id: (
      "ios."
      + (.device_id // "unknown-device")
      + ".overnight_sidecar."
      + (.captured_at | gsub("[^0-9]"; ""))
      + "."
      + ((.sha256 // .frame_hex)[0:16])
    ),
    source: (.source // "ios.corebluetooth.raw_notification"),
    captured_at: .captured_at,
    device_model: "compatible BLE health device",
    frame_hex: .frame_hex,
    sensitivity: "user-owned-capture",
    capture_session_id: .session_id,
    device_type: "OPENVITALS"
  }]
  | {
    schema: "open_vitals.bridge.request.v1",
    request_id: "import-overnight-sidecar-history",
    method: "capture.import_frame_batch",
    args: {
      database_path: $db,
      include_results: false,
      include_timeline_rows: false,
      compact_raw_payloads: true,
      frames: .
    }
  }
' "${RAW_NOTIFICATIONS_PATH}" > "${SIDECAR_IMPORT_REQUEST_PATH}"

(
  cd "${REPO_ROOT}/Rust/core"
  cargo run --quiet --bin open-vitals-bridge < "${SIDECAR_IMPORT_REQUEST_PATH}" > "${SIDECAR_IMPORT_REPORT_PATH}"
)

echo
echo "Sidecar history import report: ${SIDECAR_IMPORT_REPORT_PATH}"
jq -e '
  if (.ok and .result.pass) then
    {
      ok,
      pass: .result.pass,
      frame_count: .result.frame_count,
      raw_inserted: .result.raw_inserted,
      raw_existing: .result.raw_existing,
      frames_inserted: .result.frames_inserted,
      frames_existing: .result.frames_existing,
      historical_duplicate_skipped: .result.historical_duplicate_skipped,
      issues: .result.issues
    }
  else
    .
  end
' "${SIDECAR_IMPORT_REPORT_PATH}"

if [[ -n "$(sqlite3 "${TARGET_DB}" "PRAGMA foreign_key_check;" || true)" ]]; then
  echo "Target database has foreign-key issues after sidecar import." >&2
  exit 1
fi
