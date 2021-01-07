//
//  QSPeripheral.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/23/20.
//

import Foundation
import CoreBluetooth
import Toast


let MWV_PPG_V2 = "Mutliwavelength PPG V2"
let SHUNT_MONITOR_V1 = "Shunt Monitor V1"
let SKIN_HYDRATION_SENSOR_V2 = "Skin Hydration V2"


class MwvPpgV2ModeCodableState: Codable {
    var mode: String?
    var atime: Int?
    var astep: Int?
    var again: Int?
    var wcycles: Int?
    var drive: Int?
}

class ShuntMonitorV1CodableState: Codable {
    var mode: String?
}

class SkinHydrationV2CodableState: Codable {
    var mode: String?
}

class ProjectCodableState: Codable {
    var version: Int = 1
    var defaultMode: String?
    
    var mwv_ppg_v2_modes: [String: MwvPpgV2ModeCodableState] = [:]
    var sm_v1_modes: [String: ShuntMonitorV1CodableState] = [:]
    var shs_v2_modes: [String: SkinHydrationV2CodableState] = [:]
}

class PersistedConfig: Codable {
    var f0: Float?
    var f1: Float?
}

class QSPeripheralCodableState: Codable {
    var projectMode: String?
    var signalHz: Int?
    var signalChannels: Int?
    
    var firmwareVersion: String?
    var hardwareVersion: String?
    var persistedName: String?
    var uniqueIdentifier: String?
    
    var persistedConfig: PersistedConfig?

    var projects: [String: ProjectCodableState] = [:]
        
    init(
        _ projectMode: String?,
        _ signalHz: Int?,
        _ signalChannels: Int?,
        
        _ firmwareVersion: String?,
        _ hardwareVersion: String?,
        _ persistedName: String?,
        _ uniqueIdentifier: String?,
        
        _ persistedConfig: PersistedConfig?,

        _ projects: [String: ProjectCodableState]
    ) {
        self.projectMode = projectMode
        self.signalHz = signalHz
        self.signalChannels = signalChannels
        
        self.firmwareVersion = firmwareVersion
        self.hardwareVersion = hardwareVersion
        self.persistedName = persistedName
        self.uniqueIdentifier = uniqueIdentifier
        
        self.persistedConfig = persistedConfig

        self.projects = projects
    }
}

class QSPeripheral {
    var cbp: CBPeripheral!
    var characteristics: [UUID: CBCharacteristic]!
    var peripheralName: String!
    var rssi: Int!
    var ts: Date!
    
    var batteryLevel: Int?
    
    var projectMode: String?
    var signalHz: Int?
    var signalChannels: Int?
    
    var firmwareVersion: String?
    var hardwareVersion: String?
    var error: String?
    var persistedName: String?
    var uniqueIdentifier: String?
    var bootCount: Int?
    
    var persistedConfig: PersistedConfig?
    
    var activeMeasurement: QsMeasurement?
    var finalizedMeasurements: [QsMeasurement] = []

    var projects: [String: ProjectCodableState] = [:]
    
    public init(peripheral: CBPeripheral, rssi: NSNumber) {
        self.set(peripheral: peripheral, rssi: rssi)
        self.characteristics = [:]
        self.ts = Date()
        
        guard let encoded = UserDefaults.standard.data(forKey: id().uuidString) else {
            return
        }
        
        let decoder = JSONDecoder()
        guard let state = try? decoder.decode(QSPeripheralCodableState.self, from: encoded) else {
            LOGGER.error("Failed to decode state for \(id())")
            return
        }
        
        LOGGER.debug("Loaded coded state for \(id()): \(state)")
        
        projectMode = state.projectMode
        signalHz = state.signalHz
        signalChannels = state.signalChannels
        firmwareVersion = state.firmwareVersion
        hardwareVersion = state.hardwareVersion
        persistedName = state.persistedName
        uniqueIdentifier = state.uniqueIdentifier
        persistedConfig = state.persistedConfig
        projects = state.projects
    }
    
