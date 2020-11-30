//
//  QSPeripheral.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/23/20.
//

import Foundation
import CoreBluetooth
import Toast

class QSPeripheralCodableState: Codable {
    var projectMode: String?
    var signalHz: Int?
    var signalChannels: Int?
    
    var firmwareVersion: String?
    var hardwareVersion: String?
    var persistedName: String?
    var uniqueIdentifier: String?
        
    init(
        _ projectMode: String?,
        _ signalHz: Int?,
        _ signalChannels: Int?,
        
        _ firmwareVersion: String?,
        _ hardwareVersion: String?,
        _ persistedName: String?,
        _ uniqueIdentifier: String?
    ) {
        self.projectMode = projectMode
        self.signalHz = signalHz
        self.signalChannels = signalChannels
        
        self.firmwareVersion = firmwareVersion
        self.hardwareVersion = hardwareVersion
        self.persistedName = persistedName
        self.uniqueIdentifier = uniqueIdentifier
    }
}


class Measurement {
    let start = Date()
    var stop: Date?
    var counters: [UInt32] = []
    var channels: [[[Int16]]] = [] // [channelIdx][notificationIdx][sampleIdx]
    
    var runningTime: Double?
    var graphableTime: [Double] = []
    var graphableChannels: [[Double]] = [] // [channelIdx][sampleIdx]
    
    init(numChannels: Int) {
        for _ in 0..<numChannels {
            channels.append([])
            graphableChannels.append([])
        }
    }
    
    public func addPayload(data: Data, signalHz hz: Int) {
        guard data.count > 4 + 1 + 1 else {
            LOGGER.error("Received payload that could not be valid because it is too short")
            return
        }
        let expectedCount = data.withUnsafeBytes {
            $0.load(fromByteOffset: 0, as: UInt8.self)
        }
        guard expectedCount == data.count else {
            LOGGER.error("Received payload of length \(data.count) that says that it is of length \(expectedCount)")
            return
        }
        let splitByte = data.withUnsafeBytes {
            $0.load(fromByteOffset: 1, as: UInt8.self)
        }
        let numChannels = (splitByte & 0b11110000) >> 4
        let counterOverflow = splitByte & 0b00001111
        guard numChannels == channels.count && counterOverflow < 64 else {
            // 64 is not invalid but indicates that ~130B notifications have happened (unlikely and not handled)
            // 10 years of advertising at 64 Hz ... hard to imagine hitting this limit
            LOGGER.error("Received payload with split byte parsed as numChannels \(numChannels) and counterOverflow \(counterOverflow)")
            return
        }

        var bufferIndex = 2
        let counter = data.withUnsafeBytes { bufPtr -> UInt32 in
            var counter: UInt32 = 0
            _ = Swift.withUnsafeMutableBytes(of: &counter) { ptr in
                let range = bufferIndex..<bufferIndex+MemoryLayout<UInt32>.size
                bufPtr.copyBytes(to: ptr, from: range)
            }
            return counter
        }
        bufferIndex += 4
        counters.append(counter)
        
        let sampleInterval = TimeInterval(1.0 / Float(hz))
        if runningTime == nil {
            runningTime = -sampleInterval
        }
        
        data.withUnsafeBytes { (ptr) in
            var channelIndex = 0
            let numChannels = channels.count
            var newChannels: [[Int16]] = (1...numChannels).map { (_) in [] }
            while bufferIndex < expectedCount {
                let sample = data.withUnsafeBytes { bufPtr -> Int16 in
                    var sample: Int16 = 0
                    _ = Swift.withUnsafeMutableBytes(of: &sample) { ptr in
                        let range = bufferIndex..<bufferIndex+MemoryLayout<UInt16>.size
                        bufPtr.copyBytes(to: ptr, from: range)
                    }
                    return sample
                }

                graphableChannels[channelIndex].append(Double(sample))
                newChannels[channelIndex].append(sample)
                bufferIndex += 2
                channelIndex += 1
                
                if channelIndex == numChannels {
                    channelIndex = 0
                    runningTime! += sampleInterval
                    graphableTime.append(runningTime!)
                }
            }
            
            for (channelIndex, newChannelData) in newChannels.enumerated() {
                channels[channelIndex].append(newChannelData)
            }
        }
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
    
    var activeMeasurement: Measurement?
    var finalizedMeasurements: [Measurement] = []
    
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

    }
    
    public func save() {
        let state = QSPeripheralCodableState(
            projectMode,
            signalHz,
            signalChannels,
            firmwareVersion,
            hardwareVersion,
            persistedName,
            uniqueIdentifier)
        
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
