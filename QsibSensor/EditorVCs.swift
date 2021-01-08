//
//  EditorVCs.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 1/8/21.
//


import UIKit
import CoreBluetooth
import Foundation
import NIO
import AsyncHTTPClient
import Toast
import Logging
import ReSwift

class textAttributeEditorVC: UIViewController {
    var headerLabelText: String!
    var placeholderValue: String!
    var confirmedValue: String!
    var proposedValue: String!
    var predicate: ((String) -> Bool)!
    var actionFactory: ((String) -> Action)!
    
    
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var confirmButton: UIButton!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.headerLabel.text = headerLabelText
        self.textField.placeholder = placeholderValue
        self.textField.text = proposedValue
        
        self.textField.addDoneCancelToolbar()
    }
    
    @IBAction func handleValueChanged(_ sender: Any) {
        self.proposedValue = textField.text
        self.confirmButton.isEnabled = self.proposedValue != self.confirmedValue && self.predicate(self.proposedValue)
    }
    
    @IBAction func handleClickedCancel(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBAction func handleClickedConfirm(_ sender: Any) {
        self.proposedValue = textField.text
        self.confirmButton.isEnabled = self.proposedValue != self.confirmedValue && self.predicate(self.proposedValue)
        if self.confirmButton.isEnabled {
            QSIB_ACTION_DISPATCH(action: self.actionFactory(self.proposedValue))
            self.dismiss(animated: true)
        }
    }
}

class pickerAttributeEditorVC: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {
    var headerLabelText: String!
    var detailLabelText: String?
    var options: [String]!
    var confirmedValue: Int?
    var proposedValue: Int!
    var predicate: ((Int) -> Bool)!
    var actionFactory: ((Int) -> Action)!
    
    
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    @IBOutlet weak var valuePicker: UIPickerView!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var confirmButton: UIButton!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.headerLabel.text = headerLabelText
        self.detailLabel.text = detailLabelText
        self.valuePicker.delegate = self
        self.valuePicker.dataSource = self
        self.valuePicker.selectRow(proposedValue, inComponent: 0, animated: true)
    }
        
    @IBAction func handleClickedCancel(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBAction func handleClickedConfirm(_ sender: Any) {
        self.proposedValue = self.valuePicker.selectedRow(inComponent: 0)
        self.confirmButton.isEnabled = self.proposedValue != self.confirmedValue && self.predicate(self.proposedValue)
        if self.confirmButton.isEnabled {
            QSIB_ACTION_DISPATCH(action: self.actionFactory(self.proposedValue))
            self.dismiss(animated: true)
        }
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        options.count
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.proposedValue = row
        self.confirmButton.isEnabled = self.proposedValue != self.confirmedValue && self.predicate(self.proposedValue)
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        options[row]
    }
}
