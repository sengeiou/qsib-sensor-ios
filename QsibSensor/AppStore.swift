//
//  AppStore.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/20/20.
//

import CoreBluetooth
import Foundation
import UIKit
import ReSwift
import Toast


struct AppState: StateType {
    var ble: AppBluetoothDelegate? = nil
    var peripherals: [UUID: QSPeripheral] = [:]
    var toastQueue: [ToastMessage] = []
    var activePeripheral: UUID?
}

struct ToastMessage {
    let id = UUID()
    var message: String? = nil
    var duration: TimeInterval = TimeInterval(3)
    var position: ToastPosition = .top
    var title: String? = nil
    var image: UIImage? = nil
    var style: ToastStyle = .init()
    var completion: ((Bool) -> Void)? = nil
}

struct InitBle: Action {
    let delegate: AppBluetoothDelegate
}

struct DidDiscover: Action {
    let peripheral: CBPeripheral
    let rssi: NSNumber
}

struct RequestConnect: Action {
    let peripheral: CBPeripheral
}

struct DidConnect: Action {
    let peripheral: CBPeripheral
}

struct RequestDisconnect: Action {
    let peripheral: CBPeripheral
}

struct DidDisconnect: Action {
    let peripheral: CBPeripheral
}

struct DidFailToConnect: Action {
    let peripheral: CBPeripheral
}

struct DidDiscoverCharacteristic: Action {
    let peripheral: CBPeripheral
    let characteristic: CBCharacteristic
}

struct DidUpdateValueForBattery: Action {
    let peripheral: CBPeripheral
    let batteryLevel: UInt8
}

struct DidUpdateValueForFirmwareVersion: Action {
    let peripheral: CBPeripheral
    let value: String
}

struct DidUpdateValueForHardwareVersion: Action {
    let peripheral: CBPeripheral
    let value: String
}

struct DidUpdateValueForError: Action {
    let peripheral: CBPeripheral
    let value: String
}

struct DidUpdateValueForName: Action {
    let peripheral: CBPeripheral
    let value: String
}

struct DidUpdateValueForUniqueIdentifier: Action {
    let peripheral: CBPeripheral
    let value: String
}

struct DidUpdateValueForBootCount: Action {
    let peripheral: CBPeripheral
    let value: Int
}

struct WriteControl: Action {
    let peripheral: CBPeripheral
    let control: Data
}

struct WriteHardwareVersion: Action {
    let peripheral: CBPeripheral
    let hardwareVersion: String
}

struct WriteName: Action {
    let peripheral: CBPeripheral
    let name: String
}

struct WriteUniqueIdentifier: Action {
    let peripheral: CBPeripheral
    let uniqueIdentifier: String
}

struct AppendToast: Action {
    let message: ToastMessage
}

struct ProcessToast: Action {}

struct Tick: Action {}

func appReducer(action: Action, state: AppState?) -> AppState {
    var state = state ?? AppState()
    
    switch action {
    case _ as ReSwiftInit:
        LOGGER.info("Initializing ReSwift")
    case let action as InitBle:
        state.ble = action.delegate
    case let action as DidDiscover:
        let peripheral = getPeripheral(&state, action.peripheral, rssi: action.rssi)
        peripheral.cbp.delegate = state.ble
    case let action as DidDiscoverCharacteristic:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.add(characteristic: action.characteristic)
        state.peripherals[peripheral.id()] = peripheral
    case let action as RequestConnect:
        state.ble?.centralManager.connect(action.peripheral, options: nil)
        state.activePeripheral = action.peripheral.identifier
    case let action as DidConnect:
        let _ = getPeripheral(&state, action.peripheral)
    case let action as RequestDisconnect:
        state.ble?.centralManager.cancelPeripheralConnection(action.peripheral)
    case let action as DidDisconnect:
        let _ = getPeripheral(&state, action.peripheral)
    case let action as DidFailToConnect:
        let _ = getPeripheral(&state, action.peripheral)
    case let action as DidUpdateValueForBattery:
        let peripheral = getPeripheral(&state, action.peripheral)
        LOGGER.debug("\(peripheral.name ?? "Unknown") has battery level \(action.batteryLevel)")
    case let action as DidUpdateValueForFirmwareVersion:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.firmwareVersion = action.value
        state.peripherals[peripheral.id()] = peripheral
    case let action as DidUpdateValueForHardwareVersion:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.hardwareVersion = action.value
        state.peripherals[peripheral.id()] = peripheral
    case let action as DidUpdateValueForError:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.error = action.value
        state.peripherals[peripheral.id()] = peripheral
        if !action.value.isEmpty {
            LOGGER.warning("Encountered error for \(peripheral)")
        }
    case let action as DidUpdateValueForName:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.name = action.value
        state.peripherals[peripheral.id()] = peripheral
    case let action as DidUpdateValueForUniqueIdentifier:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.uniqueIdentifier = action.value
        state.peripherals[peripheral.id()] = peripheral
    case let action as DidUpdateValueForBootCount:
        var peripheral = getPeripheral(&state, action.peripheral)
        peripheral.bootCount = action.value
        state.peripherals[peripheral.id()] = peripheral
    case let action as WriteControl:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.writeControl(data: action.control)
    case let action as WriteHardwareVersion:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.writeHardwareVersion(value: action.hardwareVersion)
    case let action as WriteName:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.writeName(value: action.name)
    case let action as WriteUniqueIdentifier:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.writeUniqueIdentifier(value: action.uniqueIdentifier)
    case let action as AppendToast:
        state.toastQueue.append(action.message)
    case _ as ProcessToast:
        state.toastQueue.removeFirst()
    case _ as Tick:
        break
    default:
        LOGGER.warning("Skipped processing \(action)")
    }
    
    return state
}

let STORE = Store<AppState>(
    reducer: appReducer,
    state: nil
)

func ACTION_DISPATCH(action: Action) {
    DISPATCH.execute {
        STORE.dispatch(action)
    }
}

func TICK() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        ACTION_DISPATCH(action: Tick())
        TICK()
    }
}

func getPeripheral(_ state: inout AppState, _ peripheral: CBPeripheral) -> QSPeripheral {
    if var qsp = state.peripherals[peripheral.identifier] {
        qsp.set(peripheral: peripheral)
        state.peripherals[peripheral.identifier] = qsp
        return qsp
    } else {
        fatalError("Encountered unexpected CBPeripheral without discovering advertisement")
    }
}

func getPeripheral(_ state: inout AppState, _ peripheral: CBPeripheral, rssi: NSNumber) -> QSPeripheral {
    if var qsp = state.peripherals[peripheral.identifier] {
        qsp.set(peripheral: peripheral, rssi: rssi)
        state.peripherals[peripheral.identifier] = qsp
        return qsp
    } else {
        let qsp = QSPeripheral(peripheral: peripheral, rssi: rssi)
        state.peripherals[qsp.id()] = qsp
        return qsp
    }
}
