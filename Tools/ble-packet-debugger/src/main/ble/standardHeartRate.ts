import type { StandardHeartRateSample } from "../../shared/types";

export function parseStandardHeartRateMeasurement(data: Buffer): StandardHeartRateSample | undefined {
  if (data.length < 2) {
    return undefined;
  }

  const flags = data[0];
  if (flags === undefined) {
    return undefined;
  }
  const isUInt16 = (flags & 0x01) !== 0;
  let offset = 1;
  if (data.length < offset + (isUInt16 ? 2 : 1)) {
    return undefined;
  }

  const bpm = isUInt16 ? data.readUInt16LE(offset) : data[offset];
  offset += isUInt16 ? 2 : 1;
  if (bpm === undefined) {
    return undefined;
  }

  const contactSupported = (flags & 0x04) !== 0;
  const contactDetected = contactSupported ? (flags & 0x02) !== 0 : undefined;

  const energyExpendedJ = (flags & 0x08) !== 0 && data.length >= offset + 2
    ? data.readUInt16LE(offset)
    : undefined;
  if ((flags & 0x08) !== 0) {
    offset += 2;
  }

  const rrIntervalsMs: number[] = [];
  if ((flags & 0x10) !== 0) {
    while (data.length >= offset + 2) {
      rrIntervalsMs.push((data.readUInt16LE(offset) / 1024) * 1000);
      offset += 2;
    }
  }

  return {
    bpm,
    rrIntervalsMs,
    ...(contactDetected === undefined ? {} : { contactDetected }),
    ...(energyExpendedJ === undefined ? {} : { energyExpendedJ }),
  };
}
