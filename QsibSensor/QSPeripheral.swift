//
//  QSPeripheral.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/23/20.
//

import Foundation
import CoreBluetooth

struct QSPeripheral {
    var cbp: CBPeripheral!
    var name: String!
    var rssi: Int!
    var ts: Date!
    
    public init(peripheral: CBPeripheral, rssi: NSNumber) {
        self.set(peripheral: peripheral, rssi: rssi)
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
        set(peripheral: peripheral)
    }
    
    public func displayRssi() -> Optional<Int> {
        if Date().timeIntervalSince(ts) > 10 {
            return nil
        }
        return rssi
    }
}
