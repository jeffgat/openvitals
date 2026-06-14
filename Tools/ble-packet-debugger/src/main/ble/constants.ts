export const CUSTOM_BAND_SERVICE_UUIDS = [
  "fd4b0001cce1403393ce002d5875f58a",
  "610800018d6d82b8614a1c8cb0f8dcc6",
] as const;

export const COMMAND_CHARACTERISTIC_UUIDS = [
  "fd4b0002cce1403393ce002d5875f58a",
  "610800028d6d82b8614a1c8cb0f8dcc6",
] as const;

export const NOTIFICATION_CHARACTERISTIC_UUIDS = [
  "fd4b0003cce1403393ce002d5875f58a",
  "fd4b0004cce1403393ce002d5875f58a",
  "fd4b0005cce1403393ce002d5875f58a",
  "fd4b0007cce1403393ce002d5875f58a",
  "610800038d6d82b8614a1c8cb0f8dcc6",
  "610800048d6d82b8614a1c8cb0f8dcc6",
  "610800058d6d82b8614a1c8cb0f8dcc6",
  "610800078d6d82b8614a1c8cb0f8dcc6",
] as const;

export const STANDARD_HEART_RATE_SERVICE_UUID = "180d";
export const STANDARD_HEART_RATE_MEASUREMENT_UUID = "2a37";
export const BATTERY_SERVICE_UUID = "180f";
export const BATTERY_LEVEL_UUID = "2a19";
export const BATTERY_LEVEL_STATUS_UUID = "2bed";
export const DEVICE_INFORMATION_SERVICE_UUID = "180a";
export const DEVICE_INFORMATION_CHARACTERISTIC_UUIDS = new Set([
  "2a24",
  "2a26",
  "2a27",
  "2a28",
  "2a29",
]);

export const CUSTOM_BAND_SERVICE_SET = new Set<string>(CUSTOM_BAND_SERVICE_UUIDS);
export const COMMAND_CHARACTERISTIC_SET = new Set<string>(COMMAND_CHARACTERISTIC_UUIDS);
export const NOTIFICATION_CHARACTERISTIC_SET = new Set<string>(NOTIFICATION_CHARACTERISTIC_UUIDS);

export function compactUuid(uuid: string): string {
  return uuid.replaceAll("-", "").toLowerCase();
}

export function displayUuid(uuid: string): string {
  const compact = compactUuid(uuid);
  if (compact.length !== 32) {
    return compact;
  }
  return [
    compact.slice(0, 8),
    compact.slice(8, 12),
    compact.slice(12, 16),
    compact.slice(16, 20),
    compact.slice(20),
  ].join("-");
}

export function isCustomBandCharacteristic(uuid: string): boolean {
  return compactUuid(uuid).startsWith("fd4b") || compactUuid(uuid).startsWith("610800");
}

export function rustDeviceTypeForCharacteristic(uuid: string): "OPENVITALS" | "GEN4" {
  return compactUuid(uuid).startsWith("610800") ? "GEN4" : "OPENVITALS";
}
