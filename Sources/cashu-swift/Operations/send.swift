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
    
    /// Creates a token from the provided proofs.
    ///
    /// This function allows a wallet to send proofs of type `Proof`, determining correct split for optional target amounts.
    ///
    /// - Parameters:
    ///   - inputs: List of input proofs to send
    ///   - mint: The mint for this operation (must be where inputs originated)
    ///   - amount: Optional amount to send. If omitted, all inputs will be sent
    ///   - seed: Optional seed for deterministic secret generation. If `lockToPublicKey` is present, only change will be deterministic
    ///   - memo: Optional memo to include in the token
    ///   - lockToPublicKey: Optional Schnorr public key in compressed 33-byte format to lock the token to
    ///
    /// - Returns: A tuple containing:
    ///   - token: The created Cashu token
    ///   - change: Array of proof objects representing the change
    ///   - outputDLEQ: DLEQ verification result for newly created ecash
    /// - Throws: An error if the operation fails
    public static func send(inputs: [Proof],
                            mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            memo: String? = nil,
                            lockToPublicKey: String? = nil) async throws -> (token: Token,
                                                                             change: [Proof],
                                                                             outputDLEQ: Crypto.DLEQVerificationResult,
                                                                             counterIncrease: (keysetID: String, increase: Int)?) {
        let proofSum = sum(inputs)
        let inputFee = try calculateFee(for: inputs, of: mint)
        
        // Validate amount is either nil or positive
        if let amount = amount, amount <= 0 {
            throw CashuError.invalidAmount
        }
        
        let units = try units(for: inputs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("Input proofs have mixed units, which is not allowed.")
        }
        
        let unit = units.first ?? "sat"
        
        guard let activeKeyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit(unit)
        }
        
        // make sure inputs do not have spending condition
        for p in inputs {
            guard SpendingCondition.deserialize(from: p.secret) == nil else {
                throw CashuError.spendingConditionError(".send() function does not yet support locked inputs.")
            }
        }
        
        if (proofSum == amount ?? proofSum) && lockToPublicKey == nil {
            return (Token(proofs: [mint.url.absoluteString: inputs],
                          unit: unit,
                          memo: memo), [], .valid, nil)
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
        
        var increase = seed != nil ? keepOutputSets.outputs.count : 0
        if lockToPublicKey == nil && seed != nil {
            increase += sendOutputSets.outputs.count
        }
        
        let swapResult = try await swap(inputs: inputs,
                                        with: mint,
                                        sendOutputs: sendOutputSets,
                                        keepOutputs: keepOutputSets)
        
        let token = Token(proofs: [mint.url.absoluteString: swapResult.send],
                          unit: unit,
                          memo: memo)
        
        return (token, swapResult.keep, swapResult.outputDLEQ, (activeKeyset.keysetID, increase))
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
