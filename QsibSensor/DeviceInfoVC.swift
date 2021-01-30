//
//  DeviceInfoVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/23/20.
//

import Foundation
import UIKit
import ReSwift
import Toast

class DeviceInfoVC: UITableViewController, StoreSubscriber {
    
    var peripheral: QSPeripheral?
    var updateTs = Date()
    var cellHeights: [IndexPath: CGFloat] = [:]

    
    var tablePaths: [IndexPath] = [
        // Qsib Sensor Central
        IndexPath(row: 0, section: 0), // Project Mode
        IndexPath(row: 1, section: 0), // Signal Interpretation
        IndexPath(row: 2, section: 0), // Signal Interpretation :: Sample Rate
        IndexPath(row: 3, section: 0), // Signal Interpretation :: Channels
                
        // Qsib Sensor Service Peripheral
        IndexPath(row: 0, section: 1), // Control
        IndexPath(row: 1, section: 1), // Signal
        IndexPath(row: 2, section: 1), // Firmware Version
        IndexPath(row: 3, section: 1), // Hardware Version
        IndexPath(row: 4, section: 1), // Error
        IndexPath(row: 5, section: 1), // Name
        IndexPath(row: 6, section: 1), // Unique Identifier
        IndexPath(row: 7, section: 1), // Boot Count
        IndexPath(row: 8, section: 1), // Calibration
        IndexPath(row: 9, section: 1), // Calibration
    ]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.allowsSelection = true
        tableView.allowsSelectionDuringEditing = false
        tableView.allowsMultipleSelection = false
        
