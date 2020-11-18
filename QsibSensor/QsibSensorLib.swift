//
//  QsibSensorLib.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 11/18/20.
//

import Foundation

class QsibSensorLib {
    let initializer: Void = {
        rust_init();
        return ()
    }()
    
    func sayHello(to: String) -> String {
        let result = rust_greeting(to);
        let swift_result = String(cString: result!)
        rust_greeting_free(UnsafeMutablePointer(mutating: result))
        return swift_result
    }
}
