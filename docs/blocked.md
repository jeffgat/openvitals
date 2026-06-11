# Blocked Requests

Track work that is blocked because it needs human input, device access, labels, captures, credentials, account actions, or product decisions. Keep engineering-only blockers in the relevant issue, TODO, or code comments instead.

## Active

### Trusted Sleep And HRV Evidence

Status: partly unblocked for sleep v0, still blocked for HRV/recovery evidence.

- 2026-06-11 manual local bundle contains enough trusted motion/window evidence to compute `open_vitals.sleep.v0`; keep using sleep v0 until sleep v1 release-gate semantics are validated.
- Capture enough trusted RR-interval evidence to validate HRV, Recovery, and stress readiness.
- Compare the resulting local sleep/recovery outputs against the same date's trusted user-visible reference values.
- Current fallback is to show unavailable or low-confidence packet-derived states rather than fabricating sleep, recovery, or HRV values.

### Recovery V2 Packet Semantics

Status: blocked on human/device evidence.

- Capture and label one overnight window where the device companion app shows respiratory rate, SpO2, and skin/wrist temperature for the same date.
- Confirm whether the K18/K24 respiratory-rate candidate is a nightly average, point sample, or rolling value.
- Confirm whether wrist temperature should display absolute skin temperature or deviation from baseline.
- Identify which packet/field should be trusted for SpO2; Rust currently treats oxygen saturation as decoder-not-implemented.
- Decide whether Recovery timeline should eventually link to a persisted Rust algorithm-run/input-id record, rather than the current UI-level score/sleep/metric/blocker rows.

## How To Add Future Blockers

When a request cannot make meaningful progress without human input or action, add an entry here with:

- The feature or request name.
- The exact human action needed.
- The current fallback or safe behavior.
- Any file, capture, label, credential, or decision that would unblock the work.