    public func save() {
        let state = QSPeripheralCodableState(
            projectMode,
            signalHz,
            signalChannels,
            firmwareVersion,
            hardwareVersion,
            persistedName,
            uniqueIdentifier,
            persistedConfig,
            projects)
        
        if let json = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(json, forKey: id().uuidString)
        } else {
            LOGGER.error("Failed to issue state save for \(id())")
        }
    }
    
    public func id() -> UUID {
        return cbp.identifier
    }
    
    public func name() -> String {
        guard let name = persistedName else {
            return self.peripheralName
        }
        return name
    }
    
    public func set(peripheral: CBPeripheral) {
        self.cbp = peripheral
        self.peripheralName = peripheral.name ?? "Unknown"
        self.ts = Date()
    }
    
    public func set(peripheral: CBPeripheral, rssi: NSNumber) {
        self.rssi = Int(truncating: rssi)
        set(peripheral: peripheral)
    }
    
    public func add(characteristic: CBCharacteristic) {
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
    
    public func writePersistedConfig() {
        let floats: [Float] = [persistedConfig?.f0 ?? 10, persistedConfig?.f1 ?? 0]
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        LOGGER.trace("Writing persisted config: \(data.hexEncodedString())")
        assert(data.count == 8)
        writeDataToChar(cbuuid: QSS_SHS_CONF_UUID, data: data)
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
    
    public func start() {
        switch projectMode ?? "" {
        case MWV_PPG_V2:
            writeProjectControlForPpg()
        case SHUNT_MONITOR_V1:
            writeProjectControlForShuntMonitor()
        case SKIN_HYDRATION_SENSOR_V2:
            writeProjectControlForSkinHydrationV2()
        default:
            fatalError("Unsupported peripheral type to use to start measurement \(String(describing: projectMode))")
        }
    }
    
    public func resume() {
        // doesn't need to be different for any devices at the moment
        start()
    }
    
    public func pause() {
        switch self.projectMode ?? "" {
        case MWV_PPG_V2:
            let data = Data([
                UInt8(0x01),                        // Command
                UInt8(0),                           // Mode
                UInt8(0),                           // ATIME
                UInt8(0),                           // ASTEP H
                UInt8(0),                           // ASTEP L
                UInt8(0),                           // AGAIN
                UInt8(0),                           // WCYCLES
                UInt8(0)                            // DRIVE
                ])
            writeControl(data: data)
        case SHUNT_MONITOR_V1:
            writeControl(data: Data([0x00]))
        case SKIN_HYDRATION_SENSOR_V2:
            writeControl(data: Data([0x01, 0x00]))
        default:
            fatalError("Don't know how to pause \(String(describing: self.projectMode))")
        }
    }
    
    public func turnOff() {
        switch self.projectMode ?? "" {
        case MWV_PPG_V2, SKIN_HYDRATION_SENSOR_V2:
            pause()
        case SHUNT_MONITOR_V1:
            let data = Data(repeating: 0xFF, count: 23)
            writeControl(data: data)
        default:
            fatalError("Don't know how to turn off \(String(describing: self.projectMode))")
        }
    }
    
    /*!
     * Write the control message for the PPG sensor.
     * At V2 the following packed struct is expected as the value

        enum class mwv_ppg_cmd_e: uint8_t {
            NOP    = 0, // Common across projects
            PAUSE  = 1, // Common across projects
            ALTER  = 2, // Begin mwv_ppg_cmd_e commands
     
            OFF    = 0xFF, // OFF = control_msg of 0xFF's for whole message
        };

        enum class mwv_ppg_mode_e: uint8_t {
            OFF    = 0,
            MODE_0 = 1,
            MODE_1 = 2,
            MODE_2 = 3,
            MODE_3 = 4
        };

        struct mwv_ppg_qss_control_t {
            mwv_ppg_cmd_e command = mwv_ppg_cmd_e::NOP;
            mwv_ppg_mode_e mode = mwv_ppg_mode_e::OFF;
            uint8_t atime = drivers::as7341::config_t::ATIME_RECOMMENDED;
            uint16_t astep = drivers::as7341::config_t::ASTEP_RECOMMENDED;
            uint8_t again = drivers::as7341::config_t::AGAIN_RECOMMENDED;
            uint8_t wcycles = drivers::as7341::config_t::WTIME_500MS;
            uint8_t drive = drivers::as7341::config_t::DEFAULT_LED_DRIVE;
        };
    
     */
    public func writeProjectControlForPpg() {
        if let mode = projects[MWV_PPG_V2]?.defaultMode,
            let modeInfo = projects[MWV_PPG_V2]?.mwv_ppg_v2_modes[mode],
            let atime = modeInfo.atime,
            let astep = modeInfo.astep,
            let again = modeInfo.again,
            let wcycles = modeInfo.wcycles,
            let drive = modeInfo.drive {

            var enumMode = 0
            switch mode {
            case "IDLE":
                enumMode = 0
            case "MODE 0":
                enumMode = 1
            case "MODE 1":
                enumMode = 2
            case "MODE 2":
                enumMode = 3
            case "MODE 3":
                enumMode = 4
            default:
                LOGGER.error("Invalid mode \(mode)")
            }

            let data = Data([
                UInt8(0x02),                        // Command
                UInt8(enumMode),                    // Mode
                UInt8(atime),                       // ATIME
                UInt8((UInt16(astep) & 0xFF)),      // ASTEP L
                UInt8((UInt16(astep) >> 8) & 0xFF), // ASTEP H
                UInt8(again),                       // AGAIN
                UInt8(wcycles),                     // WCYCLES
                UInt8(drive)                        // DRIVE
                ])
            writeControl(data: data)
        } else {
            LOGGER.error("Not enough info set to write control for MWV PPG")
        }
    }

    public func writeProjectControlForShuntMonitor() {
        let data = Data([0x69])
        writeControl(data: data)
    }
    
    public func writeProjectControlForSkinHydrationV2() {
        let data = Data([0x02, 0x01])
        writeControl(data: data)
    }
    
    public func getOrDefaultProject() -> ProjectCodableState {
        switch projectMode ?? "" {
        case MWV_PPG_V2:
            if projects[MWV_PPG_V2] == nil {
                let projectState = ProjectCodableState()
                projectState.defaultMode = "IDLE"
                
                let idleState = MwvPpgV2ModeCodableState()
                idleState.mode = "IDLE"
                idleState.atime = 29
                idleState.astep = 599
                idleState.again = 9
                idleState.wcycles = 179
                idleState.drive = 4
                projectState.mwv_ppg_v2_modes[idleState.mode!] = idleState
                
                let mode0State = MwvPpgV2ModeCodableState()
                mode0State.mode = "MODE 0"
                mode0State.atime = 29
                mode0State.astep = 599
                mode0State.again = 9
                mode0State.wcycles = 179
                mode0State.drive = 4
                projectState.mwv_ppg_v2_modes[mode0State.mode!] = mode0State

                let mode1State = MwvPpgV2ModeCodableState()
                mode1State.mode = "MODE 1"
                mode1State.atime = 29
                mode1State.astep = 599
                mode1State.again = 9
                mode1State.wcycles = 179
                mode1State.drive = 4
                projectState.mwv_ppg_v2_modes[mode1State.mode!] = mode1State

                let mode2State = MwvPpgV2ModeCodableState()
                mode2State.mode = "MODE 2"
                mode2State.atime = 29
                mode2State.astep = 599
                mode2State.again = 9
                mode2State.wcycles = 179
                mode2State.drive = 4
                projectState.mwv_ppg_v2_modes[mode2State.mode!] = mode2State

                let mode3State = MwvPpgV2ModeCodableState()
                mode3State.mode = "MODE 3"
                mode3State.atime = 29
                mode3State.astep = 599
                mode3State.again = 9
                mode3State.wcycles = 179
                mode3State.drive = 4
                projectState.mwv_ppg_v2_modes[mode3State.mode!] = mode3State

                
                projects[MWV_PPG_V2] = projectState
            }
            
            guard let project = projects[projectMode ?? ""] else {
                fatalError("Inconsistent app state for project \(self)")
            }
            
            return project
        case SHUNT_MONITOR_V1:
            if projects[SHUNT_MONITOR_V1] == nil {
                let projectState = ProjectCodableState()
                projectState.defaultMode = "MODE 0"
                
                let mode0State = ShuntMonitorV1CodableState()
                mode0State.mode = "MODE 0"
                
                projectState.sm_v1_modes[mode0State.mode!] = mode0State
                
                projects[SHUNT_MONITOR_V1] = projectState
            }
            
            guard let project = projects[projectMode ?? ""] else {
                fatalError("Inconsistent app state for project \(self)")
            }
            
            return project

        case SKIN_HYDRATION_SENSOR_V2:
            if projects[SKIN_HYDRATION_SENSOR_V2] == nil {
                let projectState = ProjectCodableState()
                projectState.defaultMode = "MODE 0"
                
                let mode0State = SkinHydrationV2CodableState()
                mode0State.mode = "MODE 0"
                
                projectState.shs_v2_modes[mode0State.mode!] = mode0State
                
                projects[SKIN_HYDRATION_SENSOR_V2] = projectState
            }
            
            guard let project = projects[projectMode ?? ""] else {
                fatalError("Inconsistent app state for project \(self)")
            }
            
            return project
        default:
            LOGGER.error("No implementation of default for \(projectMode ?? "")")
            return projects[projectMode ?? ""] ?? ProjectCodableState()
        }
    }
}
