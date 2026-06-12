import CoreBluetooth
import Foundation

struct OpenVitalsRRReferenceDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
  let lastSeen: Date
}

private struct OpenVitalsRRReferencePendingSample {
  let sampleID: String
  let sessionID: String
  let capturedAt: String
  let deviceName: String
  let deviceID: String
  let heartRateBPM: Double?
  let rrIntervalMS: Double
  let notificationSequence: Int
  let rrIndex: Int
  let contactDetected: Bool?
  let energyExpendedJ: Int?
}

final class OpenVitalsRRReferenceCapture: NSObject, ObservableObject {
  @Published var bluetoothState = "not requested"
  @Published var status = "No RR reference capture"
  @Published var isScanning = false
  @Published var isCapturing = false
  @Published var discoveredDevices: [OpenVitalsRRReferenceDevice] = []
  @Published var activeDeviceName = "No reference device"
  @Published var activeDeviceID = ""
  @Published var sessionID: String?
  @Published var sampleCount = 0
  @Published var notificationCount = 0
  @Published var lastHeartRateBPM: Int?
  @Published var lastRRIntervalMS: Double?
  @Published var lastCapturedAt: Date?
  @Published var lastFlushStatus = "No RR samples stored"
  @Published var summaryStatus = "No RR reference summary"

  private static let heartRateServiceUUID = CBUUID(string: "180D")
  private static let heartRateMeasurementUUID = CBUUID(string: "2A37")

  private let databasePath: String
  private var central: CBCentralManager?
  private var peripherals: [UUID: CBPeripheral] = [:]
  private var activePeripheral: CBPeripheral?
  private var heartRateCharacteristic: CBCharacteristic?
  private var pendingSamples: [OpenVitalsRRReferencePendingSample] = []
  private var startedAt: Date?
  private var notificationSequence = 0
  private var insertedSampleCount = 0
  private var flushInProgress = false

  init(databasePath: String) {
    self.databasePath = databasePath
    super.init()
  }

