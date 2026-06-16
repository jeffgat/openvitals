import CoreBluetooth
import Foundation
import OSLog

extension OpenVitalsBLEClient: CBCentralManagerDelegate {
  func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, willRestoreState: dict)
    }) {
      return
    }

    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    record(source: "ble", title: "central.restore_state", body: "peripherals=\(restored.count)")
    guard let peripheral = restored.first else {
      updateReconnectState("restore empty")
      return
    }
    guard let evidence = whoopIdentityEvidence(for: peripheral) else {
      updateReconnectState("restore ignored unsupported device")
      rejectNonWhoopPeripheral(peripheral, reason: "restore_without_whoop_evidence", disconnect: true)
      return
    }
    whoopCandidateIDs.insert(peripheral.identifier)
    peripherals[peripheral.identifier] = peripheral
    selectedDeviceID = peripheral.identifier
    activePeripheral = peripheral
    peripheral.delegate = self
    rememberPeripheral(peripheral, evidence: evidence)
    if autoHistoricalSyncOnReady && !prioritizeLiveCaptureOnReady {
      pendingAutomaticHistoricalSyncReason = "restore"
    } else {
      pendingAutomaticHistoricalSyncReason = nil
      record(
        source: "ble.sync",
        title: "historical_sync.auto_skipped",
        body: "reason=restore autoHistoricalSync=\(autoHistoricalSyncOnReady) prioritizeLive=\(prioritizeLiveCaptureOnReady)"
      )
    }
    updateReconnectState("restored")
    switch peripheral.state {
    case .connected:
      let now = Date()
      connectedAt = now
      lastSyncAt = now
      updateConnectionState("discovering")
      peripheral.discoverServices(serviceDiscoveryIDs)
      processCachedServicesIfAvailable(peripheral, reason: "restore.connected")
    case .connecting:
      updateConnectionState("connecting")
    case .disconnected, .disconnecting:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    @unknown default:
      if central.state == .poweredOn {
        connect(peripheral, reason: "restore")
      }
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManagerDidUpdateState(central)
    }) {
      return
    }

    updateBluetoothState()
    if central.state == .poweredOn {
      if !startupReconnectAttempted {
        startupReconnectAttempted = true
        attemptAutomaticReconnect(reason: "startup")
      }
    } else {
      isScanning = false
      if isHistoricalSyncing {
        failHistoricalSync("Bluetooth became unavailable during historical sync. State: \(bluetoothState).")
      }
      updateConnectionState("disconnected")
      updateReconnectState("waiting for bluetooth")
      connectedAt = nil
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }) {
      return
    }

    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let advertisedServices = advertisedServiceUUIDs(from: advertisementData)
    let diagnosticName = peripheral.name ?? advertisedName
    if unsupportedAccessoryIDs.contains(peripheral.identifier) {
      recordScanDiagnostic(
        id: peripheral.identifier,
        name: diagnosticName,
        rssi: RSSI.intValue,
        advertisedServices: advertisedServices,
        status: "ignored: unsupported accessory"
      )
      rejectNonWhoopPeripheral(peripheral, reason: "scan_unsupported_accessory", fallbackName: advertisedName)
      return
    }
    let evidence = whoopIdentityEvidence(
      for: peripheral,
      fallbackName: advertisedName,
      advertisedServices: advertisedServices,
      allowRememberedValidation: true
    )
    recordScanDiagnostic(
      id: peripheral.identifier,
      name: diagnosticName,
      rssi: RSSI.intValue,
      advertisedServices: advertisedServices,
      status: evidence.map { "compatible: \($0)" } ?? "ignored: no WHOOP evidence"
    )
    guard let evidence else {
      rejectNonWhoopPeripheral(peripheral, reason: "scan_without_whoop_evidence", fallbackName: advertisedName)
      return
    }

    whoopCandidateIDs.insert(peripheral.identifier)
    peripherals[peripheral.identifier] = peripheral
    let name = Self.sanitizedWhoopDisplayName(peripheral.name ?? advertisedName ?? "Device")
    let serviceUUIDs = advertisedServices
      .map(\.uuidString)
      .joined(separator: ",")
    let device = OpenVitalsDiscoveredDevice(
      id: peripheral.identifier,
      name: name,
      rssi: RSSI.intValue
    )

    discoveredDevices.removeAll { $0.id == device.id }
    discoveredDevices.append(device)
    discoveredDevices.sort { $0.rssi > $1.rssi }
    selectedDeviceID = selectedDeviceID ?? device.id
    record(
      source: "ble",
      title: "device.discovered",
      body: "\(name) id=\(device.id.uuidString) rssi=\(device.rssi) services=\(serviceUUIDs) evidence=\(evidence)"
    )

    if autoConnectForPhysiologyCapture && activePeripheral == nil {
      record(source: "ble.sensor", title: "physiology_capture.scan.match", body: "\(peripheral.identifier.uuidString) evidence=\(evidence)")
      autoConnectForPhysiologyCapture = false
      stopScan(reason: "auto_physiology_capture_match")
      connect(peripheral, reason: "auto_physiology_scan")
      return
    }

    if autoReconnectTargetID == peripheral.identifier || shouldAutoConnectDiscoveredWhoop(peripheral) {
      record(source: "ble", title: "reconnect.scan_match", body: "\(peripheral.identifier.uuidString) evidence=\(evidence)")
      autoReconnectTargetID = nil
      stopScan(reason: "auto_reconnect_whoop_match")
      let connectReason = autoStartPhysiologyCaptureOnReady
        ? "auto_physiology_scan_remembered"
        : "auto.scan"
      connect(peripheral, reason: connectReason)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didConnect: peripheral)
    }) {
      return
    }

    let fallbackName = discoveredDevices.first { $0.id == peripheral.identifier }?.name
    guard let evidence = whoopIdentityEvidence(for: peripheral, fallbackName: fallbackName) else {
      pendingConnectionReason = nil
      autoReconnectInFlight = false
      autoReconnectTargetID = nil
      rejectNonWhoopPeripheral(peripheral, reason: "connected_without_whoop_evidence", fallbackName: fallbackName, disconnect: true)
      return
    }

    whoopCandidateIDs.insert(peripheral.identifier)
    activePeripheral = peripheral
    peripheral.delegate = self
    connectTimeoutWorkItem?.cancel()
    commandWriteAuthenticationRequired = false
    commandWriteAuthenticationStatus = "No command authentication failures"
    clientHelloSentForCurrentConnection = false
    autoReconnectInFlight = false
    autoReconnectTargetID = nil
    let reason = pendingConnectionReason ?? "unknown"
    pendingConnectionReason = nil
    if pendingHistoricalSyncResumeRequest == nil,
       !prioritizeLiveCaptureOnReady,
       reason == "manual" || reason.hasPrefix("auto.") || reason == "restore" {
      if autoHistoricalSyncOnReady {
        pendingAutomaticHistoricalSyncReason = reason
      } else {
        pendingAutomaticHistoricalSyncReason = nil
        record(
          source: "ble.sync",
          title: "historical_sync.auto_skipped",
          body: "reason=\(reason) autoHistoricalSync=false"
        )
      }
    }
    rememberPeripheral(
      peripheral,
      fallbackName: fallbackName,
      evidence: evidence
    )
    let now = Date()
    connectedAt = now
    lastSyncAt = now
    updateConnectionState("discovering")
    updateReconnectState("connected")
    record(source: "ble", title: "connect.succeeded", body: "\(peripheral.name ?? fallbackName ?? "Device") \(peripheral.identifier.uuidString) evidence=\(evidence)")
    peripheral.discoverServices(serviceDiscoveryIDs)
    processCachedServicesIfAvailable(peripheral, reason: "connect.\(reason)")
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didFailToConnect: peripheral, error: error)
    }) {
      return
    }

    autoReconnectInFlight = false
    autoConnectForPhysiologyCapture = false
    pendingConnectionReason = nil
    connectTimeoutWorkItem?.cancel()
    updateConnectionState("connect failed")
    updateReconnectState("connect failed")
    record(level: .error, source: "ble", title: "connect.failed", body: error?.localizedDescription ?? "unknown")
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    if dispatchCoreBluetoothDelegateToMainIfNeeded({ [weak self] in
      self?.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
    }) {
      return
    }

    let userRequestedDisconnect = userDisconnectRequestedIDs.remove(peripheral.identifier) != nil
    let shouldReconnect = !userRequestedDisconnect && rememberedDeviceID == peripheral.identifier
    autoReconnectInFlight = false
    autoConnectForPhysiologyCapture = false
    autoStartedPhysiologyCapture = false
    connectTimeoutWorkItem?.cancel()
    readySyncWorkItem?.cancel()
    if isHistoricalSyncing {
      let message = "Device disconnected during historical sync. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")"
      if shouldReconnect {
        pauseHistoricalSyncForReconnect(message)
      } else {
        failHistoricalSync(message)
      }
    }
    if pendingAlarmCommand != nil {
      failAlarmCommand("Device disconnected during alarm command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    if pendingClockCommand != nil {
      failClockCommand("Device disconnected during clock command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    if !pendingDebugCommands.isEmpty {
      failAllDebugCommands("Device disconnected during debug command. \(error?.localizedDescription ?? "No CoreBluetooth error was provided.")")
    }
    updateConnectionState(userRequestedDisconnect ? "disconnected" : (error?.localizedDescription ?? "disconnected"))
    record(
      level: error == nil ? .info : .warn,
      source: "ble",
      title: "disconnect",
      body: userRequestedDisconnect ? "user reset \(peripheral.identifier.uuidString)" : (error?.localizedDescription ?? peripheral.identifier.uuidString)
    )
    activePeripheral = nil
    commandCharacteristic = nil
    batteryLevelCharacteristic = nil
    batteryLevelStatusCharacteristic = nil
    clientHelloSentForCurrentConnection = false
    connectedAt = nil
    if shouldReconnect {
      let reconnectReason = prioritizeLiveCaptureOnReady ? "auto_live_capture_disconnect" : "auto.disconnect"
      if pendingHistoricalSyncResumeRequest != nil {
        pendingAutomaticHistoricalSyncReason = nil
      } else if autoHistoricalSyncOnReady && !prioritizeLiveCaptureOnReady {
        pendingAutomaticHistoricalSyncReason = reconnectReason
      } else {
        pendingAutomaticHistoricalSyncReason = nil
        record(
          source: "ble.sync",
          title: "historical_sync.auto_skipped",
          body: "reason=\(reconnectReason) autoHistoricalSync=\(autoHistoricalSyncOnReady) prioritizeLive=\(prioritizeLiveCaptureOnReady)"
        )
      }
      updateReconnectState("reconnecting after disconnect")
      connect(peripheral, reason: reconnectReason)
    } else if userRequestedDisconnect {
      updateReconnectState("reset")
    }
  }
}
