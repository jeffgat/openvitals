import CoreBluetooth
import Foundation

final class CoreBluetoothProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private let serviceUUID = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
  private let commandUUID = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
  private let notifyUUIDs: Set<CBUUID> = [
    CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0004-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0005-cce1-4033-93ce-002d5875f58a"),
    CBUUID(string: "fd4b0007-cce1-4033-93ce-002d5875f58a"),
  ]
  private let helloFrame = Data(hex: "aa0108000001e67123019101363e5c8d")

  private var manager: CBCentralManager!
  private var peripheral: CBPeripheral?
  private var commandCharacteristic: CBCharacteristic?
  private var requestedNotify = Set<CBUUID>()
  private var confirmedNotify = Set<CBUUID>()
  private var helloSent = false
  private var customNotifyCount = 0

  func start() {
    manager = CBCentralManager(delegate: self, queue: .main)
    DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
      self?.finish(code: 2, reason: "timeout customNotify=\(self?.customNotifyCount ?? 0)")
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("central state=\(central.state.rawValue)")
    guard central.state == .poweredOn else { return }
    central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    print("scan started service=\(serviceUUID.uuidString)")
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "unknown"
    print("discovered name=\(name) id=\(peripheral.identifier.uuidString) rssi=\(RSSI)")
    self.peripheral = peripheral
    peripheral.delegate = self
    central.stopScan()
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("connected id=\(peripheral.identifier.uuidString)")
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    finish(code: 3, reason: "connect failed \(error?.localizedDescription ?? "unknown")")
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      finish(code: 4, reason: "service discovery failed \(error.localizedDescription)")
      return
    }
    for service in peripheral.services ?? [] {
      print("service \(service.uuid.uuidString)")
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error {
      finish(code: 5, reason: "characteristic discovery failed \(service.uuid.uuidString) \(error.localizedDescription)")
      return
    }
    for characteristic in service.characteristics ?? [] {
      let props = propertyNames(characteristic.properties)
      print("characteristic \(characteristic.uuid.uuidString) props=\(props)")
      if characteristic.uuid == commandUUID {
        commandCharacteristic = characteristic
      }
      if notifyUUIDs.contains(characteristic.uuid) {
        requestedNotify.insert(characteristic.uuid)
        peripheral.setNotifyValue(true, for: characteristic)
        print("notify requested \(characteristic.uuid.uuidString)")
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.sendHelloIfPossible(reason: "post_notify_wait")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      print("notify state \(characteristic.uuid.uuidString) error=\(error.localizedDescription) isNotifying=\(characteristic.isNotifying)")
    } else {
      print("notify state \(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying)")
    }
    if characteristic.isNotifying {
      confirmedNotify.insert(characteristic.uuid)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      print("write \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
    } else {
      print("write \(characteristic.uuid.uuidString) ok")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      print("value \(characteristic.uuid.uuidString) error=\(error.localizedDescription)")
      return
    }
    let hex = characteristic.value?.hexString ?? ""
    print("value \(characteristic.uuid.uuidString) bytes=\(characteristic.value?.count ?? 0) hex=\(hex)")
    if notifyUUIDs.contains(characteristic.uuid) {
      customNotifyCount += 1
      finish(code: 0, reason: "custom notify received uuid=\(characteristic.uuid.uuidString)")
    }
  }

  private func sendHelloIfPossible(reason: String) {
    guard !helloSent else { return }
    guard let peripheral, let commandCharacteristic else {
      finish(code: 6, reason: "missing command characteristic")
      return
    }
    let writeType: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    print("hello sending reason=\(reason) writeType=\(writeType == .withResponse ? "withResponse" : "withoutResponse") requested=\(requestedNotify.count)/4 confirmed=\(confirmedNotify.count)/4")
    peripheral.writeValue(helloFrame, for: commandCharacteristic, type: writeType)
    helloSent = true
  }

  private func finish(code: Int32, reason: String) {
    print("finish code=\(code) reason=\(reason) requested=\(requestedNotify.count)/4 confirmed=\(confirmedNotify.count)/4 customNotify=\(customNotifyCount)")
    if let peripheral {
      manager.cancelPeripheralConnection(peripheral)
    }
    Foundation.exit(code)
  }
}

private func propertyNames(_ properties: CBCharacteristicProperties) -> String {
  var names: [String] = []
  if properties.contains(.read) { names.append("read") }
  if properties.contains(.write) { names.append("write") }
  if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
  if properties.contains(.notify) { names.append("notify") }
  if properties.contains(.indicate) { names.append("indicate") }
  if properties.contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }
  if properties.contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }
  return names.joined(separator: ",")
}

private extension Data {
  init(hex: String) {
    var bytes: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
      index = next
    }
    self.init(bytes)
  }

  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

let probe = CoreBluetoothProbe()
probe.start()
RunLoop.main.run()
