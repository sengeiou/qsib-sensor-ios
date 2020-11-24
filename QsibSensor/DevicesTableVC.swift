//
//  DevicesTableVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import Foundation
import UIKit
import CoreBluetooth
import Toast
import ReSwift


class AdvertisementTableViewCell: UITableViewCell {
    @IBOutlet weak var signalImage: UIImageView!
    @IBOutlet weak var rssiLabel: UILabel!
    @IBOutlet weak var peripheralNameLabel: UILabel!
    @IBOutlet weak var attributeNameLabel: UILabel!
    @IBOutlet weak var attributeValueLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    
    var peripheral: QSPeripheral? = nil
    var viewController: DevicesTableVC!
    
    @IBAction func handleClick(_ sender: Any) {
        switch self.peripheral?.cbp.state {
        case .connected, .connecting:
            ACTION_DISPATCH(action: AppendToast(message: ToastMessage(message: "Disconnecting from \(self.peripheral!.name!) ...", duration: TimeInterval(2), position: .center, title: nil, image: nil, style: ToastStyle(), completion: nil)))
            
            ACTION_DISPATCH(action: RequestDisconnect(peripheral: self.peripheral!.cbp))
        default:
            ACTION_DISPATCH(action: AppendToast(message: ToastMessage(message: "Connecting to \(self.peripheral!.name!) ...", duration: TimeInterval(2), position: .center, title: nil, image: nil, style: ToastStyle(), completion: nil)))
            
            ACTION_DISPATCH(action: RequestConnect(peripheral: self.peripheral!.cbp))
            
            viewController.performSegue(withIdentifier: "activeDeviceSegue", sender: viewController)
        }
    }
    
    public func updateContent(forPeripheral newPeripheral: QSPeripheral) {
        self.peripheral = newPeripheral
        self.peripheralNameLabel.text = newPeripheral.name
        var tintColor = UIColor.systemRed
        var rssiLabelText = "RSSI: --- dBm"
        if let rssi = newPeripheral.displayRssi() {
            rssiLabelText = "RSSI: \(rssi) dBm"
            tintColor = rssi > -70 ? .systemBlue : .systemYellow
        }
        
        var connectButtonText = "Connect"
        var connectButtonColor = UIColor.systemTeal
        switch newPeripheral.cbp.state {
        case .connected, .connecting:
            tintColor = .systemGreen
            rssiLabelText = "RSSI: --- dBm"
            connectButtonText = "Disconnect"
            connectButtonColor = .systemOrange
        default:
            break
        }
        self.signalImage.tintColor = tintColor
        self.rssiLabel.text = rssiLabelText
        self.connectButton.setTitleColor(.systemGray, for: .highlighted)
        self.connectButton.setTitle(connectButtonText, for: .normal)
        self.connectButton.setTitle(connectButtonText, for: .selected)
        self.connectButton.backgroundColor = connectButtonColor
    }
}

class DevicesTable: UITableView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view.isKind(of: UIButton.self) {
            return true
        }
        return super.touchesShouldCancel(in: view)
    }
}


class DevicesTableVC: UITableViewController, StoreSubscriber {
    
    var peripherals: [QSPeripheral] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.allowsSelection = false
        tableView.delaysContentTouches = false
        
        for view in tableView.subviews {
            if view.isKind(of: UIScrollView.self) {
                (view as! UIScrollView).delaysContentTouches = false
            }
        }
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
        let peripherals = state.peripherals
            .values
            .sorted(by: { $0.name < $1.name })
        
        DispatchQueue.main.async {
//            var reloadRequired = self.peripherals.count != peripherals.count
//            for (index, (old, new)) in zip(self.peripherals, peripherals).enumerated() {
//                if old.id() == new.id() {
//                    if let deviceCell = self.tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? AdvertisementTableViewCell {
//                        deviceCell.updateContent(forPeripheral: new)
//                    }
//                } else {
//                    reloadRequired = true
//                }
//            }
            
            self.peripherals = peripherals
            self.tableView.reloadData()
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "custom_cell0", for: indexPath)
        let advertisementCell = cell as! AdvertisementTableViewCell
        advertisementCell.viewController = self
        advertisementCell.updateContent(forPeripheral: peripherals[indexPath.row])
        return cell
    }
}
