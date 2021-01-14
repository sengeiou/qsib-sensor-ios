//
//  UIStore.swift
//  QsibSensor
//
//  Created by Jacob Trueb on 1/13/21.
//

import Foundation
import ReSwift
import UIKit
import Toast

public struct UIState: StateType {
    var toastQueue: [ToastMessage] = []
    var isScanning: Bool = false
    
}

public struct ToastMessage {
    let id = UUID()
    var message: String? = nil
    var duration: TimeInterval = TimeInterval(3)
    var position: ToastPosition = .top
    var title: String? = nil
    var image: UIImage? = nil
    var style: ToastStyle = .init()
    var completion: ((Bool) -> Void)? = nil
}

public struct AppendToast: Action {
    let message: ToastMessage
}

public struct ProcessToast: Action {}

public struct Tick: Action {}

public struct SetIsScanning: Action {
    let isScanning: Bool
}

public func uiReducer(action: Action, state: UIState?) -> UIState {
    var state = state ?? UIState()
    
    switch action {
    case is Tick, is ReSwiftInit:
        break
    case let action as AppendToast:
        state.toastQueue.append(action.message)
    case _ as ProcessToast:
        if state.toastQueue.count > 0 {
            state.toastQueue.removeFirst()
        }
    case let action as SetIsScanning:
        state.isScanning = action.isScanning
    default:
        fatalError("Unhandled action for ui state \(action)")
    }
    
    return state
}

public let UI_STORE = Store<UIState>(reducer: uiReducer, state: nil)

public func UI_ACTION_DISPATCH(action: Action) {
    DISPATCH.execute {
        UI_STORE.dispatch(action)
    }
}

public func UI_TICK() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        UI_ACTION_DISPATCH(action: Tick())
        UI_TICK()
    }
}
