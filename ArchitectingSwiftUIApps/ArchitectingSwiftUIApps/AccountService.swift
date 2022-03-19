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
    public func reduce(error: Error) -> AccountAction {
        .error(error)
    }

    case login
    case error(Error)
}

public struct AccountDependencies {}

public func accountReducer(state: inout AccountState,
                           action: AccountAction) -> SideEffect<AccountDependencies>
{
    SideEffect { [state] dispatcher, dependencies in
        print(state.id)
    }
}
