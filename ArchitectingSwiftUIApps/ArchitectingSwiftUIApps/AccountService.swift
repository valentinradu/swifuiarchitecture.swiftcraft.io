//
//  IdentityService.swift
//  ArchitectingSwiftUIApps
//
//  Created by Valentin Radu on 15/03/2022.
//

import Foundation

public struct AccountStore {
    var id: String
    var username: String
    var email: String
}

public enum AccountMutation: Mutation {
    public func reduce(error: Error) -> AccountMutation {
        .error(error)
    }
    
    case login
    case error(Error)
}

