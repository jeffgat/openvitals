# Blocked Requests

Track work that is blocked because it needs human input, device access, labels, captures, credentials, account actions, or product decisions. Keep engineering-only blockers in the relevant issue, TODO, or code comments instead.

## Active

### Trusted Sleep And HRV Evidence

Status: partly unblocked for sleep v0, still blocked for HRV/recovery evidence.

- 2026-06-11 manual local bundle contains enough trusted motion/window evidence to compute `open_vitals.sleep.v0`; keep using sleep v0 until sleep v1 release-gate semantics are validated.
- 2026-06-11 K20 raw/research candidates are not enough to unblock HRV: direct i16 and peak-spacing interpretations failed HR-alignment validation against trusted HR in the aggregate diagnostic capture.
- 2026-06-11 K20 simple field-correlation pass did not reveal a direct beat-interval field either: strongest simple fields were moderate (~0.58 absolute correlation), and the most plausible 300-2000 raw range correlated in the wrong direction for RR.
- 2026-06-11 realtime raw export shows `REALTIME_RAW_DATA` is already decoded as K20/K21. K20 exposes structured 25-sample channel blocks, but K20/K26 validation remains below promotion threshold: direct i16 plausible intervals were 327/1,433 within 8 bpm and peak spacing was 247/1,121 within 8 bpm against trusted HR. The dedicated K20 channel scan found 1,832 K20 frames and 1,361 realtime K20 frames, but the best channel was only 3/5 usable HR-matched segments with 33% inside 8 bpm and ~14 bpm mean absolute error. Channel peak scans need a stronger transform or external RR reference before they can be trusted.
- 2026-06-11 automatic Stream Probe capture now unblocks raw packet collection for this path: the `stream_probe.auto` session captured K20/K21/K26 plus K18 reference frames and beat-interval discovery candidates. HRV remains blocked because K20 channel alignment is not validated across enough HR/RR reference segments, not because the app cannot capture raw stream packets.
- 2026-06-11 30-minute automatic Stream Probe capture confirms raw packet collection and K20 HR alignment are now partly unblocked: the finished 20:30:52Z-21:00:52Z probe captured 1,798 realtime K20 frames, 1,799 realtime K21 frames, 1,279 historical K20 frames, 120 K26 frames, and 3,141 trusted K18 HR reference frames. Beat-interval discovery found 42,979 direct RR-like values and 53,591 peak-spacing candidates. After time-sliced K20 analysis, offset 226 positive matched K18 HR in 5/6 slices within 8 bpm. HRV remains blocked on true RR validation because HR alignment alone does not prove beat-interval accuracy.
- 2026-06-11 RR reference capture is now implemented as a separate More > Developer route for standard BLE Heart Rate Service devices. HRV promotion remains blocked until a simultaneous automatic Stream Probe plus RR reference capture is collected, exported, and compared against K20/K26 candidate intervals.
- 2026-06-12 K20 byte/scalar discovery is now implemented as a bridge/CLI report and can rank sampled K20 fields against nearby trusted HR while waiting for RR reference hardware. This helps prioritize offsets and command contexts, but it does not unblock HRV because HR correlation alone cannot prove beat-to-beat RR intervals.
- 2026-06-12 applying K20 byte/scalar discovery to the latest full export ranked optical channel 0 sample bytes highest, while the K20 waveform scanner still ranked channel 1/offset 226 highest but below threshold. This keeps the next blocker focused on RR-reference validation and improved waveform/channel transforms rather than hunting for a simple K20 metadata scalar.
- 2026-06-12 K20 waveform transform scanning now finds a stronger HR-aligned lead on the 20:30:52Z-21:00:52Z Stream Probe: channel offset 226, negative polarity, 25 Hz, smoothing 5, threshold 0.65, 6/6 HR-matched slices inside 8 bpm, mean HR error 0.6 bpm, median candidate RR around 920 ms. HRV remains blocked because there were 0 overlapping RR-reference samples, so this is still a lead rather than validated beat-interval evidence.
- 2026-06-12 Beat Evidence Report is implemented as the one-button diagnostic summary for packet deltas plus K20/K26 beat-evidence scans. Current status on the latest probe is `candidate_hr_aligned_needs_rr_reference`: K20 and K26 leads exist, but validated RR-reference overlap is still required before HRV/recovery promotion.
- 2026-06-12 latest 30-minute automatic Stream Probe export confirms the capture path is producing the right raw surface: 3,577 K20 frames, 80 K26 frames, and a K20 waveform candidate at offset 1292 that matched trusted HR in 10/11 slices within 8 bpm. HRV/recovery remain blocked because the same bundle had 0 RR reference samples, so the lead cannot be promoted beyond diagnostic-only.
- 2026-06-11 full local bundle adds K26 pulse-information as a real beat-interval lead, but it is still below the validation bar: broad direct/peak scans were ~32%/~30% within 8 bpm, and the focused byte-field scan found no promotable field/scale. Best variable HR-like field was 121/161 within 8 bpm; best RR-like field was 57/96; offset 59 big-endian RR was 370/901. K26 raw-field correlations mostly point at suspected tail/header metadata, while the best non-tail body fields are only about 0.36.
- Capture enough trusted RR-interval evidence to validate HRV, Recovery, and stress readiness.
- Next evidence target is an alternate beat-interval source: validated broadcast RR evidence, a better K26 field/scale interpretation, a different K20 byte/scale interpretation, K16/K17-style frames, or a command-gated optical/filtered stream that aligns with HR before any HRV promotion.
- Command-gated streams remain blocked for live device sends until the selected command gates are ready. The Rust capture plan now defines the order: read-only baseline config, temporary stream toggles, persistent config only with explicit approval and rollback, then shutdown. The More > Developer Stream Probe Plan route can render this plan and run packet-family delta analysis over existing evidence, but it must not send live device commands yet. After gates are ready, run the probe with packet capture enabled and export the resulting bundle for packet-family delta and beat-candidate validation.
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
