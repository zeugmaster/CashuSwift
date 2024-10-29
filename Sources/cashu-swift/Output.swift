//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

extension CashuSwift {
    // AKA BlindedMessage
    public struct Output: Codable {
        public let amount: Int
        public let B_: String
        public let id: String
    }

    // AKA BlindedSignature
    public struct Promise: Codable {
        public let id: String
        public let amount: Int
        public let C_: String
    }
}
