#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

export OPENVITALS_BLE_DEBUGGER_DB="${OPENVITALS_BLE_DEBUGGER_DB:-${HOME}/Library/Application Support/@open-vitals/ble-packet-debugger/open_vitals_ble_debugger.sqlite}"
export OPENVITALS_MOBILE_INGEST="${OPENVITALS_MOBILE_INGEST:-1}"
export OPENVITALS_MOBILE_INGEST_HOST="${OPENVITALS_MOBILE_INGEST_HOST:-0.0.0.0}"
export OPENVITALS_MOBILE_INGEST_PORT="${OPENVITALS_MOBILE_INGEST_PORT:-8765}"
export OPENVITALS_MOBILE_INGEST_TOKEN="${OPENVITALS_MOBILE_INGEST_TOKEN:-openvitals-local-ingest}"

mkdir -p "$(dirname -- "${OPENVITALS_BLE_DEBUGGER_DB}")"

TAILSCALE_IP=""
TAILSCALE_DNS=""
LAN_IP=""
if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  TAILSCALE_DNS="$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); print((data.get("Self", {}).get("DNSName") or "").rstrip("."))' 2>/dev/null || true)"
fi
for iface in en0 en1 en2; do
  if [[ -z "${LAN_IP}" ]]; then
    LAN_IP="$(ipconfig getifaddr "${iface}" 2>/dev/null || true)"
  fi
done

echo "OpenVitals BLE debugger dev"
echo "DB: ${OPENVITALS_BLE_DEBUGGER_DB}"
echo "Mobile ingest bind: ${OPENVITALS_MOBILE_INGEST_HOST}:${OPENVITALS_MOBILE_INGEST_PORT}"
if [[ -n "${TAILSCALE_IP}" ]]; then
  echo "iOS endpoint: http://${TAILSCALE_IP}:${OPENVITALS_MOBILE_INGEST_PORT}/v1/mobile/frame-batch"
  if [[ -n "${TAILSCALE_DNS}" ]]; then
    echo "MagicDNS endpoint: http://${TAILSCALE_DNS}:${OPENVITALS_MOBILE_INGEST_PORT}/v1/mobile/frame-batch"
  fi
else
  echo "iOS endpoint: http://<mac-tailscale-name-or-ip>:${OPENVITALS_MOBILE_INGEST_PORT}/v1/mobile/frame-batch"
fi
if [[ -n "${LAN_IP}" ]]; then
  echo "LAN fallback endpoint: http://${LAN_IP}:${OPENVITALS_MOBILE_INGEST_PORT}/v1/mobile/frame-batch"
fi
echo "Token: ${OPENVITALS_MOBILE_INGEST_TOKEN}"
echo

cd "${TOOL_DIR}"
exec npm run dev
