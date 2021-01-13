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
        LOGGER.trace("Fired SkinHydrationCallback on QsibState change for \(action)")
        switch action {
        case _ as InitBle:
            UserDefaults.standard.register(defaults: [
                "rtg_upper_limit_value": 50,
                "rtg_lower_limit_value": 20,

                "ble_shs_enforce_strict_checks": true,
                "ble_shs_ntc_bounds_lower": 30,
                "ble_shs_ntc_bounds_upper": 80,
                "ble_shs_ntc_diff": 24,
                                
                "ble_shs_name": ""
            ])
            
    //        UserDefaults.standard.setValue("", forKey: "ble_shs_name")
            
            // Begin UI refresh at least every N seconds
            UI_TICK()
        case _ as SetScan:
            UI_ACTION_DISPATCH(action: SetIsScanning(isScanning: state.ble!.isScanning))
        default:
            break
        }
    }
}
