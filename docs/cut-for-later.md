# Cut For Later

This file tracks partially built surfaces that were intentionally removed from the active app experience so they can be reconsidered later.

## 2026-06-10 Home and Health Simplification

- Home Cardio Load widget: hidden from Home. The `HomeCardioLoadWidget`, `CardioLoadView`, local cardio-load models, and route code remain available, but the Home surface should not show Cardio Load until the local activity-session inputs and daily load persistence are ready.
- Home Stress & Energy section: removed from Home. `HomeStressEnergySection`, Stress detail, Energy Bank detail, local stress/energy calculations, and related snapshots remain available for a later product pass.
- Home Timeline section: removed from Home. `HomeTimelineSection` and activity timeline plumbing remain available, but the current Home surface should stay focused on top scores, Health Monitor, and Data & Algorithms.
- Health tab: removed from the bottom tab bar. `HealthView` and `HealthRouteContentView` remain in code; Home still routes directly to selected Sleep, Recovery, Strain, Health Monitor, Packet Inputs, and Algorithms destinations.
- Oxygen Saturation Health Monitor card: hidden from the current Health Monitor surface. The snapshot and packet-proof placeholders remain available for later once SpO2 evidence is strong enough.
- Calibration shortcut: no longer surfaced through the removed Health landing. `CalibrationHealthView` and calibration state remain available for a later Algorithms/Data expansion.