        self.view.makeToastActivity(.center)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.view.hideToastActivity()
        }
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
        var updateInfo = false
        if let identifier = state.activePeripheral {
            if let peripheral = state.peripherals[identifier] {
                self.peripheral = peripheral
                updateInfo = true
            }
        }
        
        guard updateInfo else {
            return
        }
        guard Float(Date().timeIntervalSince(updateTs)) > 0.25 else {
            return
        }
        updateTs = Date()

        
        DispatchQueue.main.async { [self] in
            guard let peripheral = self.peripheral else {
                LOGGER.error("Cannot update device info without ")
                return
            }
            
            for indexPath in tablePaths {
                switch indexPath.section {
                case 0:
                    // QSIB Sensor Central Rows
                    switch indexPath.row {
                    case 0:
                        let projectModeCell = tableView.cellForRow(at: indexPath)
                        projectModeCell?.detailTextLabel?.text = peripheral.projectMode ?? "Undefined"
                    case 1:
                        break
                    case 2:
                        let sampleRateCell = tableView.cellForRow(at: indexPath)
                        switch peripheral.projectMode ?? "" {
                        case MWV_PPG_V2, OXIMETER_V0:
                            sampleRateCell?.detailTextLabel?.text = "--- Hz"
                        default:
                            sampleRateCell?.detailTextLabel?.text = peripheral.signalHz == nil ? "_ Hz" : "\(peripheral.signalHz!) Hz"
                        }
                    case 3:
                        let channelCell = tableView.cellForRow(at: indexPath)
                        channelCell?.detailTextLabel?.text = peripheral.signalChannels == nil ? "_" : "\(peripheral.signalChannels!)"
                    default:
                        fatalError("Invalid row selection for \(indexPath)")
                    }
//                case 1:
//                    switch self.peripheral?.projectMode ?? "" {
//                    case MWV_PPG_V2:
//                        break
//                    default:
//                        break
//                    }
                case 1:
                    // QSIB Sensor Service Rows
                    switch indexPath.row {
                    case 0:
                        break
                    case 1:
                        break
                    case 2:
                        let firmwareVersionCell = tableView.cellForRow(at: indexPath)
                        firmwareVersionCell?.detailTextLabel?.text = peripheral.firmwareVersion
                    case 3:
                        let hardwareVersionCell = tableView.cellForRow(at: indexPath)
                        hardwareVersionCell?.detailTextLabel?.text = peripheral.hardwareVersion
                    case 4:
                        let errorCell = tableView.cellForRow(at: indexPath)
                        if peripheral.error == nil || peripheral.error!.isEmpty {
                            errorCell?.detailTextLabel?.text = "none"

                        } else {
                            errorCell?.detailTextLabel?.text = peripheral.error
                        }
                    case 5:
                        let nameCell = tableView.cellForRow(at: indexPath)
                        nameCell?.detailTextLabel?.text = peripheral.name()
                        break
                    case 6:
                        let uuidCell = tableView.cellForRow(at: indexPath)
                        uuidCell?.detailTextLabel?.text = peripheral.uniqueIdentifier
                        break
                    case 7:
                        let bootCountCell = tableView.cellForRow(at: indexPath)
                        bootCountCell?.detailTextLabel?.text = "\(peripheral.bootCount ?? 0)"
                        break
                    case 8:
                        let cf0Cell = tableView.cellForRow(at: indexPath)
                        cf0Cell?.detailTextLabel?.text = "\(peripheral.persistedConfig?.f0 ?? -1)"
                    case 9:
                        let cf1Cell = tableView.cellForRow(at: indexPath)
                        cf1Cell?.detailTextLabel?.text = "\(peripheral.persistedConfig?.f1 ?? -1)"
                    default:
                        fatalError("Invalid row selection for \(indexPath)")
                    }
                default:
                    fatalError("Invalid section selection for \(indexPath)")
                }
            }
            
            tableView.reloadData()
        }
    }
    
    func isProjectConfigged() -> Bool {
        return [MWV_PPG_V2].contains(self.peripheral?.projectMode)
    }

    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cellHeights[indexPath] = cell.frame.size.height
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeights[indexPath] ?? UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let peripheral = self.peripheral else {
            LOGGER.error("Cannot update device info without peripheral")
            return
        }

        switch indexPath.section {
        case 0:
            // QSIB Sensor Central Rows
            switch indexPath.row {
            case 0:
                // show project picker
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
                editorVC.headerLabelText = "Project Mode"
                editorVC.options = [OXIMETER_V0, MWV_PPG_V2, SKIN_HYDRATION_SENSOR_V2, SHUNT_MONITOR_V1, PRESSURE_MONITOR_V1]
                if let projectMode = peripheral.projectMode {
                    editorVC.proposedValue = editorVC.options.firstIndex(of: "\(projectMode)") ?? 0
                    editorVC.confirmedValue = editorVC.options.firstIndex(of: "\(projectMode)")
                } else {
                    editorVC.proposedValue = 0
                    editorVC.confirmedValue = nil
                }
                editorVC.predicate = { (i) in return true }
                editorVC.actionFactory = { selectedIndex in
                    let selection = editorVC.options[selectedIndex]
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Configured signal interpretation projectMode: \(selection)")
                        return UpdateProjectMode(peripheral: peripheral, projectMode: selection)
                    } else {
                        LOGGER.error("No peripheral available to update hz: \(selection)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)

                break
            case 1:
                // not allowed
                break
            case 2:
                // show hz picker
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
                editorVC.headerLabelText = "Sample Hz"
                editorVC.options = (0...15).map { "\(1 << $0)" }
                editorVC.options.append("\(256 * 14)")
                if let signalHz = peripheral.signalHz {
                    editorVC.proposedValue = editorVC.options.firstIndex(of: "\(signalHz)") ?? 0
                    editorVC.confirmedValue = editorVC.options.firstIndex(of: "\(signalHz)")
                } else {
                    editorVC.proposedValue = 0
                    editorVC.confirmedValue = nil
                }
                editorVC.predicate = { (i) in return true }
                editorVC.actionFactory = { selectedIndex in
                    let selection = editorVC.options[selectedIndex]
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Configured signal interpretation hz: \(selection)")
                        if let hz = Int(selection) {
                            return UpdateSignalHz(peripheral: peripheral, hz: hz)
                        } else {
                            LOGGER.error("Could not parse hz input: \(selection)")
                            return AppendToast(message: ToastMessage(message: "Cannot parse hz input", duration: TimeInterval(2), position: .center, title: "Input Error", image: nil, style: ToastStyle(), completion: nil))
                        }
                    } else {
                        LOGGER.error("No peripheral available to update hz: \(selection)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
                break
            case 3:
                // show channel picker
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
                editorVC.headerLabelText = "Channels"
                editorVC.options = (1...8).map { "\($0)" }
                if let signalChannels = peripheral.signalChannels {
                    editorVC.proposedValue = editorVC.options.firstIndex(of: "\(signalChannels)") ?? 0
                    editorVC.confirmedValue = editorVC.options.firstIndex(of: "\(signalChannels)")
                } else {
                    editorVC.proposedValue = 0
                    editorVC.confirmedValue = nil
                }
                editorVC.predicate = { (i) in return true }
                editorVC.actionFactory = { selectedIndex in
                    let selection = editorVC.options[selectedIndex]
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Configured signal interpretation channels: \(selection)")
                        if let channels = Int(selection) {
                            return UpdateSignalChannels(peripheral: peripheral, channels: channels)
                        } else {
                            LOGGER.error("Could not parse channels input: \(selection)")
                            return AppendToast(message: ToastMessage(message: "Cannot parse channels input", duration: TimeInterval(2), position: .center, title: "Input Error", image: nil, style: ToastStyle(), completion: nil))
                        }
                    } else {
                        LOGGER.error("No peripheral available to update channels: \(selection)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
                break
            default:
                fatalError("Invalid row selection for \(indexPath)")
            }
        case 1:
            // QSIB Sensor Service Rows
            switch indexPath.row {
            case 0:
                // show command picker and choice to send/cancel
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Control"
                editorVC.placeholderValue = "00010203"
                editorVC.confirmedValue = ""
                editorVC.proposedValue = ""
                editorVC.predicate = { $0.range(of: "^([0-9a-fA-f]{2})+?$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for control: \(inputString)")
                        if let data = inputString.data(using: .hexadecimal) {
                            return WriteControl(peripheral: peripheral, control: data)
                        } else {
                            LOGGER.error("Could not parse control input: \(inputString)")
                            return AppendToast(message: ToastMessage(message: "Cannot parse control input", duration: TimeInterval(2), position: .center, title: "Input Error", image: nil, style: ToastStyle(), completion: nil))
                        }
                    } else {
                        LOGGER.error("No peripheral available to issue write for control: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
            case 1:
                // not allowed
                break
            case 2:
                // not allowed
                break
            case 3:
                // show text field to write hardware version
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Hardware Version"
                editorVC.placeholderValue = "v0.0.1"
                editorVC.confirmedValue = ""
                editorVC.proposedValue = ""
                editorVC.predicate = { $0.range(of: "^v\\d+\\.\\d+(\\.\\d+)?$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for hardware version: \(inputString)")
                        return WriteHardwareVersion(peripheral: peripheral, hardwareVersion: inputString)
                    } else {
                        LOGGER.error("No peripheral available to issue write for hardware version: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
            case 4:
                // not allowed
                break
            case 5:
                // show text field to write name
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Name"
                editorVC.placeholderValue = "QSS0"
                editorVC.confirmedValue = peripheral.name()
                editorVC.proposedValue = ""
                editorVC.predicate = { $0.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for name: \(inputString)")
                        return WriteName(peripheral: peripheral, name: inputString)
                    } else {
                        LOGGER.error("No peripheral available to issue write for name: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
            case 6:
                // show text field to write unique identifier
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Unique Identifier"
                editorVC.placeholderValue = peripheral.uniqueIdentifier
                editorVC.confirmedValue = peripheral.uniqueIdentifier
                editorVC.proposedValue = UUID().uuidString
                editorVC.predicate = { $0.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for unique identifier: \(inputString)")
                        return WriteUniqueIdentifier(peripheral: peripheral, uniqueIdentifier: inputString)
                    } else {
                        LOGGER.error("No peripheral available to issue write for unique identifier: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
            case 7:
                // not allowed
                break
            case 8:
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Calibration Factor 0"
                editorVC.placeholderValue = String.init(format: "%.03f", peripheral.persistedConfig?.f0 ?? 10)
                editorVC.confirmedValue = String.init(format: "%.03f", peripheral.persistedConfig?.f0 ?? Float.infinity)
                editorVC.proposedValue = String.init(format: "%.03f", peripheral.persistedConfig?.f0 ?? Float.infinity)
                editorVC.predicate = { $0.range(of: "^-?[0-9]+(.[0-9]+)?$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for calibration factor 0: \(inputString)")
                        return WriteCalibrationFactor0(peripheral: peripheral, f0: Float(inputString)!)
                    } else {
                        LOGGER.error("No peripheral available to issue write for calibration factor 0: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)
            case 9:
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "textAttributeEditorVC") as! textAttributeEditorVC
                editorVC.headerLabelText = "Calibration Factor 1"
                editorVC.placeholderValue = String.init(format: "%.03f", peripheral.persistedConfig?.f1 ?? 10)
                editorVC.confirmedValue = String.init(format: "%.03f", peripheral.persistedConfig?.f1 ?? Float.infinity)
                editorVC.proposedValue = String.init(format: "%.03f", peripheral.persistedConfig?.f1 ?? Float.infinity)
                editorVC.predicate = { $0.range(of: "^-?[0-9]+(.[0-9]+)?$", options: .regularExpression) != nil }
                editorVC.actionFactory = { inputString in
                    if let peripheral = peripheral.cbp {
                        LOGGER.info("Issuing write for calibration factor 1: \(inputString)")
                        return WriteCalibrationFactor1(peripheral: peripheral, f1: Float(inputString)!)
                    } else {
                        LOGGER.error("No peripheral available to issue write for calibration factor 1: \(inputString)")
                        return QsibTick()
                    }
                }
                self.present(editorVC, animated: true)

            default:
                fatalError("Invalid row selection for \(indexPath)")
            }
        default:
            fatalError("Invalid section selection for \(indexPath)")
        }
    }
}


