import { app, BrowserWindow, ipcMain, shell } from "electron";
import path from "node:path";
import { IPC } from "../shared/ipc";
import type { StartBandParityProbeOptions, StartCaptureOptions } from "../shared/types";
import { BleHostClient } from "./runtime/BleHostClient";

let mainWindow: BrowserWindow | undefined;
let hostClient: BleHostClient | undefined;

const useBuiltRenderer = process.env.OPENVITALS_BLE_DEBUGGER_USE_BUILT === "1";
const devServerUrl = process.env.VITE_DEV_SERVER_URL;
const isDev = !useBuiltRenderer && devServerUrl !== undefined;

function repoRoot(): string {
  return process.env.OPENVITALS_REPO_ROOT ?? path.resolve(app.getAppPath(), "../..");
}

function defaultDatabasePath(): string {
  return process.env.OPENVITALS_BLE_DEBUGGER_DB
    ?? path.join(app.getPath("userData"), "open_vitals_ble_debugger.sqlite");
}

function createWindow(): void {
  hostClient = new BleHostClient({
    hostPath: path.join(__dirname, "bleHost.js"),
    repoRoot: repoRoot(),
    databasePath: defaultDatabasePath(),
  });
  hostClient.on("state", (state) => {
    mainWindow?.webContents.send(IPC.stateChanged, state);
  });
  hostClient.start();

  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1160,
    minHeight: 720,
    title: "OpenVitals BLE Packet Debugger",
    backgroundColor: "#f7f8fa",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  if (isDev) {
    void mainWindow.loadURL(devServerUrl);
  } else {
    void mainWindow.loadFile(path.join(app.getAppPath(), "dist-renderer", "index.html"));
  }

  mainWindow.on("closed", () => {
    mainWindow = undefined;
  });
}

function requireHost(): BleHostClient {
  if (!hostClient) {
    throw new Error("BLE host is not running");
  }
  return hostClient;
}

app.whenReady().then(() => {
  registerIpcHandlers();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
}).catch((error) => {
  console.error(error);
  app.quit();
});

app.on("before-quit", () => {
  hostClient?.stop();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

function registerIpcHandlers(): void {
  ipcMain.handle(IPC.getState, () => requireHost().request("getState"));
  ipcMain.handle(IPC.startScan, () => requireHost().request("startScan"));
  ipcMain.handle(IPC.stopScan, () => requireHost().request("stopScan"));
  ipcMain.handle(IPC.connect, (_event, deviceId: string) => requireHost().request("connect", { deviceId }));
  ipcMain.handle(IPC.disconnect, () => requireHost().request("disconnect"));
  ipcMain.handle(IPC.startCapture, (_event, options?: StartCaptureOptions) => {
    return requireHost().request("startCapture", options ?? {});
  });
  ipcMain.handle(IPC.stopCapture, () => requireHost().request("stopCapture"));
  ipcMain.handle(IPC.setDatabasePath, (_event, databasePath: string) => {
    return requireHost().request("setDatabasePath", { databasePath });
  });
  ipcMain.handle(IPC.storageCheck, () => requireHost().request("storageCheck"));
  ipcMain.handle(IPC.sendHello, () => requireHost().request("sendHello"));
  ipcMain.handle(IPC.startIosParityPhysiologyProbe, () => {
    return requireHost().request("startIosParityPhysiologyProbe", { delayMs: 5_000 });
  });
  ipcMain.handle(IPC.startBandParityProbe, (_event, options?: StartBandParityProbeOptions) => {
    return requireHost().request("startBandParityProbe", options ?? {}, 90_000);
  });
  ipcMain.handle(IPC.runNativeAuthProbe, () => {
    return requireHost().request("runNativeAuthProbe", {}, 90_000);
  });
  ipcMain.handle(IPC.checkMacPairingStatus, () => {
    return requireHost().request("checkMacPairingStatus", {}, 30_000);
  });
  ipcMain.handle(IPC.openBluetoothSettings, async () => {
    await shell.openExternal("x-apple.systempreferences:com.apple.BluetoothSettings");
  });
  ipcMain.handle(IPC.startPhysiologyCapture, () => requireHost().request("startPhysiologyCapture"));
  ipcMain.handle(IPC.stopPhysiologyCapture, () => requireHost().request("stopPhysiologyCapture"));
  ipcMain.handle(IPC.enterHighFrequencyHistorySync, () => {
    return requireHost().request("enterHighFrequencyHistorySync");
  });
  ipcMain.handle(IPC.exitHighFrequencyHistorySync, () => requireHost().request("exitHighFrequencyHistorySync"));
  ipcMain.handle(IPC.selectPacket, (_event, packetId: string) => {
    return requireHost().request("selectPacket", { packetId });
  });
}
