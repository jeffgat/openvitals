import type {
  DebuggerAppState,
  StartBandParityProbeOptions,
  StartCaptureOptions,
  StorageCheckResult,
} from "../shared/types";

declare global {
  interface Window {
    openVitalsDebugger?: {
      getState(): Promise<DebuggerAppState>;
      startScan(): Promise<DebuggerAppState>;
      stopScan(): Promise<DebuggerAppState>;
      connect(deviceId: string): Promise<DebuggerAppState>;
      disconnect(): Promise<DebuggerAppState>;
      startCapture(options?: StartCaptureOptions): Promise<DebuggerAppState>;
      stopCapture(): Promise<DebuggerAppState>;
      setDatabasePath(databasePath: string): Promise<DebuggerAppState>;
      storageCheck(): Promise<StorageCheckResult>;
      sendHello(): Promise<DebuggerAppState>;
      startIosParityPhysiologyProbe(): Promise<DebuggerAppState>;
      startBandParityProbe(options?: StartBandParityProbeOptions): Promise<DebuggerAppState>;
      runNativeAuthProbe(): Promise<DebuggerAppState>;
      checkMacPairingStatus(): Promise<DebuggerAppState>;
      openBluetoothSettings(): Promise<void>;
      startPhysiologyCapture(): Promise<DebuggerAppState>;
      stopPhysiologyCapture(): Promise<DebuggerAppState>;
      enterHighFrequencyHistorySync(): Promise<DebuggerAppState>;
      exitHighFrequencyHistorySync(): Promise<DebuggerAppState>;
      selectPacket(packetId: string): Promise<DebuggerAppState>;
      onStateChanged(callback: (state: DebuggerAppState) => void): () => void;
    };
  }
}

export {};
