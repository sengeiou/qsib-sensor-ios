//
//  InspectDataVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/24/20.
//

import Foundation
import UIKit
import Toast
import ReSwift
import Charts

class ControlCell: UITableViewCell {

}

class ChannelCell: UITableViewCell, ChartViewDelegate {
    static let COLORS = [
        UIColor.systemBlue,
        UIColor.systemGreen,
        UIColor.systemRed,
        UIColor.systemPurple,
        UIColor.systemPink,
        UIColor.systemTeal,
        UIColor.systemYellow,
        UIColor.systemPink,
        UIColor.systemGray
    ]

    @IBOutlet weak var chartView: LineChartView!
    
    var timestamps: [Double]! = nil
    var channel: [Double]! = nil
    var dataLabel: String! = nil
    var colorIndex: Int! = nil
    
    func updateChartView() {
        self.chartView.xAxis.removeAllLimitLines()
        self.chartView.leftAxis.removeAllLimitLines()
        self.chartView.rightAxis.removeAllLimitLines()
        
        var dataSets: [LineChartDataSet] = []
        for rawData in [zip(timestamps, channel)] {
            let entries: [ChartDataEntry] = rawData.map { ChartDataEntry(x: $0.0, y: $0.1) }
            let color = ChannelCell.COLORS[colorIndex % ChannelCell.COLORS.count]
            let dataSet = LineChartDataSet(entries: entries, label: self.dataLabel)
            dataSet.mode = LineChartDataSet.Mode.linear
            dataSet.axisDependency = .left
            dataSet.setColor(color)
            dataSet.lineWidth = 0
            dataSet.circleRadius = 2
            dataSet.setCircleColor(color)
            dataSets.append(dataSet)
        }
        
        let chartData = LineChartData(dataSets: dataSets)
        chartData.setDrawValues(true)
        
        chartView.data = chartData
        chartView.xAxis.labelPosition = .bottom
        chartView.rightAxis.enabled = false
        chartView.extraLeftOffset = 10.0
        chartView.extraRightOffset = 10.0
        chartView.extraTopOffset = 20.0
        chartView.extraBottomOffset = 20.0
        chartView.dragEnabled = true
        chartView.pinchZoomEnabled = true
        chartView.setScaleEnabled(true)
        chartView.isHidden = false
    }
}

public enum GraphType {
    case trailing_5
    case trailing_15
    case trailing_30
    case trailing_60
    case trailing_120
    case downsampled
}

class InspectDataVC: UITableViewController, StoreSubscriber {
    
    var peripheral: QSPeripheral?
    var updateTs: Date? = nil
    var graphType = GraphType.trailing_60
    var graphData: TimeSeriesData? = nil
    
    var cellHeights: [IndexPath: CGFloat] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.backgroundColor = UIColor.systemGroupedBackground
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
        
        guard updateTs == nil || Date().timeIntervalSince(updateTs!) > 0.5 || (graphData == nil && peripheral?.activeMeasurement != nil) else {
            return
        }
        updateTs = Date()
        
