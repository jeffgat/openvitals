import type { DeviceProfileId, DiscoveredDevice } from "../../shared/types";
import { compactUuid, CUSTOM_BAND_SERVICE_SET, STANDARD_HEART_RATE_SERVICE_UUID } from "./constants";
import type { NoblePeripheral } from "@abandonware/noble";

interface DeviceMatch {
  profileId: DeviceProfileId;
  profileLabel: string;
  evidence: string;
}

export function discoveredDeviceFromPeripheral(peripheral: NoblePeripheral): DiscoveredDevice {
  const advertisedServices = advertisedServiceUuids(peripheral);
  const match = classifyPeripheral(peripheral, advertisedServices);
  return {
    id: peripheral.id,
    name: cleanName(peripheral.advertisement.localName ?? peripheral.uuid ?? "Nearby device"),
    rssi: peripheral.rssi,
    profileId: match.profileId,
    profileLabel: match.profileLabel,
    advertisedServices,
    evidence: match.evidence,
    lastSeenUnixMs: Date.now(),
    ...(peripheral.address ? { address: peripheral.address } : {}),
  };
}

export function advertisedServiceUuids(peripheral: NoblePeripheral): string[] {
  const direct = peripheral.advertisement.serviceUuids ?? [];
  const serviceData = peripheral.advertisement.serviceData?.map((entry) => entry.uuid) ?? [];
  return [...new Set([...direct, ...serviceData].map(compactUuid))].sort();
}

function classifyPeripheral(peripheral: NoblePeripheral, advertisedServices: string[]): DeviceMatch {
  const name = peripheral.advertisement.localName ?? "";
  const customBandService = advertisedServices.find((uuid) => CUSTOM_BAND_SERVICE_SET.has(uuid));
  if (customBandService) {
    return {
      profileId: "custom-band",
      profileLabel: "Compatible band",
      evidence: `advertised custom service ${customBandService}`,
    };
  }

  if (isUnsupportedPowerAccessoryName(name)) {
    return {
      profileId: "unknown",
      profileLabel: "Nearby BLE",
      evidence: "unsupported power accessory name; no custom service advertised",
    };
  }

  if (looksLikeInternalBandName(name)) {
    return { profileId: "custom-band", profileLabel: "Compatible band", evidence: "advertised compatible band name" };
  }

  if (advertisedServices.includes(STANDARD_HEART_RATE_SERVICE_UUID)) {
    return { profileId: "standard-heart-rate", profileLabel: "HR strap", evidence: "advertised Heart Rate service" };
  }

  if (name.toLowerCase().includes("coospo")) {
    return { profileId: "standard-heart-rate", profileLabel: "HR strap", evidence: "advertised HR strap name" };
  }

  if (name.toUpperCase().includes("H6M")) {
    return { profileId: "standard-heart-rate", profileLabel: "HR strap", evidence: "advertised H6M strap name" };
  }

  return { profileId: "unknown", profileLabel: "Nearby BLE", evidence: "no supported service advertised" };
}

function cleanName(name: string): string {
  const trimmed = name.trim();
  return trimmed.length > 0 ? trimmed : "Nearby device";
}

function looksLikeInternalBandName(name: string): boolean {
  const normalized = name.trim().toUpperCase();
  if (normalized.includes("WHOOP")) {
    return true;
  }
  return false;
}

function isUnsupportedPowerAccessoryName(name: string): boolean {
  const normalized = name.trim().toUpperCase();
  return normalized.startsWith("WBB")
    || normalized.includes("WIRELESS POWERPACK")
    || normalized.includes("WIRELESS POWER PACK")
    || normalized === "POWERPACK"
    || normalized === "POWER PACK";
}
