//
//  IdentityService.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 15/03/2022.
//

import Foundation

public struct AccountState {
    var id: String
    var username: String
    var email: String
}

public enum AccountAction: Action {
    public func transform(error: Error) -> AccountAction {
        .error(error)
    }

    case login
    case error(Error)
}

public struct AccountDependencies {}

struct AccountService: Service {
    func initialState(dependencies: AccountDependencies) async -> AccountState {
        AccountState(id: "", username: "", email: "")
    }
    
    func dependencies() async -> AccountDependencies {
        AccountDependencies()
    }

    static func reduce(state: inout AccountState, action: AccountAction) -> OldSideEffect<AccountDependencies> {
        OldSideEffect { [state] _, _ in
            print(state.id)
        }
    }
}
