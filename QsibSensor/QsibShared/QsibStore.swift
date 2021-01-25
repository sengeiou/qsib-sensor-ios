//
//  AppStore.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/20/20.
//

import CoreBluetooth
import Foundation
import ReSwift


public struct QsibState: StateType {
    var ble: AppBluetoothDelegate? = nil
    var peripherals: [UUID: QSPeripheral] = [:]
    var activePeripheral: UUID?
}

public struct InitBle: Action {
    let delegate: AppBluetoothDelegate
}

public struct DidDiscover: Action {
    let peripheral: CBPeripheral
    let rssi: NSNumber
}

public struct RequestConnect: Action {
    let peripheral: CBPeripheral
}

public struct DidConnect: Action {
    let peripheral: CBPeripheral
}

public struct RequestDisconnect: Action {
    let peripheral: CBPeripheral
}

public struct DidDisconnect: Action {
    let peripheral: CBPeripheral
}

public struct DidFailToConnect: Action {
    let peripheral: CBPeripheral
}

public struct DidDiscoverCharacteristic: Action {
    let peripheral: CBPeripheral
    let characteristic: CBCharacteristic
}

public struct DidUpdateValueForBiomedChar1: Action {
    let peripheral: CBPeripheral
    let data: Data
}

public struct DidUpdateValueForBattery: Action {
    let peripheral: CBPeripheral
    let batteryLevel: Int
}

public struct DidUpdateValueForSignal: Action {
    let peripheral: CBPeripheral
    let signal: Data
}

public struct DidUpdateValueForFirmwareVersion: Action {
    let peripheral: CBPeripheral
    let value: String
}

public struct DidUpdateValueForHardwareVersion: Action {
    let peripheral: CBPeripheral
    let value: String
}

public struct DidUpdateValueForError: Action {
    let peripheral: CBPeripheral
    let value: String
}

public struct DidUpdateValueForName: Action {
    let peripheral: CBPeripheral
    let value: String
}

public struct DidUpdateValueForUniqueIdentifier: Action {
    let peripheral: CBPeripheral
    let value: String
}

public struct DidUpdateValueForBootCount: Action {
    let peripheral: CBPeripheral
    let value: Int
}

public struct DidUpdateValueForPersistedConfig: Action {
    let peripheral: CBPeripheral
    let value: PersistedConfig
}

public struct WriteControl: Action {
    let peripheral: CBPeripheral
    let control: Data
}

public struct WriteHardwareVersion: Action {
    let peripheral: CBPeripheral
    let hardwareVersion: String
}

public struct WriteName: Action {
    let peripheral: CBPeripheral
    let name: String
}

public struct WriteUniqueIdentifier: Action {
    let peripheral: CBPeripheral
    let uniqueIdentifier: String
}

public struct WriteCalibrationFactor0: Action {
    let peripheral: CBPeripheral
    let f0: Float
}

public struct WriteCalibrationFactor1: Action {
    let peripheral: CBPeripheral
    let f1: Float
}

public struct UpdateProjectMode: Action {
    let peripheral: CBPeripheral
    let projectMode: String
}

public struct UpdateProjectDefaultMode: Action {
    let peripheral: CBPeripheral
    let projectMode: String
    let defaultMode: String
}

public struct UpdateSignalChannels: Action {
    let peripheral: CBPeripheral
    let channels: Int
}

public struct UpdateSignalHz: Action {
    let peripheral: CBPeripheral
    let hz: Int
}

public struct StartMeasurement: Action {
    let peripheral: CBPeripheral
}

public struct ResumeMeasurement: Action {
    let peripheral: CBPeripheral
}

public struct PauseMeasurement: Action {
    let peripheral: CBPeripheral
}

public struct StopMeasurement: Action {
    let peripheral: CBPeripheral
}

public struct TurnOffSensor: Action {
    let peripheral: CBPeripheral
}

public struct QsibTick: Action {}

public struct IssueControlWriteFor: Action {
    let peripheral: CBPeripheral
    let projectMode: String
}

