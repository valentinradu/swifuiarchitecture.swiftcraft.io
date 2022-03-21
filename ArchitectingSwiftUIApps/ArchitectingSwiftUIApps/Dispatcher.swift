//
//  Dispatcher.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 14/03/2022.
//

import Foundation

public protocol Action {
    func transform(error: Error) -> Self
}

public actor Store<State>: ObservableObject {
    private var state: State

    public init(_ state: State) {
        self.state = state
    }

    public func update<T>(_ closure: (inout State) -> T) -> T {
        objectWillChange.send()
        return closure(&state)
    }
}

public enum SideEffect<E> {
    public typealias Operation = (Dispatcher, E) async throws -> Void
    case noop
    case sideEffects(Operation)

    public init(_ operation: @escaping Operation) {
        self = .sideEffects(operation)
    }
}

public enum ReducerResult<E> {
    case ignore
    case resolve(SideEffect<E>)
}

public struct Reducer<E, S> {
    public typealias Operation = (inout S, Action) -> ReducerResult<E>
    private let _operation: Operation
    public init<A>(_ operation: @escaping (inout S, A) -> SideEffect<E>) where A: Action {
        _operation = { state, action in
            if let action = action as? A {
                return .resolve(operation(&state, action))
            }
            return .ignore
        }
    }

    public func reduce(state: inout S, action: Action) -> ReducerResult<E> {
        _operation(&state, action)
    }
}

public actor Service<E, S>: StatefulReducer {
    private let _environment: E
    private let _store: Store<S>
    private var _reducers: [Reducer<E, S>]

    public init(environment: E, store: Store<S>) {
        _environment = environment
        _store = store
        _reducers = []
    }

    public func add<A>(reducer: @escaping (inout S, A) -> SideEffect<E>) where A: Action {
        _reducers.append(Reducer(reducer))
    }

    fileprivate func reduce(action: Action) async -> StatefulReducerResult {
        var sideEffects: [SideEffect<E>] = []
        for reducer in _reducers {
            let result = await _store.update { (state: inout S) -> ReducerResult<E> in
                reducer.reduce(state: &state, action: action)
            }

            switch result {
            case .ignore:
                continue
            case let .resolve(sideEffect):
                sideEffects.append(sideEffect)
            }
        }

        if !sideEffects.isEmpty {
            return .resolve { [weak self] dispatcher in
                for sideEffect in sideEffects {
                    if let self = self,
                       case let .sideEffects(operation) = sideEffect
                    {
                        try await operation(dispatcher, self._environment)
                    }
                }
            }
        } else {
            return .ignore
        }
    }
}

private enum StatefulReducerResult {
    typealias Resolver = (Dispatcher) async throws -> Void
    case ignore
    case resolve(Resolver)
}

private protocol StatefulReducer: AnyObject {
    func reduce(action: Action) async -> StatefulReducerResult
}

@MainActor
public class Dispatcher {
    private var _services: [ObjectIdentifier: StatefulReducer] = [:]

    public func register<E, S>(service: Service<E, S>) {
        let id = ObjectIdentifier(service)
        _services[id] = service
    }

    public func unregister<E, S>(service: Service<E, S>) {
        let id = ObjectIdentifier(service)
        _services.removeValue(forKey: id)
    }

    public func mutate<A>(action: A) where A: Action {
        Task {
            var resolvers: [StatefulReducerResult.Resolver] = []
            for service in _services.values {
                let result = await service.reduce(action: action)

                switch result {
                case .ignore:
                    continue
                case let .resolve(resolver):
                    resolvers.append(resolver)
                }
            }

            for resolver in resolvers {
                do {
                    try await resolver(self)
                } catch {
                    mutate(action: action.transform(error: error))
                }
            }
        }
    }
}
