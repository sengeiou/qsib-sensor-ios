//
//  ViewController.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        let libInst = QsibSensorLib()
        print("Rust says \(libInst.sayHello(to: "Jacob"))")
    }
}
