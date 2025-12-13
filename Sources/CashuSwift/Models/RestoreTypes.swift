//
//  File.swift
//  
//
//  Created by zm on 19.08.24.
//

import Foundation

extension CashuSwift {
    public struct RestoreRequest: Codable {
        public let outputs:[Output]
        
        public init(outputs: [Output]) {
            self.outputs = outputs
        }
    }

    public struct RestoreResponse: Codable {
        public let outputs:[Output]
        public let signatures:[Promise]
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
        
        public init(keysetID: String, derivationCounter: Int, unitString: String, proofs: [Proof], inputFeePPK: Int) {
            self.keysetID = keysetID
            self.derivationCounter = derivationCounter
            self.unitString = unitString
            self.proofs = proofs
            self.inputFeePPK = inputFeePPK
        }
    }
}