        if let activeMeasurement = peripheral?.activeMeasurement {
            switch graphType {
            case .trailing_5:
                graphData = activeMeasurement.getTrailingData(secondsInTrailingWindow: 5)
            case .trailing_15:
                graphData = activeMeasurement.getTrailingData(secondsInTrailingWindow: 15)
            case .trailing_30:
                graphData = activeMeasurement.getTrailingData(secondsInTrailingWindow: 30)
            case .trailing_60:
                graphData = activeMeasurement.getTrailingData(secondsInTrailingWindow: 60)
            case .trailing_120:
                graphData = activeMeasurement.getTrailingData(secondsInTrailingWindow: 120)
            case .downsampled:
                graphData = activeMeasurement.getDownsampledData()
            }
            LOGGER.trace("Graph \(graphType) data has \(String(describing: graphData?.timestamps.count)) timestamps")
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    func isProjectConfigged() -> Bool {
        return [MWV_PPG_V2].contains(self.peripheral?.projectMode)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 6
        default:
            if isProjectConfigged() && section == 1 {
                switch self.peripheral?.projectMode ?? "" {
                case MWV_PPG_V2:
                    // Could add rows for the section specific to mwv_ppg_v2
                    // switch indexPath.row {
                    //     case 0: break // Mode
                    //     case 1: break // atime
                    //     case 2: break // astep
                    //     case 3: break // again
                    //     case 4: break // wcycles
                    //     case 5: break // drive
                    //     case 6: break // Apply
                    // }
                    return 7
                default:
                    return 1
                }
            } else {
                return 1
            }
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        let baseSections = 1 + (self.peripheral?.signalChannels ?? 0)
        switch self.peripheral?.projectMode ?? "" {
        case MWV_PPG_V2:
            // Add 1 section for configuration of measurement
            return baseSections + 1
        default:
            return baseSections
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cellHeights[indexPath] = cell.frame.size.height
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return cellHeights[indexPath] ?? UITableView.automaticDimension
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Control"
        default:
            if isProjectConfigged() && section == 1 {
                switch self.peripheral?.projectMode ?? "" {
                case MWV_PPG_V2:
                    return "\(MWV_PPG_V2) Config"
                default:
                    return "Channel \(section - 1)"
                }
            } else {
                return "Channel \(section - 1)"
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let peripheral = self.peripheral else {
            LOGGER.error("No peripheral to use to start measurement")
            fatalError("No peripheral to use to start measurement")
        }
        
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                LOGGER.debug("Selected turn off device ...")
                QSIB_ACTION_DISPATCH(action: TurnOffSensor(peripheral: peripheral.cbp))
                self.dismiss(animated: true)
            case 2:
                LOGGER.debug("Selected start measurement ...")
                if let measurementState = self.peripheral?.activeMeasurement?.state {
                    switch measurementState {
                    case .initial:
                        QSIB_ACTION_DISPATCH(action: StartMeasurement(peripheral: peripheral.cbp))
                    case .paused:
                        QSIB_ACTION_DISPATCH(action: ResumeMeasurement(peripheral: peripheral.cbp))
                    case .running:
                        QSIB_ACTION_DISPATCH(action: PauseMeasurement(peripheral: peripheral.cbp))
                    case .ended:
                        LOGGER.debug("Ignoring selection with ended active measurement on \(indexPath)")
                    }
                } else {
                    QSIB_ACTION_DISPATCH(action: StartMeasurement(peripheral: peripheral.cbp))
                }
            case 3:
                LOGGER.debug("Selected stop measurement ...")
                if let measurementState = self.peripheral?.activeMeasurement?.state {
                    switch measurementState {
                    case .initial, .paused, .running, .ended:
                        QSIB_ACTION_DISPATCH(action: StopMeasurement(peripheral: peripheral.cbp))
                    }
                } else {
                    LOGGER.debug("Ignoring selection without active measurement on \(indexPath)")
                }
            case 4:
                LOGGER.debug("Selected save and export measurement ...")
                var measurement = peripheral.activeMeasurement
                if measurement == nil {
                    measurement = peripheral.finalizedMeasurements.last
                }
                if let measurement = measurement {
                    LOGGER.debug("Pausing for export from \(measurement.state)")
                    
                    // Pause
                    QSIB_ACTION_DISPATCH(action: PauseMeasurement(peripheral: peripheral.cbp))
                    
                    // Let the user know that we are working on it
                    DispatchQueue.main.async { self.view.makeToastActivity(.center) }
                    
                    DISPATCH.execute {
                        // Archive
                        guard let archive = try? measurement.archive() else {
                            LOGGER.error("Cannot export archive because archiving failed")
                            return
                        }
                        
                        // AirDrop
                        DispatchQueue.main.async {
                            // Done working remove activity indicator and
                            self.view.hideToastActivity()
                            
                            // Show pop over activity
                            let controller = UIActivityViewController.init(activityItems: [archive], applicationActivities: nil)
                            controller.excludedActivityTypes = [UIActivity.ActivityType.postToTwitter, UIActivity.ActivityType.postToFacebook, UIActivity.ActivityType.postToWeibo, UIActivity.ActivityType.message, UIActivity.ActivityType.print, UIActivity.ActivityType.copyToPasteboard, UIActivity.ActivityType.assignToContact, UIActivity.ActivityType.saveToCameraRoll, UIActivity.ActivityType.addToReadingList, UIActivity.ActivityType.postToFlickr,  UIActivity.ActivityType.postToVimeo, UIActivity.ActivityType.postToTencentWeibo]
                            
                            controller.popoverPresentationController?.sourceView = self.view

                            self.present(controller, animated: true, completion: nil)
                        }
                    }
                } else {
                    LOGGER.debug("Ignoring selection without active measurement on \(indexPath)")
                }
            case 5:
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let editorVC  = storyboard.instantiateViewController(withIdentifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
                editorVC.headerLabelText = "Graph Type"
                editorVC.options = ["Trailing 5s", "Trailing 15s", "Trailing 30s", "Trailing 60s", "Trailing 120s", "Downsample from all"]
                editorVC.proposedValue = 3
                editorVC.confirmedValue = nil
                editorVC.predicate = { (i) in return true }
                editorVC.actionFactory = { selectedIndex in
                    switch selectedIndex {
                    case 0:
                        self.graphType = .trailing_5
                    case 1:
                        self.graphType = .trailing_15
                    case 2:
                        self.graphType = .trailing_30
                    case 3:
                        self.graphType = .trailing_60
                    case 4:
                        self.graphType = .trailing_120
                    case 5:
                        self.graphType = .downsampled
                    default:
                        fatalError("Unexpected graph type selection: \(selectedIndex)")
                    }
                    self.updateTs = nil
                    
                    return Tick()
                }
                self.present(editorVC, animated: true)
            default:
                LOGGER.debug("Unhandled selection on first section at \(indexPath)")
                break
            }
        case 1:
            if isProjectConfigged() {
                switch self.peripheral?.projectMode ?? "" {
                case MWV_PPG_V2:
                    handleSelectOnPpg(peripheral, indexPath)
                default:
                    LOGGER.error("Unhandled selection at \(indexPath)")
                }
            } else {
                LOGGER.debug("Unhandled selection at \(indexPath)")
            }
        default:
            LOGGER.debug("Unhandled selection at \(indexPath)")
            break
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let peripheral = self.peripheral else {
            LOGGER.error("No peripheral to use to populate inspect data")
            self.dismiss(animated: true)
            return tableView.dequeueReusableCell(withIdentifier: "controlcell0")!
        }
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "controlcell0") as! ControlCell
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Turn Off Sensor"
                cell.detailTextLabel?.text = ""
            case 1:
                cell.textLabel?.text = "Battery Level"
                switch peripheral.projectMode ?? "" {
                case OXIMETER_V0:
                    cell.detailTextLabel?.text = peripheral.batteryLevel == nil ? "??%" : "\(peripheral.batteryLevel!)mV"
                default:
                    cell.detailTextLabel?.text = peripheral.batteryLevel == nil ? "??%" : "\(peripheral.batteryLevel!)%"
                }
            case 2:
                if let measurementState = self.peripheral?.activeMeasurement?.state {
                    switch measurementState {
                    case .initial:
                        cell.textLabel?.text = "Start"
                        cell.detailTextLabel?.text = ""
                    case .paused:
                        cell.textLabel?.text = "Resume"
                        cell.detailTextLabel?.text = ""
                    case .running:
                        cell.textLabel?.text = "Pause"
                        if let activeSet = self.peripheral?.activeMeasurement?.dataSets.last! as? RamDataSet {
                            cell.detailTextLabel?.text = activeSet.getReadableDataRate()
                        }
                    case .ended:
                        cell.textLabel?.text = "... Measurement already ended ..."
                        cell.detailTextLabel?.text = ""
                    }
                } else {
                    cell.textLabel?.text = "Start"
                    cell.detailTextLabel?.text = ""
                }
            case 3:
                cell.textLabel?.text = "End"
                cell.detailTextLabel?.text = nil
            case 4:
                var measurement = peripheral.activeMeasurement
                if measurement == nil {
                    measurement = peripheral.finalizedMeasurements.last
                }
                if let dataSets =  measurement?.dataSets,
                   let activeSet = dataSets.last! as? RamDataSet {
                    // Assume 3x compression across all datasets in the final archive
                    // Active RAM usage is limited to the active data set size
                    let multiplier = Double(dataSets.count) * 0.33
                    cell.detailTextLabel?.text = activeSet.getReadableDataSize(multiplier: multiplier)
                } else {
                    cell.detailTextLabel?.text = ""
                }
                
                cell.textLabel?.text = "Pause, Save, Export"
            case 5:
                cell.textLabel?.text = "Graph Type"
                switch graphType {
                case .trailing_5:
                    cell.detailTextLabel?.text = "Trailing 5s"
                case .trailing_15:
                    cell.detailTextLabel?.text = "Trailing 15s"
                case .trailing_30:
                    cell.detailTextLabel?.text = "Trailing 30s"
                case .trailing_60:
                    cell.detailTextLabel?.text = "Trailing 60s"
                case .trailing_120:
                    cell.detailTextLabel?.text = "Trailing 120s"
                case .downsampled:
                    cell.detailTextLabel?.text = "Downsample from All"
                }
            default:
                break
            }
            return cell
        default:
            let isConfigged = isProjectConfigged()
            if isConfigged && indexPath.section == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "controlcell0", for: indexPath) as! ControlCell
                switch self.peripheral?.projectMode ?? "" {
                case MWV_PPG_V2:
                    let project = peripheral.getOrDefaultProject()
                    let opMode = project.mwv_ppg_v2_modes[project.defaultMode ?? ""] ?? MwvPpgV2ModeCodableState()
                    switch indexPath.row {
                    case 0: // Mode
                        cell.textLabel?.text = "Mode"
                        cell.detailTextLabel?.text = opMode.mode ?? "---"
                    case 1:
                        cell.textLabel?.text = "Step time (ATIME)"
                        let atime = opMode.atime == nil ? "---" : "\(opMode.atime!)"
                        cell.detailTextLabel?.text = "\(atime) (2.78us cycles)"
                    case 2:
                        cell.textLabel?.text = "Integration steps (ASTEP)"
                        let astep = opMode.astep == nil ? "---" : "\(opMode.astep!)"
                        cell.detailTextLabel?.text = "\(astep) steps"
                    case 3:
                        cell.textLabel?.text = "Gain (AGAIN)"
                        let again = opMode.again == nil ? "---" : "\(String.init(format: "%.1f", pow(Float(2), Float(opMode.again! - 1))))"
                        cell.detailTextLabel?.text = "\(again)x"
                    case 4:
                        cell.textLabel?.text = "Sample Period (WTIME)"
                        let wtime = opMode.wcycles == nil ? "---" : String.init(format: "%.1f", 2.78 * Float(opMode.wcycles! + 1))
                        cell.detailTextLabel?.text = "\(wtime) ms"
                    case 5:
                        cell.textLabel?.text = "LED Drive"
                        let drive = opMode.drive == nil ? "---" : "\((4 + (opMode.drive! * 2)))"
                        cell.detailTextLabel?.text = "\(drive) mA"
                    case 6:
                        cell.textLabel?.text = "Apply"
                        cell.detailTextLabel?.text = ""
                    default:
                        LOGGER.error("Unhandled row")
                        break
                    }
                default:
                    LOGGER.error("Unhandled section")
                }
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "channelcell0", for: indexPath) as! ChannelCell
                guard let data = self.graphData else {
                    cell.chartView.data = nil
                    return cell
                }
                
