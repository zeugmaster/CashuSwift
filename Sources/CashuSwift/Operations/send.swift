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
    /// - Returns: A `SendResult` containing the token, change proofs, DLEQ verification result, and counter increase info
    /// - Throws: An error if the operation fails
    public static func send(inputs: [Proof],
                            mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            memo: String? = nil,
                            lockToPublicKey: String? = nil) async throws -> SendResult {
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
            return SendResult(token: Token(proofs: [mint.url.absoluteString: inputs.withShortKeysetID()],
                                           unit: unit,
                                           memo: memo),
                              send: [],
                              change: [],
                              outputDLEQ: .valid,
                              counterIncrease: nil)
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
        
        let token = Token(proofs: [mint.url.absoluteString: swapResult.send.withShortKeysetID()],
                          unit: unit,
                          memo: memo)
        
        return SendResult(token: token,
                          send: swapResult.send,
                          change: swapResult.keep,
                          outputDLEQ: swapResult.outputDLEQ,
                          counterIncrease: (activeKeyset.keysetID, increase))
    }
    
    public static func send(request: PaymentRequest,
                            mint: Mint,
                            inputs: [Proof],
                            amount: Int? = nil,
                            memo: String?,
                            seed: String?) async throws -> SendPayloadResult {
        
        guard let requestAmount = request.amount ?? amount else {
            throw CashuError.paymentRequestAmount("Either request amount or explicit amount must be provided")
        }
        
        let proofSum = sum(inputs)
        let inputFee = try calculateFee(for: inputs, of: mint)
        
        let units = try units(for: inputs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("Input proofs have mixed units, which is not allowed.")
        }
        
        let unit = units.first ?? "sat"
        
        guard unit == request.unit ?? "sat" else {
            throw CashuError.unitError("Payment request unit and input unit do not match.")
        }
        
        // make sure inputs do not have spending condition
        for p in inputs {
            guard SpendingCondition.deserialize(from: p.secret) == nil else {
                throw CashuError.spendingConditionError(".send() function does not yet support locked inputs.")
            }
        }
        
        guard let activeKeyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit(unit)
        }
        
        // TODO: check for exact amount to avoid swap
        
        let lockToPublicKey: String?
        if let lockingCondition = request.lockingCondition {
            guard lockingCondition.kind == "P2PK" else {
                throw CashuError.paymentRequestValidation("CashuSwift only support HTLC locking conditions yet.")
            }
            lockToPublicKey = lockingCondition.data
        } else {
            lockToPublicKey = nil
        }
        
        let split = try split(for: proofSum, target: requestAmount, fee: inputFee)
        
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
        
        let payload = PaymentRequestPayload(id: request.paymentId,
                                            memo: memo,
                                            mint: mint.url.absoluteString,
                                            unit: unit,
                                            proofs: swapResult.send)
        
        return SendPayloadResult(payload: payload,
                                 send: swapResult.send,
                                 change: swapResult.keep,
                                 outputDLEQ: swapResult.outputDLEQ,
                                 counterIncrease: (activeKeyset.keysetID, increase))
    }
}
