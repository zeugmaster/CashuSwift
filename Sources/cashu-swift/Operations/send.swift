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
    @available(*, deprecated)
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
    @available(*, deprecated)
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
    
    /// # send
    public static func send(inputs: [Proof],
                            mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            memo: String? = nil,
                            lockToPublicKey: String? = nil) async throws -> (token: Token,
                                                                             change: [Proof],
                                                                             outputDLEQ: Crypto.DLEQVerificationResult) {
        let proofSum = sum(inputs)
        let amount = amount ?? proofSum
        
        guard amount > 0 else {
            throw CashuError.invalidAmount
        }
        
        guard amount <= proofSum else {
            throw CashuError.insufficientInputs("amount must not be larger than input proofs")
        }
        
        let units = try units(for: inputs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("Input proofs have mixed units, which is not allowed.")
        }
        let unit = units.first ?? "sat"
        
        // make sure inputs do not have spending condition
        for p in inputs {
            guard SpendingCondition.deserialize(from: p.secret) == nil else {
                throw CashuError.spendingConditionError(".send() function does not yet support locked inputs.")
            }
        }
        
        let keepOutputSets:(outputs: [Output], blindingFactors: [String], secrets: [String])
        let sendOutputSets:(outputs: [Output], blindingFactors: [String], secrets: [String])
        
        if let lockToPublicKey {
            sendOutputSets = try generateP2PKOutputs(for: amount,
                                                     mint: mint,
                                                     publicKey: lockToPublicKey)
        } else {
            if amount == proofSum {
                return (Token(proofs: [mint.url.absoluteString: inputs],
                              unit: unit,
                              memo: memo), [], .valid)
            } else {
                sendOutputSets = try generateOutputs(distribution: splitIntoBase2Numbers(amount),
                                                     mint: mint,
                                                     seed: seed,
                                                     unit: unit)
            }
        }
        
        keepOutputSets = try generateOutputs(distribution: splitIntoBase2Numbers(proofSum - amount),
                                             mint: mint,
                                             seed: seed,
                                             unit: unit)
        
        let swapResult = try await swap(inputs: inputs,
                                        with: mint,
                                        sendOutputs: sendOutputSets,
                                        keepOutputs: keepOutputSets)
        
        let token = Token(proofs: [mint.url.absoluteString: swapResult.send],
                          unit: unit,
                          memo: memo)
        
        return (token, swapResult.keep, swapResult.outputDLEQ)
    }
}
