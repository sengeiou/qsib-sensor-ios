//
//  MainViewController.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import UIKit
import ReSwift
import Toast

class MainViewController: UIViewController, StoreSubscriber {
    
    var previousToast: UUID? = nil
    var cachedIsScanning = false
    
    
    @IBOutlet weak var scanButton: UIButton!
    
    @IBAction func toggleScan(_ sender: Any) {
        QSIB_ACTION_DISPATCH(action: SetScan(doScan: !cachedIsScanning))
    }
    

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UI_STORE.subscribe(self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UI_STORE.unsubscribe(self)
    }
    
    func newState(state: UIState) {
        if state.toastQueue.count > 0 && state.toastQueue.first!.id != previousToast {
            let tm = state.toastQueue.first!
            previousToast = tm.id
            DispatchQueue.main.async {
                self.view.makeToast(tm.message, duration: tm.duration, position: tm.position, title: tm.title, image: tm.image, style: tm.style, completion: tm.completion)
            }
            UI_ACTION_DISPATCH(action: ProcessToast())
        }
        
        cachedIsScanning = state.isScanning
        if cachedIsScanning {
            LOGGER.trace("Setting scan button label for scan on")
            DispatchQueue.main.async { self.scanButton.setTitle("Stop Scan", for: .normal) }
        } else {
            LOGGER.trace("Setting scan button label for scan off")
            DispatchQueue.main.async { self.scanButton.setTitle("Start Scan", for: .normal) }
        }
    }
}
