//
//  StoreCallback.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 1/8/21.
//

import Foundation


import Foundation
import ReSwift
import Toast


public let STORE_CALLBACK: SubscriberCallback = StoreCallback()

public class StoreCallback: SubscriberCallback {
    public func fire(_ state: inout QsibState, _ action: Action) {
        LOGGER.trace("Fired SubscriberCallback on QsibState change for \(action)")
        switch action {
        case _ as InitBle:
            // Begin UI refresh at least every N seconds
            UI_TICK()
        case _ as SetScan:
            UI_ACTION_DISPATCH(action: SetIsScanning(isScanning: state.ble!.isScanning))
        default:
            break
        }
    }
}
