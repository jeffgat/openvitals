declare module "@abandonware/noble" {
  import { EventEmitter } from "node:events";

  export interface NobleAdvertisement {
    localName?: string;
    serviceUuids?: string[];
    serviceData?: Array<{ uuid: string; data: Buffer }>;
  }

  export interface NobleCharacteristic extends EventEmitter {
    uuid: string;
    properties: string[];
    read(callback: (error: Error | null, data?: Buffer) => void): void;
    subscribe(callback: (error?: Error | null) => void): void;
    unsubscribe(callback: (error?: Error | null) => void): void;
    write(data: Buffer, withoutResponse: boolean, callback?: (error?: Error | null) => void): void;
  }

  export interface NobleService {
    uuid: string;
  }

  export interface NoblePeripheral extends EventEmitter {
    id: string;
    uuid: string;
    address?: string;
    rssi: number;
    advertisement: NobleAdvertisement;
    connect(callback: (error?: Error | null) => void): void;
    disconnect(callback?: (error?: Error | null) => void): void;
    discoverAllServicesAndCharacteristics(
      callback: (error: Error | null, services: NobleService[], characteristics: NobleCharacteristic[]) => void,
    ): void;
  }

  export interface Noble extends EventEmitter {
    state: string;
    startScanning(serviceUuids: string[], allowDuplicates: boolean, callback?: (error?: Error | null) => void): void;
    stopScanning(callback?: () => void): void;
    on(event: "stateChange", listener: (state: string) => void): this;
    on(event: "discover", listener: (peripheral: NoblePeripheral) => void): this;
  }

  const noble: Noble;
  export default noble;
}
