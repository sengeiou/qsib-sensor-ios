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

class AppBluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
        
    var centralManager: CBCentralManager!
    var isScanning: Bool = false
    var count: Int = 0
    
    static let BATTERY_SERVICE_UUID = CBUUID(string: "180F")
    let BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID = CBUUID(string: "2A19")
    
    static let QSIB_SENSOR_SERVICE_UUID = CBUUID(string: "000062c4-b99e-4141-9439-c4f9db977899")

    let QSS_CONTROL_UUID = CBUUID(string: "010062c4-b99e-4141-9439-c4f9db977899")
    let QSS_SIGNAL_UUID = CBUUID(string: "020062c4-b99e-4141-9439-c4f9db977899")
    let QSS_FIRMWARE_VERSION_UUID = CBUUID(string: "030062c4-b99e-4141-9439-c4f9db977899")
    let QSS_HARDWARE_VERSION_UUID = CBUUID(string: "040062c4-b99e-4141-9439-c4f9db977899")
    let QSS_ERROR_UUID = CBUUID(string: "050062c4-b99e-4141-9439-c4f9db977899")
    let QSS_NAME_UUID = CBUUID(string: "060062c4-b99e-4141-9439-c4f9db977899")
    let QSS_UUID_UUID = CBUUID(string: "070062c4-b99e-4141-9439-c4f9db977899")
    let QSS_BOOT_COUNT_UUID = CBUUID(string: "080062c4-b99e-4141-9439-c4f9db977899")

//    let CENTRAL_MANAGER_IDENTIFIER = "CENTRAL_MANAGER_IDENTIFIER"
    let CENTRAL_MANAGER_IDENTIFIER: String? = nil

    override init() {
        super.init()
        LOGGER.debug("Initializing Bluetooth Delegate ...")
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        ACTION_DISPATCH(action: InitBle(delegate: self))
    }
    
    func handleConnectOnDiscovery(_ connectOnDiscovery: Bool) {
        self.centralManagerDidUpdateState(self.centralManager)
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
            LOGGER.info("Beginning scan for QSIB Sensor ...")
            centralManager.scanForPeripherals(withServices: [AppBluetoothDelegate.QSIB_SENSOR_SERVICE_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            isScanning = true
        default:
            LOGGER.info("CBCM UNEXPECTED UNHANDLED MANAGER STATE: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let name = advertisementData["kCBAdvDataLocalName"] as? String {
            LOGGER.trace("Found QSS \(name) with RSSI \(RSSI)")
            
            ACTION_DISPATCH(action: DidDiscover(peripheral: peripheral, rssi: RSSI))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        LOGGER.debug("didConnect peripheral: \(peripheral)")
                
        ACTION_DISPATCH(action: DidConnect(peripheral: peripheral))
        peripheral.discoverServices([AppBluetoothDelegate.QSIB_SENSOR_SERVICE_UUID, AppBluetoothDelegate.BATTERY_SERVICE_UUID])
        count = 0
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        LOGGER.debug("didDisconnectPeripheral: \(peripheral) with error: \(String(describing: error))")
        
        ACTION_DISPATCH(action: DidDisconnect(peripheral: peripheral))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        LOGGER.debug("didFailToConnect peripheral: \(peripheral) with error: \(String(describing: error))")
        
        ACTION_DISPATCH(action: DidFailToConnect(peripheral: peripheral))


    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        LOGGER.debug("Discovered services \(peripheral.services!) with error: \(String(describing: error))")
        for service in peripheral.services! {
            if service.uuid == AppBluetoothDelegate.BATTERY_SERVICE_UUID {
                LOGGER.debug("Discovering services for BATTERY_SERVICE_UUID: \(AppBluetoothDelegate.BATTERY_SERVICE_UUID)")
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == AppBluetoothDelegate.QSIB_SENSOR_SERVICE_UUID {
                LOGGER.debug("Discovering services for QSIB_SENSOR_SERVICE_UUID: \(AppBluetoothDelegate.QSIB_SENSOR_SERVICE_UUID)")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            LOGGER.error("Failed to discover characteristics with \(error)")
        }
        
        LOGGER.debug("Discovered characteristics \(service.characteristics!) for \(service)")
        if service.uuid == AppBluetoothDelegate.BATTERY_SERVICE_UUID {
            for characteristic in service.characteristics! {
                if characteristic.uuid == BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID {
                    // Battery Level
                    LOGGER.trace("Subscribed to notifications for battery level characteristic");
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        } else if service.uuid == AppBluetoothDelegate.QSIB_SENSOR_SERVICE_UUID {
            for characteristic in service.characteristics! {
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
                default:
                    LOGGER.warning("Discovered unexpected QSS Characteristic: \(characteristic)")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        LOGGER.trace("Updated notification state for \(characteristic) with \(String(describing: error))")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        LOGGER.trace("Wrote value for characteristic: \(characteristic) with error: \(String(describing: error))")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID:
            LOGGER.trace("Updated BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID: \(BATTERY_SERVICE_BATTERY_LEVEL_CHARACTERISTIC_UUID)")
            ACTION_DISPATCH(action: DidUpdateValueForBattery(peripheral: peripheral, batteryLevel: UInt8(characteristic.value![0])))
        case QSS_CONTROL_UUID:
            LOGGER.trace("Updated QSS_CONTROL_UUID: \(QSS_CONTROL_UUID) :: \(characteristic.value!.hexEncodedString())")
        case QSS_SIGNAL_UUID:
            LOGGER.trace("Updated QSS_SIGNAL_UUID: \(QSS_SIGNAL_UUID) for the \(count)th time :: \(characteristic.value!)")
            count += 1
        case QSS_FIRMWARE_VERSION_UUID:
            LOGGER.trace("Updated QSS_FIRMWARE_VERSION_UUID: \(QSS_FIRMWARE_VERSION_UUID) :: \(String(describing: String(data: characteristic.value!, encoding: .utf8)))")
        case QSS_HARDWARE_VERSION_UUID:
            LOGGER.trace("Updated QSS_HARDWARE_VERSION_UUID: \(QSS_HARDWARE_VERSION_UUID) :: \(String(describing: String(data: characteristic.value!, encoding: .utf8)))")
        case QSS_ERROR_UUID:
            LOGGER.trace("Updated QSS_ERROR_UUID: \(QSS_ERROR_UUID) :: \(String(describing: String(data: characteristic.value!, encoding: .utf8)))")
        case QSS_NAME_UUID:
            LOGGER.trace("Updated QSS_NAME_UUID: \(QSS_NAME_UUID) :: \(String(describing: String(data: characteristic.value!, encoding: .utf8)))")
        case QSS_UUID_UUID:
            LOGGER.trace("Updated QSS_UUID_UUID: \(QSS_UUID_UUID) :: \(String(describing: String(data: characteristic.value!, encoding: .utf8)))")
        case QSS_BOOT_COUNT_UUID:
            LOGGER.trace("Updated QSS_BOOT_COUNT_UUID: \(QSS_BOOT_COUNT_UUID) :: \(characteristic.value!.hexEncodedString())")
        default:
            LOGGER.warning("Updated unexpected characteristic: \(characteristic)")
        }
    }
}
