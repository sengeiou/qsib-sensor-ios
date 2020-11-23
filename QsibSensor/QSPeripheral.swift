//
//  QSPeripheral.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/23/20.
//

import Foundation
import CoreBluetooth
import Toast

struct QSPeripheral {
    var cbp: CBPeripheral!
    var characteristics: [UUID: CBCharacteristic]!
    var name: String!
    var rssi: Int!
    var ts: Date!
    
    var projectMode: String?
    var signalHz: Int?
    var signalChannels: Int?
    
    var firmwareVersion: String?
    var hardwareVersion: String?
    var error: String?
    var uniqueIdentifier: String?
    var bootCount: Int?
    
    public init(peripheral: CBPeripheral, rssi: NSNumber) {
        self.set(peripheral: peripheral, rssi: rssi)
        self.characteristics = [:]
        self.ts = Date()
    }
    
    public func id() -> UUID {
        return cbp.identifier
    }
    
    public mutating func set(peripheral: CBPeripheral) {
        self.cbp = peripheral
        self.name = peripheral.name ?? "Unknown"
        self.ts = Date()
    }
    
    public mutating func set(peripheral: CBPeripheral, rssi: NSNumber) {
        self.rssi = Int(truncating: rssi)
        self.projectMode = "Multiwavelength PPG v1"
        self.signalHz = 32
        self.signalChannels = 6
        set(peripheral: peripheral)
    }
    
    public mutating func add(characteristic: CBCharacteristic) {
        self.characteristics[UUID(uuidString: characteristic.uuid.uuidString)!] = characteristic
        self.ts = Date()
    }
    
    public func displayRssi() -> Optional<Int> {
        if Date().timeIntervalSince(ts) > 10 {
            return nil
        }
        return rssi
    }

    public func writeControl(data: Data) {
        writeDataToChar(cbuuid: QSS_CONTROL_UUID, data: data)
    }
    
    public func writeHardwareVersion(value: String) {
        writeStringToChar(cbuuid: QSS_HARDWARE_VERSION_UUID, value: value)
    }
    
    public func writeName(value: String) {
        writeStringToChar(cbuuid: QSS_NAME_UUID, value: value)
    }

    public func writeUniqueIdentifier(value: String) {
        writeStringToChar(cbuuid: QSS_UUID_UUID, value: value)
    }
    
    private func writeStringToChar(cbuuid: CBUUID, value: String) {
        writeDataToChar(cbuuid: cbuuid, data: Data(value.utf8))
    }
    
    private func writeDataToChar(cbuuid: CBUUID, data: Data) {
        if let characteristic = self.characteristics[UUID(uuidString: cbuuid.uuidString)!] {
            self.cbp.writeValue(data, for: characteristic, type: .withResponse)
        } else {
            ACTION_DISPATCH(action: AppendToast(message: ToastMessage(message: "Cannot update characteristic", duration: TimeInterval(2), position: .center, title: "Internal BLE Error", image: nil, style: ToastStyle(), completion: nil)))
        }
    }

}
