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
    
    /// Send ecash
    ///
    /// Allows a wallet to send inputs of type `Proof`, determining correct split for optional target amounts
    ///
    ///  - Parameter inputs: List of input `Proofs`
    ///  - Parameter mint: The mint for this operation, needs to be where inputs originated
    ///  - Parameter amount: Optional amount to send/keep as change. If omitted all inputs will be go into the Token
    ///  - Parameter seed: Optional seed for NUT-13. If `lockToPublicKey` is present, only change will be deterministic (handle derivation counters accordingly)
    ///  - Parameter memo: Optional memo for the Token
    ///  - Parameter lockToPublicKey: Optional string representing a Schnorr public key in compressed 33-byte format
    ///
    /// - Returns: A Cashu Token, the change as an array of `Proof`s and the DLEQ verification result of newly created ecash
    public static func send(inputs: [Proof],
                            mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            memo: String? = nil,
                            lockToPublicKey: String? = nil) async throws -> (token: Token,
                                                                             change: [Proof],
                                                                             outputDLEQ: Crypto.DLEQVerificationResult) {
        let proofSum = sum(inputs)
        let inputFee = try calculateFee(for: inputs, of: mint)
        
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
        
        if (proofSum == amount ?? proofSum) && lockToPublicKey == nil {
            return (Token(proofs: [mint.url.absoluteString: inputs],
                          unit: unit,
                          memo: memo), [], .valid)
        }
        
        let split = try split(for: proofSum, target: amount, fee: inputFee)
        
        let keepOutputSets = try generateOutputs(distribution: splitIntoBase2Numbers(split.keepAmount),
                                                 mint: mint,
                                                 seed: seed,
                                                 unit: unit)
                
        let sendOutputSets = try lockToPublicKey.map { pubkey in
            try generateP2PKOutputs(for: split.sendAmount,
                                    mint: mint,
                                    publicKey: pubkey,
                                    unit: unit)
        } ?? generateOutputs(distribution: splitIntoBase2Numbers(split.sendAmount),
                             mint: mint,
                             seed: seed,
                             unit: unit,
                             offset: keepOutputSets.outputs.count) // MARK: need to increase detsec counter in function
        
        
        
        let swapResult = try await swap(inputs: inputs,
                                        with: mint,
                                        sendOutputs: sendOutputSets,
                                        keepOutputs: keepOutputSets)
        
        let token = Token(proofs: [mint.url.absoluteString: swapResult.send],
                          unit: unit,
                          memo: memo)
        
        return (token, swapResult.keep, swapResult.outputDLEQ)
    }
    
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
}
