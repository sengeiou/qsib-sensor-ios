//
//  ConnectedDeviceVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 1/5/21.
//

import Foundation
import UIKit
import ReSwift

class ConnectedDeviceVC: UITabBarController, StoreSubscriber {
    
    var peripheral: QSPeripheral?
    var updateTs: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        LOGGER.debug("Loaded ConnectedDeviceVC")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        QSIB_STORE.subscribe(self)
    }
        
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        QSIB_STORE.unsubscribe(self)
    }
    
    func newState(state: QsibState) {
        if self.peripheral == nil || self.peripheral!.id() != state.activePeripheral {
            if let identifier = state.activePeripheral {
                self.peripheral = state.peripherals[identifier]
                updateTs = nil
            }
        }
        
        guard let peripheral = self.peripheral else {
            return
        }
        
        var update = updateTs == nil || peripheral.cbp.state == .disconnected
        if let updateTs = updateTs {
            update = Date().timeIntervalSince(updateTs) > 0.1
        }
        
        if update {
            DispatchQueue.main.async { [self] in
                switch peripheral.cbp.state {
                case .disconnected:
                    self.tabBar.items?[2].badgeValue = "!"
                case .connecting:
                    self.tabBar.items?[2].badgeValue = "..."
                case .connected:
                    self.tabBar.items?[2].badgeValue = nil
                case .disconnecting:
                    self.tabBar.items?[2].badgeValue = "..."
                default:
                    self.tabBar.items?[2].badgeValue = "!!"
                }
            }
        }
    }
}
