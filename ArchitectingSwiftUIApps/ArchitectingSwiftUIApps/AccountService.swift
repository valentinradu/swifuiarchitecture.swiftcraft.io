//
//  IdentityService.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 15/03/2022.
//

import Foundation

public struct AccountStore: Store {
    var id: String
    var username: String
    var email: String
}

public enum AccountMutation: Action {
    public func reduce(error: Error) -> AccountMutation {
        .error(error)
    }
    
    case login
    case error(Error)
}
