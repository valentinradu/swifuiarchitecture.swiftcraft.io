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

public struct OldSideEffect<D> {
    public typealias Operation = (Dispatcher, D) async throws -> Void
    private let _operation: Operation?
    public static var noop: OldSideEffect<D> { OldSideEffect<D>() }

    public init(_ operation: @escaping Operation) {
        _operation = operation
    }

    private init() {
        _operation = nil
    }

    fileprivate var hasOperation: Bool {
        _operation != nil
    }

    fileprivate func callAsFunction(_ dispatcher: Dispatcher, dependencies: D) async throws {
        guard let operation = _operation else {
            assertionFailure()
            return
        }
        try await operation(dispatcher, dependencies)
    }
}

private struct AnyReducer {
    typealias Operation = (Dispatcher) async throws -> Void
    private let _reduce: (Action) -> Operation?

    init<S, D, A>(store: Store<S>,
                  dependencies: D,
                  reducer: @escaping (inout S, A) -> OldSideEffect<D>)
    {
        _reduce = { action in
            if let action = action as? A {
                let sideEffect = reducer(&store.state, action)
                if sideEffect.hasOperation {
                    return {
                        try await sideEffect($0, dependencies: dependencies)
                    }
                }
            }
            return nil
        }
    }

    func mutate<A: Action>(action: A) -> Operation? {
        _reduce(action)
    }
}

public protocol OldService {
    typealias Reducer = (inout S, A) -> OldSideEffect<D>
    associatedtype S
    associatedtype A: Action
    associatedtype D
    func bootstrap() async -> ServiceBootstrap<S, A, D>
}

public struct ServiceBootstrap<S, A, D> where A: Action {
    typealias Reducer = (inout S, A) -> OldSideEffect<D>
    let state: S
    let dependencies: D
    let reducers: [Reducer]
}

public class UnregisterToken<T> {
    private let _closure: () async -> Void
    public init(_ closure: @escaping () async -> Void) {
        _closure = closure
    }

    deinit {
        Task { [_closure] in
            await _closure()
        }
    }
}

public actor Dispatcher {
    private var _reducers: [UUID: AnyReducer] = [:]

    public func register<T: OldService>(service: T) async -> UnregisterToken<T> {
        let bootstrap = await service.bootstrap()
        var uuids: Set<UUID> = []
        for reducer in bootstrap.reducers {
            let uuid = UUID()
            let reducer = AnyReducer(store: Store(bootstrap.state),
                                     dependencies: bootstrap.dependencies,
                                     reducer: reducer)

            _reducers[uuid] = reducer
            uuids.insert(uuid)
        }

        return UnregisterToken { [weak self, uuids] in
            await self?.removeServices(uuids: uuids)
        }
    }

    private func removeServices(uuids: Set<UUID>) {
        for uuid in uuids {
            _reducers.removeValue(forKey: uuid)
        }
    }

    public func mutate<M>(_ action: M) where M: Action {
        var sideEffects: [AnyReducer.Operation] = []
        for reducer in _reducers.values {
            if let sideEffect = reducer.mutate(action: action) {
                sideEffects.append(sideEffect)
            }
        }

        Task { [sideEffects] in
            for sideEffect in sideEffects {
                do {
                    try await sideEffect(self)
                } catch {
                    mutate(action.transform(error: error))
                }
            }
        }
    }
}

// -------------------------------------------------------------------------

public class Store<State> {
    fileprivate var state: State

    public init(_ state: State) {
        self.state = state
    }
}

public enum SideEffect<E> {
    public typealias Operation = (Dispatcher, E) async throws -> Void
    case noop
    case sideEffects(Operation, E)
}

public protocol Service {}

public struct EmptyService: Service {
    public func add<E>(environment: E) -> EnvironmentService<E> {
        EnvironmentService(environment: environment)
    }

    public func add<S>(initialState: S) -> StatefulService<S> {
        StatefulService(initialState: initialState)
    }
}

public struct EnvironmentService<E>: Service {
    private var _environment: E

    public init(environment: E) {
        _environment = environment
    }

    public func add<S>(initialState: S) -> StatefulEnvironmentService<S, E> {
        StatefulEnvironmentService(initialState: initialState, environment: _environment)
    }
}

public struct StatefulService<S>: Service {
    private var _initialState: S

    public init(initialState: S) {
        _initialState = initialState
    }

    public func add<E>(environment: E) -> StatefulEnvironmentService<S, E> {
        StatefulEnvironmentService(initialState: _initialState, environment: environment)
    }

    public func add<A>(reducer: @escaping (inout S, A) -> SideEffect<Never>) -> StatefulReducerService<S, A> where A: Action {
        StatefulReducerService(initialState: _initialState, reducer: reducer)
    }
}

public struct FullService<S, E, A>: Service {
    public typealias Reducer = (inout S, A) -> SideEffect<E>
    private let _initialState: S
    private let _environment: E
    private let _reducer: Reducer

    public init(initialState: S, environment: E, reducer: @escaping Reducer) {
        _initialState = initialState
        _environment = environment
        _reducer = reducer
    }
}

public struct StatefulEnvironmentService<S, E>: Service {
    private let _initialState: S
    private let _environment: E

    public init(initialState: S, environment: E) {
        _initialState = initialState
        _environment = environment
    }

    public func add<A>(reducer: @escaping (inout S, A) -> SideEffect<E>) -> FullService<S, E, A> where A: Action {
        FullService(initialState: _initialState, environment: _environment, reducer: reducer)
    }
}

public struct StatefulReducerService<S, A>: Service where A: Action {
    public typealias Reducer = (inout S, A) -> SideEffect<Never>
    private let _initialState: S
    private let _reducer: Reducer

    public init(initialState: S, reducer: @escaping Reducer) {
        _initialState = initialState
        _reducer = reducer
    }
}

public struct ServiceBuilder {
    public func createService() -> EmptyService {
        EmptyService()
    }

    func text() {
        createService()
            .add(initialState: AccountState(id: "", username: "", email: ""))
            .add(reducer: { (_: inout AccountState, _: AccountAction) -> SideEffect in
                .noop
            })
    }
}
