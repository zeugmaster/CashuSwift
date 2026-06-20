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
    ///   - preferredKeepDistribution: Optional denomination split for the change (kept)
    ///     proofs, e.g. from `preferredDistribution(forAmount:retained:…)` to move the
    ///     wallet toward its offline-send denomination target. Must sum to the keep
    ///     amount or `preferredDistributionMismatch` is thrown. The send (token) outputs
    ///     stay base-2 — their denominations are the recipient's concern. Ignored on the
    ///     exact-amount direct path (no swap, no change).
    ///
    /// - Returns: A `SendResult` containing the token, change proofs, DLEQ verification result, and counter increase info
    /// - Throws: An error if the operation fails
    public static func send(inputs: [Proof],
                            mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            memo: String? = nil,
                            lockToPublicKey: String? = nil,
                            preferredKeepDistribution: [Int]? = nil) async throws -> SendResult {
        let proofSum = sum(inputs)
        let inputFee = try calculateFee(for: inputs, of: mint)
        
        // Validate amount is either nil or positive
        if let amount = amount, amount <= 0 {
            throw CashuError.invalidAmount
        }
        
        let unit = try singleUnit(for: inputs, of: mint)
        
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

        let keepDistribution = preferredKeepDistribution ?? splitIntoBase2Numbers(split.keepAmount)
        guard keepDistribution.reduce(0, +) == split.keepAmount else {
            throw CashuError.preferredDistributionMismatch(
                "preferredKeepDistribution sum (\(keepDistribution.reduce(0, +))) does not match the keep amount (\(split.keepAmount)).")
        }
        let keepOutputSets = try generateOutputs(distribution: keepDistribution,
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
                            seed: String?,
                            preferredKeepDistribution: [Int]? = nil) async throws -> SendPayloadResult {
        
        guard let requestAmount = request.amount ?? amount else {
            throw CashuError.paymentRequestAmount("Either request amount or explicit amount must be provided")
        }
        
        let proofSum = sum(inputs)
        let inputFee = try calculateFee(for: inputs, of: mint)
        
        let unit = try singleUnit(for: inputs, of: mint)
        
        if let requestUnit = request.unit, unit != requestUnit {
            throw CashuError.unitError("Payment request unit '\(requestUnit)' does not match input unit '\(unit)'.")
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

        let keepDistribution = preferredKeepDistribution ?? splitIntoBase2Numbers(split.keepAmount)
        guard keepDistribution.reduce(0, +) == split.keepAmount else {
            throw CashuError.preferredDistributionMismatch(
                "preferredKeepDistribution sum (\(keepDistribution.reduce(0, +))) does not match the keep amount (\(split.keepAmount)).")
        }
        let keepOutputSets = try generateOutputs(distribution: keepDistribution,
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

    /// Builds a token from exactly the given proofs, with **no mint round-trip**.
    ///
    /// This is the offline-send primitive. When the wallet already holds a subset of
    /// unlocked proofs summing to the desired amount — e.g. a
    /// `selectProofs(…, purpose: .tokenTransferUnlocked)` result whose `kind` is
    /// `.directToken` — the token simply *is* those proofs: no swap, no change, no
    /// network. Being **synchronous**, the absence of a network round-trip is
    /// guaranteed at the type level (unlike the `async` `send`).
    ///
    /// The caller owns proof-state handling: reserve/mark the proofs `pending` before
    /// handing off the token, since they now leave the wallet's spendable balance.
    ///
    /// - Parameters:
    ///   - proofs: The exact proofs to bundle. Must share a single unit and carry no
    ///     spending condition — a P2PK send must mint outputs to the lock key, which
    ///     requires the mint and so cannot be done offline.
    ///   - mint: The mint these proofs belong to (provides the URL and keyset IDs).
    ///   - memo: Optional memo to include in the token.
    /// - Returns: A `Token` bundling `proofs`.
    /// - Throws: `CashuError` if `proofs` is empty, spans multiple units, or is locked.
    public static func offlineToken(for proofs: [Proof],
                                    mint: Mint,
                                    memo: String? = nil) throws -> Token {
        guard !proofs.isEmpty else {
            throw CashuError.insufficientInputs("offlineToken: no proofs provided.")
        }
        let unit = try singleUnit(for: proofs, of: mint)
        for p in proofs {
            guard SpendingCondition.deserialize(from: p.secret) == nil else {
                throw CashuError.spendingConditionError("offlineToken does not support locked proofs.")
            }
        }
        return Token(proofs: [mint.url.absoluteString: proofs.withShortKeysetID()],
                     unit: unit,
                     memo: memo)
    }

    /// Whether `amount` can be sent offline (unlocked) right now: i.e. an exact subset
    /// of `proofs` sums to it, so a token can be built with `offlineToken(for:…)`
    /// without a mint swap. Convenience over inspecting
    /// `selectProofs(…, purpose: .tokenTransferUnlocked).kind == .directToken`.
    /// Returns `false` on any infeasibility (insufficient funds, no eligible proofs, …).
    public static func canSendOffline(_ proofs: [some ProofRepresenting],
                                      amount: Int,
                                      mint: some MintRepresenting,
                                      unit: String) -> Bool {
        guard let result = try? selectProofs(proofs, targetAmount: amount, mint: mint,
                                             unit: unit, purpose: .tokenTransferUnlocked) else {
            return false
        }
        return result.kind == .directToken
    }
}
