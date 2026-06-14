import type { RustDeviceType } from "../../shared/types";

export interface DeframeResult {
  frames: Buffer[];
  bufferedLen: number;
  droppedPrefixLen: number;
}

export class FrameAccumulator {
  private buffer = Buffer.alloc(0);

  constructor(private readonly deviceType: RustDeviceType) {}

  feed(chunk: Buffer): DeframeResult {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const frames: Buffer[] = [];
    let droppedPrefixLen = this.dropUntilFrameStart();

    while (true) {
      const expected = expectedFrameLength(this.deviceType, this.buffer);
      if (expected === undefined || this.buffer.length < expected) {
        break;
      }
      frames.push(this.buffer.subarray(0, expected));
      this.buffer = this.buffer.subarray(expected);
      droppedPrefixLen += this.dropUntilFrameStart();
    }

    return {
      frames,
      bufferedLen: this.buffer.length,
      droppedPrefixLen,
    };
  }

  private dropUntilFrameStart(): number {
    const start = this.buffer.indexOf(0xaa);
    if (start === 0) {
      return 0;
    }
    if (start > 0) {
      this.buffer = this.buffer.subarray(start);
      return start;
    }
    const dropped = this.buffer.length;
    this.buffer = Buffer.alloc(0);
    return dropped;
  }
}

function expectedFrameLength(deviceType: RustDeviceType, buffer: Buffer): number | undefined {
  if (deviceType === "GEN4") {
    if (buffer.length < 4) {
      return undefined;
    }
    return buffer.readUInt16LE(1) + 4;
  }
  if (buffer.length < 8) {
    return undefined;
  }
  return buffer.readUInt16LE(2) + 8;
}
