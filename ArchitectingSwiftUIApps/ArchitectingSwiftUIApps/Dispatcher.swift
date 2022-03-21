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

public actor Store<State> {
    private var state: State

    public init(_ state: State) {
        self.state = state
    }

    public func update<T>(_ closure: (inout State) -> T) -> T {
        closure(&state)
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

public struct Reducer<E, S> {
    public typealias Operation = (inout S, Action) -> SideEffect<E>?
    private let _operation: Operation
    public init<A>(_ operation: @escaping (inout S, A) -> SideEffect<E>) where A: Action {
        _operation = { state, action in
            if let action = action as? A {
                return operation(&state, action)
            }
            return nil
        }
    }

    public func reduce(state: inout S, action: Action) -> SideEffect<E>? {
        _operation(&state, action)
    }
}

public struct Middleware<S> {
    public typealias PreOperation = (S, Action) -> Action?
    public typealias PostOperation = (S, Action) -> Void
    private let _pre: PreOperation?
    private let _post: PostOperation?
    public init<A>(pre: ((S, A) -> Action)?,
                   post: ((S, A) -> Void)?) where A: Action
    {
        _pre = { state, action in
            if let pre = pre,
               let action = action as? A
            {
                return pre(state, action)
            }
            return nil
        }

        _post = { state, action in
            if let post = post,
               let action = action as? A
            {
                post(state, action)
            }
        }
    }

    public func pre(state: S, action: Action) -> Action? {
        _pre?(state, action)
    }

    public func post(state: S, action: Action) {
        _post?(state, action)
    }
}

public actor Service<E, S>: StatefulReducer {
    private let _environment: E
    private let _store: Store<S>
    private var _reducers: [Reducer<E, S>]
    private var _middlewares: [Middleware<S>]

    public init(environment: E, store: Store<S>) {
        _environment = environment
        _store = store
        _reducers = []
        _middlewares = []
    }

    public func add<A>(reducer: @escaping (inout S, A) -> SideEffect<E>) where A: Action {
        _reducers.append(Reducer(reducer))
    }

    public func add<A>(pre: ((S, A) -> Action)? = nil,
                       post: ((S, A) -> Void)? = nil) where A: Action
    {
        _middlewares.append(Middleware(pre: pre, post: post))
    }

    fileprivate func reduce(action: Action) async -> SideEffectWrapper? {
        var sideEffects: [SideEffect<E>] = []
        for reducer in _reducers {
            let result = await _store.update {(state: inout S) -> SideEffect<E>? in
                var newState = state
                for middleware in _middlewares {
                    if let newAction = middleware.pre(state: state, action: action) {
                        await reduce(action: newAction)
                        return nil
                    }
                }
                let sideEffect = reducer.reduce(state: &state, action: action)
                for middleware in _middlewares {
                    middleware.post(state: state, action: action)
                }
                return sideEffect
            }

            if let sideEffect = result {
                sideEffects.append(sideEffect)
            }
        }

        if !sideEffects.isEmpty {
            return { [weak self] dispatcher in
                for sideEffect in sideEffects {
                    if let self = self,
                       case let .sideEffects(operation) = sideEffect
                    {
                        try await operation(dispatcher, self._environment)
                    }
                }
            }
        } else {
            return nil
        }
    }
}

private typealias SideEffectWrapper = (Dispatcher) async throws -> Void

private protocol StatefulReducer: AnyObject {
    func reduce(action: Action) async -> SideEffectWrapper?
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
            var sideEffects: [SideEffectWrapper] = []
            for service in _services.values {
                if let sideEffect = await service.reduce(action: action) {
                    sideEffects.append(sideEffect)
                }
            }

            for sideEffect in sideEffects {
                do {
                    try await sideEffect(self)
                } catch {
                    mutate(action: action.transform(error: error))
                }
            }
        }
    }
}
