//
//  AppBluetoothDelegate.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/20/20.
//

import UIKit
import CoreBluetooth
import Foundation
import Toast
import ReSwift

let BATTERY_SERVICE_UUID = CBUUID(string: "180F")
let BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID = CBUUID(string: "2A19")

let QSIB_SENSOR_SERVICE_UUID = CBUUID(string: "000062c4-b99e-4141-9439-c4f9db977899")

let QSS_CONTROL_UUID = CBUUID(string: "010062c4-b99e-4141-9439-c4f9db977899")
let QSS_SIGNAL_UUID = CBUUID(string: "020062c4-b99e-4141-9439-c4f9db977899")
let QSS_FIRMWARE_VERSION_UUID = CBUUID(string: "030062c4-b99e-4141-9439-c4f9db977899")
let QSS_HARDWARE_VERSION_UUID = CBUUID(string: "040062c4-b99e-4141-9439-c4f9db977899")
let QSS_ERROR_UUID = CBUUID(string: "050062c4-b99e-4141-9439-c4f9db977899")
let QSS_NAME_UUID = CBUUID(string: "060062c4-b99e-4141-9439-c4f9db977899")
let QSS_UUID_UUID = CBUUID(string: "070062c4-b99e-4141-9439-c4f9db977899")
let QSS_BOOT_COUNT_UUID = CBUUID(string: "080062c4-b99e-4141-9439-c4f9db977899")
let QSS_SHS_CONF_UUID = CBUUID(string: "090062c4-b99e-4141-9439-c4f9db977899")

let BIOMED_SERVICE_UUID = CBUUID(string: "FFF0")
let BIOMED_CHAR1_UUID = CBUUID(string: "FFF1")
let BIOMED_CHAR2_UUID = CBUUID(string: "FFF2")
let BIOMED_CHAR3_UUID = CBUUID(string: "FFF3")
let BIOMED_CHAR4_UUID = CBUUID(string: "FFF4")


class AppBluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    var centralManager: CBCentralManager!
    var isScanning: Bool = false
    var biomedCounter: UInt64 = 0
    var prevBiomedCounter: UInt8? = nil
    var biomedMayWrap: Bool = false

    