public struct SetScan: Action {
    let doScan: Bool
}

func qsibReducer(action: Action, state: QsibState?) -> QsibState {
    var state = state ?? QsibState()
    
    switch action {
    case _ as ReSwiftInit:
        LOGGER.info("Initializing ReSwift")
    case let action as InitBle:
        state.ble = action.delegate
    case let action as DidDiscover:
        let peripheral = getPeripheral(&state, action.peripheral, rssi: action.rssi)
        peripheral.cbp.delegate = state.ble
    case let action as DidDiscoverCharacteristic:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.add(characteristic: action.characteristic)
        save(&state, peripheral)
    case let action as RequestConnect:
        if action.peripheral.state != .connected && action.peripheral.state != .connecting {
            state.ble?.centralManager.connect(action.peripheral, options: nil)
            state.activePeripheral = action.peripheral.identifier
        }
    case let action as DidConnect:
        let _ = getPeripheral(&state, action.peripheral)
    case let action as RequestDisconnect:
        state.ble?.centralManager.cancelPeripheralConnection(action.peripheral)
    case let action as DidDisconnect:
        let _ = getPeripheral(&state, action.peripheral)
        QSIB_ACTION_DISPATCH(action: StopMeasurement(peripheral: action.peripheral))
    case let action as DidFailToConnect:
        let _ = getPeripheral(&state, action.peripheral)
    case let action as DidUpdateValueForBiomedChar1:
        // Override mode info on biomedchar1 remote configs always
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.projectMode = OXIMETER_V0
        let state = peripheral.getOrDefaultProject()
        if action.data.count < 9 {
            break
        }
        let data = action.data
        let modeInfo = state.ox_v0_modes[state.defaultMode!]!
        modeInfo.biomed_id = Int(data[0])
        modeInfo.fifo_config = Int(data[1])
        modeInfo.mode_config = Int(data[2])
        modeInfo.spo2_config = Int(data[3])
        modeInfo.led_amp = Int((UInt32(data[4]) << 16) | (UInt32(data[5]) << 8) | UInt32(data[6]))
        modeInfo.multi_led = Int((UInt16(data[7]) << 8) | UInt16(data[8]))
        state.ox_v0_modes[state.defaultMode!] = peripheral.updateModeStateForOximeterV0(modeState: modeInfo)
        peripheral.save()
    case let action as DidUpdateValueForBattery:
        let peripheral = getPeripheral(&state, action.peripheral)
        LOGGER.trace("\(peripheral.name()) has battery level \(action.batteryLevel)")
        peripheral.batteryLevel = action.batteryLevel
        save(&state, peripheral)
    case let action as DidUpdateValueForSignal:
        let peripheral = getPeripheral(&state, action.peripheral)
        EVENT_LOOP_GROUP.next().execute {
            guard let measurement = peripheral.activeMeasurement else {
                LOGGER.trace("No active measurement for \(peripheral.id())")
                return
            }
                        
            guard let _ = measurement.addPayload(data: action.signal) else {
                LOGGER.error("Failed to add payload to \(measurement)")
                return
            }
        }
    case let action as DidUpdateValueForFirmwareVersion:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.firmwareVersion = action.value
        save(&state, peripheral)
    case let action as DidUpdateValueForHardwareVersion:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.hardwareVersion = action.value
        save(&state, peripheral)
    case let action as DidUpdateValueForError:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.error = action.value
        save(&state, peripheral)
        if !action.value.isEmpty {
            LOGGER.warning("Encountered error for \(peripheral)")
        }
    case let action as DidUpdateValueForName:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.persistedName = action.value
        save(&state, peripheral)
    case let action as DidUpdateValueForUniqueIdentifier:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.uniqueIdentifier = action.value
        save(&state, peripheral)
    case let action as DidUpdateValueForBootCount:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.bootCount = action.value
        save(&state, peripheral)
    case let action as DidUpdateValueForPersistedConfig:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.persistedConfig = action.value
        save(&state, peripheral)
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
    case let action as WriteCalibrationFactor0:
        let peripheral = getPeripheral(&state, action.peripheral)
        if nil == peripheral.persistedConfig {
            peripheral.persistedConfig = PersistedConfig()
        }
        peripheral.persistedConfig!.f0 = action.f0
        peripheral.writePersistedConfig()
    case let action as WriteCalibrationFactor1:
        let peripheral = getPeripheral(&state, action.peripheral)
        if nil == peripheral.persistedConfig {
            peripheral.persistedConfig = PersistedConfig()
        }
        peripheral.persistedConfig!.f1 = action.f1
        peripheral.writePersistedConfig()
    case let action as UpdateProjectMode:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.projectMode = action.projectMode
        switch peripheral.projectMode ?? "" {
        case MWV_PPG_V2:
            if peripheral.signalHz == nil {
                peripheral.signalHz = 1
            }
            if peripheral.signalChannels == nil {
                peripheral.signalChannels = 6
            }
        case SHUNT_MONITOR_V1:
            if peripheral.signalHz == nil {
                peripheral.signalHz = 512
            }
            if peripheral.signalChannels == nil {
                peripheral.signalChannels = 5
            }
        case SKIN_HYDRATION_SENSOR_V2:
            peripheral.signalHz = 256
            peripheral.signalChannels = 4
        case OXIMETER_V0:
            if peripheral.signalHz == nil {
                peripheral.signalHz = 1
            }
            
            if peripheral.signalChannels == nil {
                peripheral.signalChannels = 2
            }
        default:
            fatalError("Not setting or checking project defaults for \(String(describing: peripheral.projectMode))")
        }
        save(&state, peripheral)
    case let action as UpdateProjectDefaultMode:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.projectMode = action.projectMode
        let projectState = peripheral.getOrDefaultProject()
        projectState.defaultMode = action.defaultMode
        save(&state, peripheral)
    case let action as UpdateSignalHz:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.signalHz = action.hz
        save(&state, peripheral)
    case let action as UpdateSignalChannels:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.signalChannels = action.channels
        save(&state, peripheral)
    case let action as StartMeasurement:
        let peripheral = getPeripheral(&state, action.peripheral)
        if let numChannels = peripheral.signalChannels {
            var holdInRam: Bool = false
            switch peripheral.projectMode ?? "" {
            case SHUNT_MONITOR_V1, MWV_PPG_V2, OXIMETER_V0:
                holdInRam = false
            case SKIN_HYDRATION_SENSOR_V2:
                holdInRam = true
            default:
                LOGGER.warning("\(String(describing: peripheral.projectMode)) doesn't specify how to transition between data sets.")
            }
            peripheral.activeMeasurement = QSMeasurement(signalChannels: UInt8(numChannels), holdInRam: holdInRam)
            peripheral.activeMeasurement?.state = .running
            LOGGER.debug("Starting measurement ...")
            startNewDataSet(for: peripheral)
            peripheral.start()
            save(&state, peripheral)
        } else {
            LOGGER.error("Number of channels not set. Cannot start measurement")
        }
    case let action as ResumeMeasurement:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.activeMeasurement?.state = .running
        LOGGER.debug("Resuming measurement ...")
        startNewDataSet(for: peripheral)
        peripheral.resume()
    case let action as PauseMeasurement:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.activeMeasurement?.state = .paused
        startNewDataSet(for: peripheral)
        peripheral.pause()
    case let action as StopMeasurement:
        let peripheral = getPeripheral(&state, action.peripheral)
        if let activeMeasurement = peripheral.activeMeasurement {
            peripheral.activeMeasurement?.state = .ended
            peripheral.finalizedMeasurements.append(activeMeasurement)
            peripheral.activeMeasurement = nil
            peripheral.pause()
            save(&state, peripheral)
        } else {
            LOGGER.trace("No active measurement to stop")
        }
    case let action as TurnOffSensor:
        let peripheral = getPeripheral(&state, action.peripheral)
        peripheral.activeMeasurement?.state = .running
        peripheral.rssi = -100
        peripheral.turnOff()
    case let action as IssueControlWriteFor:
        let peripheral = getPeripheral(&state, action.peripheral)
        
        switch peripheral.projectMode ?? "" {
        case OXIMETER_V0:
            peripheral.writeProjectControlForOximeterV0(skipChar2: true)
        default:
            peripheral.pause()
            peripheral.start()
        }
        
        startNewDataSet(for: peripheral)
    case let action as SetScan:
        state.ble!.setScan(doScan: action.doScan)
    case _ as QsibTick:
        break
    default:
        LOGGER.warning("Skipped processing \(action)")
    }
    
    // Allow someone to add logic to run for this aciton after the state has been updated
    STORE_CALLBACK.fire(&state, action)
    
    return state
}

