import { contextBridge, ipcRenderer } from "electron";
import { IPC } from "../shared/ipc";
import type {
  DebuggerAppState,
  StartBandParityProbeOptions,
  StartCaptureOptions,
  StorageCheckResult,
} from "../shared/types";

contextBridge.exposeInMainWorld("openVitalsDebugger", {
  getState: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.getState),
  startScan: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.startScan),
  stopScan: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.stopScan),
  connect: (deviceId: string): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.connect, deviceId),
  disconnect: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.disconnect),
  startCapture: (options?: StartCaptureOptions): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.startCapture, options);
  },
  stopCapture: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.stopCapture),
  setDatabasePath: (databasePath: string): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.setDatabasePath, databasePath);
  },
  storageCheck: (): Promise<StorageCheckResult> => ipcRenderer.invoke(IPC.storageCheck),
  sendHello: (): Promise<DebuggerAppState> => ipcRenderer.invoke(IPC.sendHello),
  startIosParityPhysiologyProbe: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.startIosParityPhysiologyProbe);
  },
  startBandParityProbe: (options?: StartBandParityProbeOptions): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.startBandParityProbe, options);
  },
  runNativeAuthProbe: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.runNativeAuthProbe);
  },
  checkMacPairingStatus: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.checkMacPairingStatus);
  },
  openBluetoothSettings: (): Promise<void> => {
    return ipcRenderer.invoke(IPC.openBluetoothSettings);
  },
  startPhysiologyCapture: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.startPhysiologyCapture);
  },
  stopPhysiologyCapture: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.stopPhysiologyCapture);
  },
  enterHighFrequencyHistorySync: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.enterHighFrequencyHistorySync);
  },
  exitHighFrequencyHistorySync: (): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.exitHighFrequencyHistorySync);
  },
  selectPacket: (packetId: string): Promise<DebuggerAppState> => {
    return ipcRenderer.invoke(IPC.selectPacket, packetId);
  },
  onStateChanged: (callback: (state: DebuggerAppState) => void): (() => void) => {
    const listener = (_event: Electron.IpcRendererEvent, state: DebuggerAppState) => callback(state);
    ipcRenderer.on(IPC.stateChanged, listener);
    return () => {
      ipcRenderer.off(IPC.stateChanged, listener);
    };
  },
});
