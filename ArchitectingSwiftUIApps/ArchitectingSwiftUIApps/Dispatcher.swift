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

public struct SideEffect<D> {
    public typealias Operation = (Dispatcher, D) async throws -> Void
    private let _operation: Operation?
    public static var noop: SideEffect<D> { SideEffect<D>() }

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

private struct Service {
    typealias Operation = (Dispatcher) async throws -> Void
    private let _reduce: (Action) async -> Operation?

    init<S, D, A>(store: Store<S>,
                  dependencies: D,
                  reducer: @escaping (inout S, A) -> SideEffect<D>)
    {
        _reduce = { action in
            if let action = action as? A {
                var state = await store.state
                let sideEffect = reducer(&state, action)
                await store.update(state: state)
                if sideEffect.hasOperation {
                    return {
                        try await sideEffect($0, dependencies: dependencies)
                    }
                }
            }
            return nil
        }
    }

    func mutate<A: Action>(action: A) async -> Operation? {
        await _reduce(action)
    }
}

public actor Dispatcher {
    private var _services: [Service] = []

    public func register<S, D, A>(store: Store<S>,
                                  dependencies: D,
                                  reducer: @escaping (inout S, A) -> SideEffect<D>) where A: Action
    {
        let service = Service(store: store,
                              dependencies: dependencies,
                              reducer: reducer)
        _services.append(service)
    }

    public func mutate<M>(_ action: M) async where M: Action {
        var sideEffects: [Service.Operation] = []
        for service in _services {
            if let sideEffect = await service.mutate(action: action) {
                sideEffects.append(sideEffect)
            }
        }

        for sideEffect in sideEffects {
            do {
                try await sideEffect(self)
            } catch {
                await mutate(action.reduce(error: error))
            }
        }
    }
}