public let QSIB_STORE = Store<QsibState>(
    reducer: qsibReducer,
    state: nil
)

public func QSIB_ACTION_DISPATCH(action: Action) {
    DISPATCH.execute {
        QSIB_STORE.dispatch(action)
    }
}

public func QSIB_TICK() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        QSIB_ACTION_DISPATCH(action: QsibTick())
        QSIB_TICK()
    }
}

func getPeripheral(_ state: inout QsibState, _ peripheral: CBPeripheral) -> QSPeripheral {
    if let qsp = state.peripherals[peripheral.identifier] {
        qsp.set(peripheral: peripheral)
        state.peripherals[peripheral.identifier] = qsp
        return qsp
    } else {
        fatalError("Encountered unexpected CBPeripheral without discovering advertisement")
    }
}

func getPeripheral(_ state: inout QsibState, _ peripheral: CBPeripheral, rssi: NSNumber) -> QSPeripheral {
    if let qsp = state.peripherals[peripheral.identifier] {
        qsp.set(peripheral: peripheral, rssi: rssi)
        qsp.ts = Date()
        return qsp
    } else {
        let qsp = QSPeripheral(peripheral: peripheral, rssi: rssi)
        state.peripherals[qsp.id()] = qsp
        qsp.ts = Date()
        return qsp
    }
}

