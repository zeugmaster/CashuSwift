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

    public struct KeysetRestoreResult {
        public let keysetID: String
        public let derivationCounter: Int
        public let unitString: String
        public let proofs: [ProofRepresenting]
        public let inputFeePPK: Int
    }
}
