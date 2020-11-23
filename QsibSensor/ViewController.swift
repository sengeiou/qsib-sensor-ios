//
//  ViewController.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import UIKit
import ReSwift
import Toast

class ViewController: UIViewController, StoreSubscriber {
    
    var previousToast: UUID? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        let libInst = QsibSensorLib()
        print("Rust says \(libInst.sayHello(to: "Jacob"))")
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
        if state.toastQueue.count > 0 && state.toastQueue.first!.id != previousToast {
            let tm = state.toastQueue.first!
            previousToast = tm.id
            DispatchQueue.main.async {
                self.view.makeToast(tm.message, duration: tm.duration, position: tm.position, title: tm.title, image: tm.image, style: tm.style, completion: tm.completion)
            }
            ACTION_DISPATCH(action: ProcessToast())
        }
    }
    
}
