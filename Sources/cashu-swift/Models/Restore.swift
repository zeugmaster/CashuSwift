//
//  File.swift
//  
//
//  Created by zm on 19.08.24.
//

import Foundation

extension CashuSwift {
    struct RestoreRequest: Codable {
        let outputs:[Output]
    }

    struct RestoreResponse: Codable {
        let outputs:[Output]
        let signatures:[Promise]
    }

    /// Result of a keyset restoration operation.
    public struct KeysetRestoreResult: Sendable {
        /// The keyset ID that was restored.
        public let keysetID: String
        
        /// The derivation counter for deterministic generation.
        public let derivationCounter: Int
        
        /// The unit string for this keyset.
        public let unitString: String
        
        /// The restored proofs.
        public let proofs: [Proof]
        
        /// The input fee in parts per thousand.
        public let inputFeePPK: Int
    }
}
