//
//  Dispatcher.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 14/03/2022.
//

import Foundation

public protocol Mutation {
    func reduce(error: Error) -> Self
}

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

public class Service<M, S> where M: Mutation {
    public typealias Reducer = (inout S, M) -> SideEffect
    private let _reducer: Reducer
    private var _state: S

    public init(_ initialState: S, reducer: @escaping Reducer) {
        _reducer = reducer
        _state = initialState
    }

    func perform(mutation: M) -> SideEffect {
        _reducer(&_state, mutation)
    }
}

public struct AnyService<M> {
    private var _perform: (M) -> SideEffect

    public init<S>(_ service: Service<M, S>) {
        _perform = service.perform
    }

    public func perform(mutation: M) -> SideEffect {
        _perform(mutation)
    }
}

public actor Dispatcher {
    private var _services: [ObjectIdentifier: Any] = [:]

    public func register<M, S>(service: Service<M, S>) {
        _services[ObjectIdentifier(service)] = AnyService(service)
    }

    public func unregister<M, S>(service: Service<M, S>) {
        _services.removeValue(forKey: ObjectIdentifier(service))
    }

    public func mutate<M>(_ action: M) where M: Mutation {
        var sideEffects: [SideEffect] = []
        for service in _services.values {
            guard let service = service as? AnyService<M> else {
                continue
            }
            let sideEffect = service.perform(mutation: action)
            if case .sideEffect = sideEffect {
                sideEffects.append(sideEffect)
            }
        }

        let finalSideEffects = sideEffects
        Task {
            var queue = finalSideEffects
            while !queue.isEmpty {
                let sideEffect = queue.removeLast()
                do {
                    try await sideEffect(self)
                } catch {
                    for service in _services.values {
                        guard let service = service as? AnyService<M> else {
                            continue
                        }
                        let sideEffect = service.perform(mutation: action.reduce(error: error))
                        if case .sideEffect = sideEffect {
                            queue.append(sideEffect)
                        }
                    }
                }
            }
        }
    }
}
