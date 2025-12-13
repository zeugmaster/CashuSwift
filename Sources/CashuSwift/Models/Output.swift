//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

extension CashuSwift {
    /// Represents a blinded message sent to the mint.
    public struct Output: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case amount
            case B_ = "B_"
            case id
        }
        
        /// The amount for this output.
        public let amount: Int
        
        /// The blinded message.
        public let B_: String
        
        /// The keyset ID this output uses.
        public let id: String
    }

    /// Represents a blinded signature from the mint.
    public struct Promise: Codable, Sendable {
        /// The keyset ID used.
        public let id: String
        
        /// The amount of this promise.
        public let amount: Int
        
        /// The blinded signature.
        public let C_: String
        
        /// Optional DLEQ proof for verification.
        public let dleq: DLEQ?
    }
    
    /// DLEQ (Discrete Logarithm Equality) proof for signature verification.
    public struct DLEQ: Codable, Sendable {
        /// The challenge value.
        public let e: String
        
        /// The response value.
        public let s: String
        
        /// Optional randomness value.
        public let r: String?
    }
}
