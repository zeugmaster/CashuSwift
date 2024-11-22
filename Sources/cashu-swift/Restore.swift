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
        let keysetID: String
        let derivationCounter: Int
        let unitString: String
        let proofs: [ProofRepresenting]
    }
}