  func startScanning() {
    ensureCentral()
    guard central?.state == .poweredOn else {
      status = "Bluetooth is \(bluetoothState)"
      return
    }
    discoveredDevices = []
    isScanning = true
    status = "Scanning for BLE heart-rate reference devices..."
    central?.scanForPeripherals(
      withServices: [Self.heartRateServiceUUID],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  func stopScanning() {
    central?.stopScan()
    isScanning = false
    if !isCapturing {
      status = discoveredDevices.isEmpty ? "No reference devices found" : "Scan stopped"
    }
  }

  func startCapture(deviceID: UUID) {
    ensureCentral()
    guard !isCapturing else {
      status = "RR reference capture already running"
      return
    }
    guard let peripheral = peripherals[deviceID] else {
      status = "Select a discovered reference device"
      return
    }
    guard central?.state == .poweredOn else {
      status = "Bluetooth is \(bluetoothState)"
      return
    }

    let sessionID = "rr-reference.\(UUID().uuidString)"
    let startedAt = Date()
    self.sessionID = sessionID
    self.startedAt = startedAt
    activeDeviceName = peripheral.name ?? "BLE Heart Rate Reference"
    activeDeviceID = peripheral.identifier.uuidString
    sampleCount = 0
    notificationCount = 0
    insertedSampleCount = 0
    notificationSequence = 0
    lastHeartRateBPM = nil
    lastRRIntervalMS = nil
    lastCapturedAt = nil
    lastFlushStatus = "Waiting for RR samples"
    summaryStatus = "No RR reference summary"
    pendingSamples = []
    isCapturing = true
    status = "Starting RR reference session..."

    startReferenceCaptureSession(
      sessionID: sessionID,
      startedAt: startedAt,
      deviceName: activeDeviceName,
      deviceID: activeDeviceID
    ) { [weak self] success in
      guard let self else {
        return
      }
      guard success else {
        self.isCapturing = false
        self.sessionID = nil
        return
      }
      self.central?.stopScan()
      self.isScanning = false
      self.activePeripheral = peripheral
      peripheral.delegate = self
      self.status = "Connecting to \(self.activeDeviceName)..."
      self.central?.connect(peripheral)
    }
  }

  func stopCapture() {
    guard isCapturing else {
      status = "No RR reference capture is running"
      return
    }
    status = "Stopping RR reference capture..."
    if let activePeripheral, let heartRateCharacteristic {
      activePeripheral.setNotifyValue(false, for: heartRateCharacteristic)
    }
    if let activePeripheral {
      central?.cancelPeripheralConnection(activePeripheral)
    }
    finishCaptureSession()
  }

  func refreshSummary() {
    guard let sessionID else {
      summaryStatus = "No RR reference session"
      return
    }
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "reference_rr.summary",
        args: [
          "database_path": self.databasePath,
          "session_id": sessionID,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
        let samples = MoreDataStore.firstString(value, keys: ["sample_count"]) ?? "0"
        let notifications = MoreDataStore.firstString(value, keys: ["notification_count"]) ?? "0"
        let medianRR = MoreDataStore.firstString(value, keys: ["median_rr_interval_ms"]) ?? "--"
        let rmssd = MoreDataStore.firstString(value, keys: ["rmssd_ms"]) ?? "--"
        self.summaryStatus = "\(samples) RR samples | \(notifications) notifications | median RR \(medianRR) ms | RMSSD \(rmssd) ms"
      case .failure(let error):
        self.summaryStatus = "Summary failed: \(MoreDataStore.errorSummary(error))"
      }
    }
  }

  private func ensureCentral() {
    if central == nil {
      central = CBCentralManager(delegate: self, queue: nil)
    }
  }

  private func startReferenceCaptureSession(
    sessionID: String,
    startedAt: Date,
    deviceName: String,
    deviceID: String,
    completion: @escaping (Bool) -> Void
  ) {
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "capture.start_session",
        args: [
          "database_path": self.databasePath,
          "session_id": sessionID,
          "source": "ios.rr_reference_capture",
          "started_at_unix_ms": Self.unixMilliseconds(startedAt),
          "device_model": deviceName,
          "active_device_id": deviceID,
          "provenance": [
            "schema": "open_vitals.rr-reference-capture-provenance.v1",
            "collector": "OpenVitalsRRReferenceCapture",
            "service_uuid": Self.heartRateServiceUUID.uuidString,
            "measurement_characteristic_uuid": Self.heartRateMeasurementUUID.uuidString,
            "storage_policy": "standard_ble_rr_reference_for_validation_only",
          ],
        ]
      )
    }) { [weak self] result in
      switch result {
      case .success:
        completion(true)
      case .failure(let error):
        self?.status = "Could not start RR reference session: \(MoreDataStore.errorSummary(error))"
        completion(false)
      }
    }
  }

  private func finishCaptureSession() {
    let endedAt = Date()
    let sessionID = sessionID
    flushPendingSamples()
    isCapturing = false
    status = "RR reference capture stopped"
    heartRateCharacteristic = nil
    activePeripheral = nil
    guard let sessionID else {
      return
    }

    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "capture.finish_session",
        args: [
          "database_path": self.databasePath,
          "session_id": sessionID,
          "ended_at_unix_ms": Self.unixMilliseconds(endedAt),
          "frame_count": self.sampleCount,
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success:
        self.status = "RR reference capture stopped | \(self.sampleCount) samples"
        self.refreshSummary()
      case .failure(let error):
        self.status = "Stop saved locally; session finish failed: \(MoreDataStore.errorSummary(error))"
      }
    }
  }

  private func handleHeartRateMeasurement(_ data: Data, capturedAt: Date) {
    guard let sessionID, let activePeripheral else {
      return
    }
    let measurement = Self.parseHeartRateMeasurement(data)
    notificationSequence += 1
    notificationCount += 1
    lastHeartRateBPM = measurement.heartRateBPM
    lastCapturedAt = capturedAt

    guard !measurement.rrIntervalsMS.isEmpty else {
      status = "Reference connected, waiting for RR intervals..."
      return
    }

    let capturedAtText = capturedAt.moreISO8601String()
    let deviceName = activePeripheral.name ?? activeDeviceName
    let deviceID = activePeripheral.identifier.uuidString
    let newSamples = measurement.rrIntervalsMS.enumerated().map { index, rrIntervalMS in
      OpenVitalsRRReferencePendingSample(
        sampleID: "\(sessionID).\(notificationSequence).\(index)",
        sessionID: sessionID,
        capturedAt: capturedAtText,
        deviceName: deviceName,
        deviceID: deviceID,
        heartRateBPM: measurement.heartRateBPM.map(Double.init),
        rrIntervalMS: rrIntervalMS,
        notificationSequence: notificationSequence,
        rrIndex: index,
        contactDetected: measurement.contactDetected,
        energyExpendedJ: measurement.energyExpendedJ
      )
    }
    pendingSamples.append(contentsOf: newSamples)
    sampleCount += newSamples.count
    lastRRIntervalMS = measurement.rrIntervalsMS.last
    status = "Capturing RR reference | \(sampleCount) samples"
    flushPendingSamples()
  }

  private func flushPendingSamples() {
    guard !flushInProgress, !pendingSamples.isEmpty else {
      return
    }
    flushInProgress = true
    let samples = pendingSamples
    pendingSamples.removeAll()
    OpenVitalsRustBridge.performInBackground(qos: .utility, {
      try OpenVitalsRustBridge().request(
        method: "reference_rr.insert_samples",
        args: [
          "database_path": self.databasePath,
          "samples": samples.map(Self.bridgeSample),
        ]
      )
    }) { [weak self] result in
      guard let self else {
        return
      }
      self.flushInProgress = false
      switch result {
      case .success(let value):
        let inserted = MoreDataStore.firstString(value, keys: ["inserted_count"]) ?? "0"
        self.insertedSampleCount += Int(inserted) ?? 0
        self.lastFlushStatus = "Stored \(self.insertedSampleCount)/\(self.sampleCount) RR samples"
      case .failure(let error):
        self.pendingSamples.insert(contentsOf: samples, at: 0)
        self.lastFlushStatus = "Store failed: \(MoreDataStore.errorSummary(error))"
      }
      if !self.pendingSamples.isEmpty {
        self.flushPendingSamples()
      }
    }
  }

  private static func bridgeSample(_ sample: OpenVitalsRRReferencePendingSample) -> [String: Any] {
    var row: [String: Any] = [
      "sample_id": sample.sampleID,
      "session_id": sample.sessionID,
      "captured_at": sample.capturedAt,
      "device_name": sample.deviceName,
      "device_id": sample.deviceID,
      "rr_interval_ms": sample.rrIntervalMS,
      "notification_sequence": sample.notificationSequence,
      "rr_index": sample.rrIndex,
      "provenance": [
        "schema": "open_vitals.rr-reference-sample-provenance.v1",
        "service_uuid": heartRateServiceUUID.uuidString,
        "characteristic_uuid": heartRateMeasurementUUID.uuidString,
        "source": "standard_ble_heart_rate_service",
        "unit": "rr_interval_ms",
      ],
    ]
    if let heartRateBPM = sample.heartRateBPM {
      row["heart_rate_bpm"] = heartRateBPM
    }
    if let contactDetected = sample.contactDetected {
      row["contact_detected"] = contactDetected
    }
    if let energyExpendedJ = sample.energyExpendedJ {
      row["energy_expended_j"] = energyExpendedJ
    }
    return row
  }

  private static func parseHeartRateMeasurement(_ data: Data) -> (
    heartRateBPM: Int?,
    contactDetected: Bool?,
    energyExpendedJ: Int?,
    rrIntervalsMS: [Double]
  ) {
    let bytes = [UInt8](data)
    guard !bytes.isEmpty else {
      return (nil, nil, nil, [])
    }
    let flags = bytes[0]
    var index = 1
    let heartRateBPM: Int?
    if flags & 0x01 == 0x01 {
      guard index + 1 < bytes.count else {
        return (nil, nil, nil, [])
      }
      heartRateBPM = Int(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
      index += 2
    } else {
      guard index < bytes.count else {
        return (nil, nil, nil, [])
      }
      heartRateBPM = Int(bytes[index])
      index += 1
    }

    let contactDetected: Bool?
    if flags & 0x06 == 0x06 {
      contactDetected = true
    } else if flags & 0x04 == 0x04 {
      contactDetected = false
    } else {
      contactDetected = nil
    }

    let energyExpendedJ: Int?
    if flags & 0x08 == 0x08 {
      guard index + 1 < bytes.count else {
        return (heartRateBPM, contactDetected, nil, [])
      }
      energyExpendedJ = Int(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
      index += 2
    } else {
      energyExpendedJ = nil
    }

    var rrIntervalsMS: [Double] = []
    if flags & 0x10 == 0x10 {
      while index + 1 < bytes.count {
        let raw = UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        rrIntervalsMS.append((Double(raw) / 1024.0) * 1000.0)
        index += 2
      }
    }
    return (heartRateBPM, contactDetected, energyExpendedJ, rrIntervalsMS)
  }

  private static func unixMilliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}

extension OpenVitalsRRReferenceCapture: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    bluetoothState = Self.bluetoothStateText(central.state)
    if central.state != .poweredOn {
      isScanning = false
      status = "Bluetooth is \(bluetoothState)"
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    peripherals[peripheral.identifier] = peripheral
    let name = peripheral.name
      ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
      ?? "BLE Heart Rate Reference"
    let device = OpenVitalsRRReferenceDevice(
      id: peripheral.identifier,
      name: name,
      rssi: RSSI.intValue,
      lastSeen: Date()
    )
    if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
      discoveredDevices[index] = device
    } else {
      discoveredDevices.append(device)
    }
    discoveredDevices.sort { left, right in
      if left.rssi == right.rssi {
        return left.name < right.name
      }
      return left.rssi > right.rssi
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    status = "Discovering heart-rate service..."
    peripheral.discoverServices([Self.heartRateServiceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    isCapturing = false
    status = "Reference connect failed: \(error.map(MoreDataStore.errorSummary) ?? "unknown error")"
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if isCapturing {
      status = "Reference disconnected: \(error.map(MoreDataStore.errorSummary) ?? "ended")"
      finishCaptureSession()
    }
  }

  private static func bluetoothStateText(_ state: CBManagerState) -> String {
    switch state {
    case .unknown:
      return "unknown"
    case .resetting:
      return "resetting"
    case .unsupported:
      return "unsupported"
    case .unauthorized:
      return "unauthorized"
    case .poweredOff:
      return "powered off"
    case .poweredOn:
      return "powered on"
    @unknown default:
      return "unknown"
    }
  }
}

extension OpenVitalsRRReferenceCapture: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      status = "Reference service discovery failed: \(MoreDataStore.errorSummary(error))"
      return
    }
    guard let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateServiceUUID }) else {
      status = "Reference device has no heart-rate service"
      return
    }
    peripheral.discoverCharacteristics([Self.heartRateMeasurementUUID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error {
      status = "Reference characteristic discovery failed: \(MoreDataStore.errorSummary(error))"
      return
    }
    guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.heartRateMeasurementUUID }) else {
      status = "Reference device has no heart-rate measurement characteristic"
      return
    }
    heartRateCharacteristic = characteristic
    status = "Subscribing to RR reference stream..."
    peripheral.setNotifyValue(true, for: characteristic)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      status = "Reference notify failed: \(MoreDataStore.errorSummary(error))"
      return
    }
    if characteristic.isNotifying {
      status = "RR reference capture listening"
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      status = "Reference update failed: \(MoreDataStore.errorSummary(error))"
      return
    }
    guard characteristic.uuid == Self.heartRateMeasurementUUID,
          let value = characteristic.value else {
      return
    }
    handleHeartRateMeasurement(value, capturedAt: Date())
  }
}
