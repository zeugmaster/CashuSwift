//
//  File.swift
//  CashuSwift
//
//  Created by zm on 07.04.25.
//

import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    public static func send(mint:MintRepresenting,
                            proofs:[ProofRepresenting],
                            amount:Int? = nil,
                            seed:String? = nil,
                            memo:String? = nil) async throws -> (token:Token,
                                                        change:[ProofRepresenting]) {
        
        let proofSum = sum(proofs)
        let amount = amount ?? proofSum
        
        guard amount <= proofSum else {
            throw CashuError.insufficientInputs("amount must not be larger than input proofs")
        }
        
        let sendProofs:[ProofRepresenting]
        let changeProofs:[ProofRepresenting]
        
        if proofSum == amount {
            sendProofs = proofs
            changeProofs = []
        } else {
            let (new, change) = try await swap(mint: mint, proofs: proofs, amount: amount, seed: seed)
            sendProofs = new
            changeProofs = change
        }
        
        let units = try units(for: sendProofs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("units needs to contain exactly ONE entry, more means multi unit, less means none found - no bueno")
        }
        
        let proofsPerMint = [mint.url.absoluteString: sendProofs]
        let token = Token(proofs: proofsPerMint,
                          unit: units.first ?? "sat",
                          memo: memo)
        
        return (token, changeProofs)
    }

    public static func send(mint: Mint,
                           proofs: [Proof],
                           amount: Int? = nil,
                           seed: String? = nil,
                           memo: String? = nil) async throws -> (token: Token, change: [Proof]) {
        let result = try await send(mint: mint as MintRepresenting,
                                   proofs: proofs as [ProofRepresenting],
                                   amount: amount,
                                   seed: seed,
                                   memo: memo)
        return (result.token, result.change as! [Proof])
    }
}
