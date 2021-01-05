//
//  StatusControlVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 1/5/21.
//

import Foundation
import UIKit
import ReSwift

class StatusControlVC: UITableViewController, StoreSubscriber {
    
    var peripheral: QSPeripheral?
    var updateTs: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        LOGGER.debug("Loaded StatusControlVC")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        STORE.subscribe(self)
    }
        
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        STORE.unsubscribe(self)
    }
    
    func newState(state: AppState) {
        if self.peripheral == nil {
            if let identifier = state.activePeripheral {
                self.peripheral = state.peripherals[identifier]
                updateTs = nil
            }
        }
        
        guard let peripheral = self.peripheral else {
            return
        }
        
        var update = updateTs == nil
        if let updateTs = updateTs {
            update = Date().timeIntervalSince(updateTs) > 0.1
        }
        
        if update {
            DispatchQueue.main.async { [self] in
                if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) {
                    var connectionState = "nil"
                    switch peripheral.cbp.state {
                    case .disconnected:
                        connectionState = "Disconnected"
                    case .connecting:
                        connectionState = "Connecting"
                    case .connected:
                        connectionState = "Connected"
                    case .disconnecting:
                        connectionState = "Disconnecting"
                    default:
                        break
                    }
                    cell.detailTextLabel?.text = connectionState
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        
        switch indexPath.section {
        case 0:
            guard let peripheral = self.peripheral else {
                fatalError("No peripheral available but row was selected")
            }
            
            switch indexPath.row {
            case 0:
                return
            case 1:
                updateTs = nil
                ACTION_DISPATCH(action: RequestConnect(peripheral: peripheral.cbp))
            case 2:
                updateTs = nil
                ACTION_DISPATCH(action: RequestDisconnect(peripheral: peripheral.cbp))
            default:
                fatalError("Programming error for \(indexPath)")
            }
        case 1:
            switch indexPath.row {
            case 0:
                self.dismiss(animated: true, completion: nil)
            default:
                fatalError("Programming error for \(indexPath)")
            }
        default:
            fatalError("Programming error for \(indexPath)")
        }
    }
}