//    let CENTRAL_MANAGER_IDENTIFIER = "CENTRAL_MANAGER_IDENTIFIER"
    let CENTRAL_MANAGER_IDENTIFIER: String? = nil

    override init() {
        super.init()
        LOGGER.debug("Initializing Bluetooth Delegate ...")
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        QSIB_ACTION_DISPATCH(action: InitBle(delegate: self))
    }
    
    func handleConnectOnDiscovery(_ connectOnDiscovery: Bool) {
        self.centralManagerDidUpdateState(self.centralManager)
    }
    
    func setScan(doScan: Bool) {
        if doScan {
            LOGGER.info("Beginning scan for QSIB Sensor ...")
            centralManager.scanForPeripherals(withServices: [QSIB_SENSOR_SERVICE_UUID, BIOMED_SERVICE_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            isScanning = true
        } else {
            LOGGER.info("Stopping scan for QSIB Sensor ...")
            centralManager.stopScan()
            isScanning = false
        }
    }
        
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            LOGGER.info("CoreBluetooth CentralManager State = unknown")
        case .resetting:
            LOGGER.info("CoreBluetooth CentralManager State = resetting")
        case .unsupported:
            LOGGER.info("CoreBluetooth CentralManager State = unsupported")
        case .unauthorized:
            LOGGER.info("CoreBluetooth CentralManager State = unauthorized")
        case .poweredOff:
            LOGGER.info("CoreBluetooth CentralManager State = poweredOff")
            isScanning = false
        case .poweredOn:
            LOGGER.info("CoreBluetooth CentralManager State = poweredOn")
            setScan(doScan: true)
        default:
            LOGGER.info("CBCM UNEXPECTED UNHANDLED MANAGER STATE: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let name = advertisementData["kCBAdvDataLocalName"] as? String {
            LOGGER.trace("Found QSS \(name) with RSSI \(RSSI)")
            
            QSIB_ACTION_DISPATCH(action: DidDiscover(peripheral: peripheral, rssi: RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        LOGGER.debug("didConnect peripheral: \(peripheral)")
                
        QSIB_ACTION_DISPATCH(action: DidConnect(peripheral: peripheral))
        peripheral.discoverServices([QSIB_SENSOR_SERVICE_UUID, BIOMED_SERVICE_UUID, BATTERY_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        LOGGER.debug("didDisconnectPeripheral: \(peripheral) with: \(String(describing: error))")
        
        QSIB_ACTION_DISPATCH(action: DidDisconnect(peripheral: peripheral))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        LOGGER.debug("didFailToConnect peripheral: \(peripheral) with: \(String(describing: error))")
        
        QSIB_ACTION_DISPATCH(action: DidFailToConnect(peripheral: peripheral))
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        LOGGER.debug("Discovered services \(peripheral.services!) with: \(String(describing: error))")
        for service in peripheral.services! {
            if service.uuid == BATTERY_SERVICE_UUID {
                LOGGER.debug("Discovering services for BATTERY_SERVICE_UUID: \(BATTERY_SERVICE_UUID)")
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == QSIB_SENSOR_SERVICE_UUID {
                LOGGER.debug("Discovering services for QSIB_SENSOR_SERVICE_UUID: \(QSIB_SENSOR_SERVICE_UUID)")
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == BIOMED_SERVICE_UUID {
                LOGGER.debug("Discovering services for BIOMED_SERVICE_UUID: \(BIOMED_SERVICE_UUID)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            LOGGER.error("Failed to discover characteristics with \(error)")
        }
        
        LOGGER.debug("Discovered characteristics \(service.characteristics!) for \(service)")
        if service.uuid == BATTERY_SERVICE_UUID {
            for characteristic in service.characteristics! {
                if characteristic.uuid == BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID {
                    // Battery Level
                    LOGGER.trace("Subscribed to notifications for battery level characteristic");
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        } else if service.uuid == QSIB_SENSOR_SERVICE_UUID {
            for characteristic in service.characteristics! {
                QSIB_ACTION_DISPATCH(action: DidDiscoverCharacteristic(peripheral: peripheral, characteristic: characteristic))
                switch characteristic.uuid {
                case QSS_CONTROL_UUID:
                    LOGGER.trace("Discovered QSS_CONTROL_UUID: \(QSS_CONTROL_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_SIGNAL_UUID:
                    LOGGER.trace("Discovered QSS_SIGNAL_UUID: \(QSS_SIGNAL_UUID)")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case QSS_FIRMWARE_VERSION_UUID:
                    LOGGER.trace("Discovered QSS_FIRMWARE_VERSION_UUID: \(QSS_FIRMWARE_VERSION_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_HARDWARE_VERSION_UUID:
                    LOGGER.trace("Discovered QSS_HARDWARE_VERSION_UUID: \(QSS_HARDWARE_VERSION_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_ERROR_UUID:
                    LOGGER.trace("Discovered QSS_ERROR_UUID: \(QSS_ERROR_UUID)")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case QSS_NAME_UUID:
                    LOGGER.trace("Discovered QSS_NAME_UUID: \(QSS_NAME_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_UUID_UUID:
                    LOGGER.trace("Discovered QSS_UUID_UUID: \(QSS_UUID_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_BOOT_COUNT_UUID:
                    LOGGER.trace("Discovered QSS_BOOT_COUNT_UUID: \(QSS_BOOT_COUNT_UUID)")
                    peripheral.readValue(for: characteristic)
                case QSS_SHS_CONF_UUID:
                    LOGGER.trace("Discovered QSS_SHS_CONF_UUID: \(QSS_SHS_CONF_UUID)")
                    peripheral.readValue(for: characteristic)
                default:
                    LOGGER.warning("Discovered unexpected QSS Characteristic: \(characteristic)")
                }
            }
        } else if service.uuid == BIOMED_SERVICE_UUID {
            for characteristic in service.characteristics! {
                QSIB_ACTION_DISPATCH(action: DidDiscoverCharacteristic(peripheral: peripheral, characteristic: characteristic))
                switch characteristic.uuid {
                case BIOMED_CHAR1_UUID:
                    LOGGER.trace("Discovered BIOMED_CHAR1_UUID: \(BIOMED_CHAR1_UUID)")
                    peripheral.readValue(for: characteristic)
                case BIOMED_CHAR2_UUID:
                    LOGGER.trace("Discovered BIOMED_CHAR2_UUID: \(BIOMED_CHAR2_UUID)")
                    peripheral.readValue(for: characteristic)
                case BIOMED_CHAR3_UUID:
                    LOGGER.trace("Discovered BIOMED_CHAR3_UUID: \(BIOMED_CHAR3_UUID)")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case BIOMED_CHAR4_UUID:
                    LOGGER.trace("Discovered BIOMED_CHAR4_UUID: \(BIOMED_CHAR4_UUID)")
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                default:
                    LOGGER.warning("Discovered unexpected BIOMED Characteristic: \(characteristic)")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        LOGGER.trace("Updated notification state for \(characteristic) with \(String(describing: error))")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        LOGGER.trace("Wrote value for characteristic: \(characteristic) with: \(String(describing: error))")
        if let error = error {
            LOGGER.error("Encountered error writing to characteristic: \(error)")
        } else {
            peripheral.readValue(for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID:
            LOGGER.trace("Updated BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID: \(BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForBattery(peripheral: peripheral, batteryLevel: Int(characteristic.value![0])))
        case QSS_CONTROL_UUID:
            LOGGER.trace("Updated QSS_CONTROL_UUID: \(QSS_CONTROL_UUID) :: \(characteristic.value!.hexEncodedString())")
        case QSS_SIGNAL_UUID:
            if let value = characteristic.value {
                QSIB_ACTION_DISPATCH(action: DidUpdateValueForSignal(peripheral: peripheral, signal: value))
            }
        case QSS_FIRMWARE_VERSION_UUID:
            let firmwareVersion = String(data: characteristic.value!, encoding: .utf8) ?? "invalid"
            LOGGER.trace("Updated QSS_FIRMWARE_VERSION_UUID: \(QSS_FIRMWARE_VERSION_UUID) :: \(firmwareVersion)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForFirmwareVersion(peripheral: peripheral, value: firmwareVersion))
        case QSS_HARDWARE_VERSION_UUID:
            let hardwareVersion = String(data: characteristic.value!, encoding: .utf8) ?? "invalid"
            LOGGER.trace("Updated QSS_HARDWARE_VERSION_UUID: \(QSS_HARDWARE_VERSION_UUID) :: \(hardwareVersion)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForHardwareVersion(peripheral: peripheral, value: hardwareVersion))
        case QSS_ERROR_UUID:
            let error = String(data: characteristic.value!, encoding: .utf8) ?? "invalid"
            LOGGER.trace("Updated QSS_ERROR_UUID: \(QSS_ERROR_UUID) :: \(error)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForError(peripheral: peripheral, value: error))
        case QSS_NAME_UUID:
            let name = String(data: characteristic.value!, encoding: .utf8) ?? "invalid"
            LOGGER.trace("Updated QSS_NAME_UUID: \(QSS_NAME_UUID) :: \(name)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForName(peripheral: peripheral, value: name))
        case QSS_UUID_UUID:
            let uniqueIdentifier = String(data: characteristic.value!, encoding: .utf8) ?? "invalid"
            LOGGER.trace("Updated QSS_UUID_UUID: \(QSS_UUID_UUID) :: \(uniqueIdentifier)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForUniqueIdentifier(peripheral: peripheral, value: uniqueIdentifier))
        case QSS_BOOT_COUNT_UUID:
            var beforeOrderBootCount: UInt32 = 0
            if let data = characteristic.value {
                beforeOrderBootCount = data.withUnsafeBytes {
                    $0.load(as: UInt32.self)
                }
            }
            let bootCount = Int(beforeOrderBootCount)
            LOGGER.trace("Updated QSS_BOOT_COUNT_UUID: \(QSS_BOOT_COUNT_UUID) :: \(bootCount)")
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForBootCount(peripheral: peripheral, value: bootCount))
        case QSS_SHS_CONF_UUID:
            guard let data = characteristic.value, data.count == 8 else {
                return
            }
            LOGGER.trace("Updated QSS_SHS_CONF_UUID: \(QSS_SHS_CONF_UUID) :: \(data.hexEncodedString())")
            let persistedConfig = PersistedConfig()
            persistedConfig.f0 = data[0..<4].withUnsafeBytes { $0.load(as: Float.self) }
            persistedConfig.f1 = data[4..<8].withUnsafeBytes { $0.load(as: Float.self) }
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForPersistedConfig(peripheral: peripheral, value: persistedConfig))
        case BIOMED_CHAR1_UUID:
            LOGGER.trace("Updated BIOMED_CHAR1_UUID: \(BIOMED_CHAR1_UUID)")
            guard let value = characteristic.value else {
                LOGGER.error("Invalid characteristic update for BIOMED_CHAR1_UUID: \(characteristic)")
                return
            }
            LOGGER.trace("Updated BIOMED_CHAR1_UUID with \(value.hexEncodedString())")
        case BIOMED_CHAR2_UUID:
            LOGGER.trace("Updated BIOMED_CHAR2_UUID: \(BIOMED_CHAR2_UUID)")
            guard let value = characteristic.value else {
                LOGGER.error("Invalid characteristic update for BIOMED_CHAR2_UUID: \(characteristic)")
                return
            }
            LOGGER.trace("Updated BIOMED_CHAR2_UUID with \(value.hexEncodedString())")
        case BIOMED_CHAR3_UUID:
            LOGGER.trace("Updated BIOMED_CHAR3_UUID: \(BIOMED_CHAR3_UUID)")
            guard let value = characteristic.value else {
                LOGGER.error("Invalid characteristic update for BIOMED_CHAR3_UUID: \(characteristic)")
                return
            }
            LOGGER.trace("Updated BIOMED_CHAR3_UUID with \(value.hexEncodedString())")
            
            let msbMv = Int(value[0])
            let lsbMv = Int(value[1])
            let batteryMv = Int((msbMv << 8) + lsbMv) * 10
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForBattery(peripheral: peripheral, batteryLevel: batteryMv))
        case BIOMED_CHAR4_UUID:
            LOGGER.trace("Updated BIOMED_CHAR4_UUID: \(BIOMED_CHAR4_UUID)")
            guard let value = characteristic.value else {
                LOGGER.warning("Invalid characteristic update for BIOMED_CHAR4_UUID: \(characteristic)")
                return
            }
            LOGGER.trace("Updated BIOMED_CHAR4_UUID with \(value.hexEncodedString())")
            
            let counter = UInt8(value[0])
            let messageSize = Int(value[1])
            guard messageSize == 100 && value.count == 202 else {
                LOGGER.error("Invalid BIOMED_CHAR4_UUID value. Expected payload of 202 bytes and 100 samples")
                return
            }
            
            if let prevCounter = prevBiomedCounter {
                if prevCounter > 245 && counter < 10 {
                    biomedCounter += UInt64((255 - prevCounter) + counter)
                } else {
                    biomedCounter += UInt64(counter - prevCounter)
                }
            } else {
                biomedCounter = UInt64(counter)
            }
            prevBiomedCounter = counter
            
            
            let signalPayloadBytes = 8 + (2 * 2 * 100)
            var data = Data(repeating: 0, count: signalPayloadBytes)
            data[0] = UInt8(signalPayloadBytes & 0xFF)
            data[1] = UInt8((signalPayloadBytes >> 8) & 0xFF)
            data[2] = 2
            data[3] = (UInt8(2) << 4) | (UInt8(0))
            data[4] = UInt8(biomedCounter & 0xff)
            data[5] = UInt8((biomedCounter >> 8) & 0xff)
            data[6] = UInt8((biomedCounter >> 16) & 0xff)
            data[7] = UInt8((biomedCounter >> 24) & 0xff)

            
            data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
                let offsetPtr = ptr.baseAddress!.bindMemory(to: UInt8.self, capacity: 208) + 8
                value.copyBytes(to: offsetPtr, from: 2..<202)
            }
            
            QSIB_ACTION_DISPATCH(action: DidUpdateValueForSignal(peripheral: peripheral, signal: data))
        default:
            LOGGER.warning("Updated unexpected characteristic: \(characteristic)")
        }
    }
}

extension CBUUID {
    var UUIDValue: UUID? {
        get {
            var data = self.data
            if self.data.count < MemoryLayout<uuid_t>.size {
                data.append(Data(repeating: 0, count: MemoryLayout<uuid_t>.size - self.data.count))
            }
            return data.withUnsafeBytes {
                (pointer: UnsafeRawBufferPointer) -> UUID in
                let uuid = pointer.load(as: uuid_t.self)
                return UUID(uuid: uuid)
            }
        }
    }
}
