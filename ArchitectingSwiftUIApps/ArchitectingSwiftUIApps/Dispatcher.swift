//
//  Dispatcher.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 14/03/2022.
//

import Foundation

public protocol Action {
    func reduce(error: Error) -> Self
}

public protocol Store {}

public enum SideEffect {
    public typealias Operation = (Dispatcher) async throws -> Void
    case noop
    case sideEffect(Operation)

    func callAsFunction(_ dispatcher: Dispatcher) async throws {
        switch self {
        case .noop:
            break
        case let .sideEffect(value):
            try await value(dispatcher)
        }
    }
}

public class Service<M, S> where M: Action, S: Store {
    public typealias Reducer = (inout S, M) -> SideEffect
    public private(set) var store: S

    private let _reducer: Reducer

    public init(_ initialState: S, reducer: @escaping Reducer) {
        _reducer = reducer
        store = initialState
    }

    func mutate(action: M) -> SideEffect {
        _reducer(&store, action)
    }
}

public struct AnyService: Hashable {
    private let _mutate: (Action) -> SideEffect
    private let id: ObjectIdentifier
    public let store: Store

    public init<M, S>(_ service: Service<M, S>) {
        _mutate = { action in
            if let action = action as? M {
                return service.mutate(action: action)
            }
            return .noop
        }
        store = service.store
        id = ObjectIdentifier(service)
    }

    public func mutate(action: Action) -> SideEffect {
        _mutate(action)
    }

    public static func == (lhs: AnyService, rhs: AnyService) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public class AnyObserver: Hashable {
    private let _receive: (Store) -> Void
    private let id: UUID

    public init<S>(_ receive: @escaping (S) -> Void) where S: Store {
        _receive = { store in
            if let store = store as? S {
                receive(store)
            }
        }
        id = UUID()
    }

    public func receive(store: Store) {
        _receive(store)
    }

    public static func == (lhs: AnyObserver, rhs: AnyObserver) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public class WatchToken {
    private let _closure: () -> Void
    public init(_ closure: @escaping () -> Void) {
        _closure = closure
    }

    deinit {
        _closure()
    }
}

public actor Dispatcher {
    private var _services: Set<AnyService> = []
    private var _observers: Set<AnyObserver> = []

    public func register<M, S>(service: Service<M, S>) {
        let service = AnyService(service)
        _services.insert(service)
    }

    public func unregister<M, S>(service: Service<M, S>) {
        let service = AnyService(service)
        _services.remove(service)
    }

    public func watch<S>(_ store: S.Type, receive: @escaping (S) -> Void) -> WatchToken where S: Store {
        let observer = AnyObserver(receive)
        _observers.insert(observer)

        return WatchToken {
            Task { [weak self] in
                await self?.unwatch(observer: observer)
            }
        }
    }

    private func unwatch(observer: AnyObserver) {
        _observers.remove(observer)
    }

    public func mutate<M>(_ action: M) where M: Action {
        var sideEffects: [SideEffect] = []
        for service in _services {
            let sideEffect = service.mutate(action: action)
            if case .sideEffect = sideEffect {
                sideEffects.append(sideEffect)
            }

            for observer in _observers {
                observer.receive(store: service.store)
            }
        }

        let finalSideEffects = sideEffects
        Task {
            for sideEffect in finalSideEffects {
                do {
                    try await sideEffect(self)
                } catch {
                    mutate(action.reduce(error: error))
                }
            }
        }
    }
}