func save(_ state: inout QsibState, _ peripheral: QSPeripheral) {
    LOGGER.trace("Saving \(peripheral.id()) ...")
    peripheral.save()
}

func startNewDataSet(for peripheral: QSPeripheral) {
    switch peripheral.projectMode ?? "" {
    case MWV_PPG_V2:
        let state = peripheral.getOrDefaultProject()
        let currentMode: String = state.defaultMode!
        let wtime = (2.78 * Float(1 + (state.mwv_ppg_v2_modes[currentMode]?.wcycles ?? 0)))
        let hz = 1000.0 / wtime
        peripheral.activeMeasurement?.startNewDataSet(hz: hz)
    case OXIMETER_V0:
        let state = peripheral.getOrDefaultProject()
        let currentMode: String = state.defaultMode!
        let modeInfo = state.ox_v0_modes[currentMode]!
        let hz = modeInfo.effective_sample_hz!
        peripheral.activeMeasurement?.startNewDataSet(hz: hz)
    case SKIN_HYDRATION_SENSOR_V2, SHUNT_MONITOR_V1:
        let _ = peripheral.getOrDefaultProject()
        if let hz = peripheral.signalHz {
            peripheral.activeMeasurement?.startNewDataSet(hz: Float(hz))
        } else {
            peripheral.signalHz = 1
            peripheral.activeMeasurement?.startNewDataSet(hz: Float(peripheral.signalHz!))
        }
    default:
        fatalError("Don't know how to start new dataset for \(String(describing: peripheral.projectMode))")
    }
}

// Protocol to allow others register work to perform ops on dispatch
public protocol SubscriberCallback {
    func fire(_ state: inout QsibState, _ action: Action)
}

public class NopCallback: SubscriberCallback {
    public func fire(_ state: inout QsibState, _ action: Action) {
        // nop
    }
}

