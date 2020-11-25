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
    
    var start: Date?
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
    
    var data: [(Double, Double)] = []
    var dataLabel: String! = nil
    var colorIndex: Int! = nil
    
    func updateChartView() {
        self.chartView.xAxis.removeAllLimitLines()
        self.chartView.leftAxis.removeAllLimitLines()
        self.chartView.rightAxis.removeAllLimitLines()
        
        var dataSets: [LineChartDataSet] = []
        for rawData in [data] {
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

class InspectDataVC: UITableViewController, StoreSubscriber {
    
    var peripheral: QSPeripheral?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.backgroundColor = UIColor.systemGroupedBackground
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

        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 5
        default:
            return 1
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + (self.peripheral?.signalChannels ?? 0)
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Control"
        default:
            return "Channel \(section - 1)"
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
            case 1:
                LOGGER.debug("Selected start measurement ...")
                ACTION_DISPATCH(action: StartMeasurement(peripheral: peripheral.cbp))
            case 2:
                LOGGER.debug("Selected stop measurement ...")
                ACTION_DISPATCH(action: StopMeasurement(peripheral: peripheral.cbp))

            default:
                LOGGER.debug("Unhandled selection on first section at \(indexPath)")
                break
            }
        default:
            LOGGER.debug("Unhandled selection at \(indexPath)")
            break
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let peripheral = self.peripheral else {
            LOGGER.error("No peripheral to use to populate inspect data")
            fatalError("No peripheral to use to populate inspect data")
        }
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "controlcell0") as! ControlCell
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Battery Level"
                cell.detailTextLabel?.text = peripheral.batteryLevel == nil ? "??%" : "\(peripheral.batteryLevel!)%"
            case 1:
                cell.textLabel?.text = "Start"
                cell.detailTextLabel?.text = cell.start?.getElapsedInterval()
            case 2:
                cell.textLabel?.text = "End"
                cell.detailTextLabel?.text = nil
            case 3:
                cell.textLabel?.text = "Save"
                cell.detailTextLabel?.text = "13MB"
            case 4:
                cell.textLabel?.text = "Export"
                cell.detailTextLabel?.text = nil
            default:
                break
            }
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "channelcell0", for: indexPath) as! ChannelCell
            guard let activeMeasurement = self.peripheral?.activeMeasurement else {
                cell.chartView.data = nil
                return cell
            }
            
            if indexPath.section - 1 > activeMeasurement.channels.count {
                LOGGER.error("Cannot populate data for channel that the active measurement is not configured to have")
                fatalError("Cannot populate data for channel that the active measurement is not configured to have")
            }

            cell.data = zip(activeMeasurement.graphableTime, activeMeasurement.graphableChannels[indexPath.section - 1]).map { $0 }
            cell.dataLabel = "SAADC Samples (mV)"
            cell.colorIndex = indexPath.section
            cell.chartView.delegate = cell
            cell.updateChartView()
            return cell
        }
    }
}
