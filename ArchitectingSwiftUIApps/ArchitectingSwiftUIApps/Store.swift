//
//  Store.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 18/03/2022.
//

import Foundation

public actor Store<State> {
    public typealias Observer = (State) -> Void
    private var _observers: [UUID: Observer] = [:]
    internal private(set) var state: State

    public init(_ state: State) {
        self.state = state
    }

    public func watch(receive: @escaping Observer) -> WatchToken {
        let id = UUID()
        _observers[id] = receive

        return WatchToken { [weak self] in
            Task { [weak self] in
                await self?.unwatch(uuid: id)
            }
        }
    }

    internal func update(state: State) {
        self.state = state
        for observer in _observers.values {
            observer(state)
        }
    }

    private func unwatch(uuid: UUID) {
        _observers.removeValue(forKey: uuid)
    }
}

public class WatchToken {
    private let _closure: () -> Void
    public init(_ closure: @escaping () -> Void) {
        _closure = closure
    }

    public func unwatch() {
        _closure()
    }

    deinit {
        _closure()
    }
}