                let channelSection = indexPath.section - 1 - (isConfigged ? 1 : 0)
                if data.timestamps.count == 0 || data.channels.count == 0 || data.channels[0].count == 0 || channelSection >= data.channels.count {
                    // This can happen when new payloads make it so that the buffer for data to export for graphing are too small
                    LOGGER.debug("No data to graph for \(channelSection): \(data.timestamps.count), \(data.channels.count) \(channelSection)")
                    return cell
                }

                cell.timestamps = data.timestamps
                cell.channel = data.channels[channelSection]
                LOGGER.trace("Updating channel \(channelSection) with [\(cell.timestamps.count), \(cell.channel.count)] values")
                cell.dataLabel = "SAADC Samples (mV)"
                cell.colorIndex = indexPath.section
                cell.chartView.delegate = cell
                cell.updateChartView()
                return cell
            }
        }
    }
    
    private func handleSelectOnPpg(_ peripheral: QSPeripheral, _ indexPath: IndexPath) {
        LOGGER.trace("Handling select on \(indexPath) for ppg")
        
        
        let project = peripheral.getOrDefaultProject()
        
        switch indexPath.row {
        case 0:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "Operational Mode"
            editorVC.options = ["IDLE", "MODE 0", "MODE 1", "MODE 2", "MODE 3"]
            editorVC.confirmedValue = editorVC.options.firstIndex(of: project.defaultMode ?? "") ?? 0
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                let selection = editorVC.options[selectedIndex]
                LOGGER.debug("Selected mode \(selection)")
                project.defaultMode = selection
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 1:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "Step time (ATIME)"
            editorVC.options = (0...UINT8_MAX).map { "\($0)" }
            editorVC.confirmedValue = project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.atime ?? 0
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                LOGGER.debug("Selected atime \(selectedIndex)")
                project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.atime = selectedIndex
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 2:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "Integration steps (ASTEP)"
            editorVC.options = (0...UINT16_MAX).map { "\($0)" }
            editorVC.confirmedValue = project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.astep ?? 0
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                LOGGER.debug("Selected atime \(selectedIndex)")
                project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.astep = selectedIndex
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 3:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "Gain (AGAIN)"
            editorVC.options = (0...10).map { i in
                let gainStr: String = String.init(format: "%.1f", pow(Float(2), Float(i - 1)))
                return "\(gainStr)x"
            }
            editorVC.confirmedValue = project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.again ?? 0
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                LOGGER.debug("Selected again \(editorVC.options[selectedIndex])")
                project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.again = selectedIndex
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 4:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "WTIME (1000 ms / Sample Hz)"
            editorVC.detailLabelText = "(WTIME = 2.78ms * WCYCLES) >= (ASTEP + 1) * (ATIME + 1) * 2.78us"
            var firstOption = 255
            editorVC.options = (0...255).filter { (i) in
                guard let mode = project.mwv_ppg_v2_modes[project.defaultMode ?? ""] else {
                    return false
                }
                let wtime = 2.78 * Float(i + 1) * 1000
                let min_wtime = Float(mode.atime ?? 0 + 1) * Float(mode.astep ?? 0 + 1) * 2.78
                if wtime >= min_wtime {
                    if i < firstOption {
                        firstOption = i
                    }
                    return true
                } else {
                    return false
                }
            }.map { i in
                let waitStr: String = String.init(format: "%.1f", 2.78 * Float(i + 1))
                return "\(waitStr) ms"
            }
            if let wcycles = project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.wcycles {
                editorVC.confirmedValue = wcycles - firstOption + 1
            } else {
                editorVC.confirmedValue =  0
            }
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                LOGGER.debug("Selected wtime \(editorVC.options[selectedIndex])")
                project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.wcycles = firstOption + selectedIndex
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 5:
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let editorVC = storyboard.instantiateViewController(identifier: "pickerAttributeEditorVC") as! pickerAttributeEditorVC
            editorVC.headerLabelText = "LED Drive"
            editorVC.options = (0...255).map { i in
                return "\(4 + (i * 2)) mA"
            }
            editorVC.confirmedValue = project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.drive ?? 0
            editorVC.proposedValue = editorVC.confirmedValue
            editorVC.predicate = { (i) in return true }
            editorVC.actionFactory = { selectedIndex in
                LOGGER.debug("Selected led drive \(editorVC.options[selectedIndex])")
                project.mwv_ppg_v2_modes[project.defaultMode ?? ""]?.drive = selectedIndex
                peripheral.save()
                return QsibTick()
            }
            self.present(editorVC, animated: true)
        case 6:
            guard let mode = peripheral.projectMode else {
                LOGGER.error("Cannot apply alteration to unknown project mode")
                return
            }
            LOGGER.debug("Selected apply project mode on \(mode)")
            QSIB_ACTION_DISPATCH(action: IssueControlWriteFor(peripheral: peripheral.cbp, projectMode: mode))

        default:
            LOGGER.error("Unhandled row selection for \(MWV_PPG_V2) on \(indexPath)")
        }
    }
}
