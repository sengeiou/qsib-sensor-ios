//
//  DevicesTableVC.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import Foundation
import UIKit
import CoreBluetooth


class AdvertisementTableViewCell: UITableViewCell {
    @IBOutlet weak var signalImage: UIImageView!
    @IBOutlet weak var rssiLabel: UILabel!
    @IBOutlet weak var peripheralNameLabel: UILabel!
    @IBOutlet weak var attributeNameLabel: UILabel!
    @IBOutlet weak var attributeValueLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    
    var peripheral: String? = nil
    
    @IBAction func handleClick(_ sender: Any) {
        print("Click \(String(describing: peripheral))")
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


class DevicesTableVC: UITableViewController {
    
    let peripherals: [String] = ["Fake Peripheral"]

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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripherals.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "custom_cell0", for: indexPath)
        let advertisementCell = cell as! AdvertisementTableViewCell
        advertisementCell.peripheral = peripherals[indexPath.row]
        advertisementCell.peripheralNameLabel.text = advertisementCell.peripheral
        advertisementCell.connectButton.setTitleColor(.systemGray, for: .highlighted)
        return cell
    }
}
