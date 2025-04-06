//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

extension CashuSwift {
    // AKA BlindedMessage
    public struct Output: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case amount
            case B_ = "B_"
            case id
        }
        
        public let amount: Int
        public let B_: String
        public let id: String
    }

    // AKA BlindedSignature
    public struct Promise: Codable, Sendable {
        public let id: String
        public let amount: Int
        public let C_: String
    }
}
