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

public enum OtherAction: Action {
    public func transform(error: Error) -> OtherAction {
        return self
    }

    case some
}

public struct AccountEnvironment {}

struct AccountService {
    func bootstrap() async {
        let store = Store(AccountState(id: "", username: "", email: ""))
        let environment = AccountEnvironment()
        let service = Service(environment: environment, store: store)
        await service.add(reducer: AccountService.reduce)
        await service.add(reducer: AccountService.reduce2)
        await service.add(pre: AccountService.pre)
        await service.add(post: AccountService.post)
    }

    static func reduce(state: inout AccountState, action: AccountAction) -> SideEffect<AccountEnvironment> {
        SideEffect { _, _ in
        }
    }

    static func reduce2(state: inout AccountState, action: OtherAction) -> SideEffect<AccountEnvironment> {
        SideEffect { _, _ in
        }
    }
    
    static func pre(state: AccountState, action: AccountAction) -> Action {
        return OtherAction.some
    }
    
    static func post(state: AccountState, action: OtherAction) {
    }
}
