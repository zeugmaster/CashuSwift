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
    
    /// Swaps proofs with a mint for new proofs with detailed DLEQ verification results.
    /// - Parameters:
    ///   - inputs: The input proofs to swap
    ///   - mint: The mint to swap with
    ///   - amount: Optional amount to swap (if nil, swaps all minus fees)
    ///   - seed: Optional seed for deterministic secret generation
    ///   - preferredReturnDistribution: Optional preferred denomination distribution for change
    /// - Returns: A tuple containing:
    ///   - new: The new proofs
    ///   - change: The change proofs
    ///   - inputDLEQ: DLEQ verification result for input proofs
    ///   - outputDLEQ: DLEQ verification result for output proofs
    /// - Throws: An error if the swap operation fails
    public static func swap(inputs: [Proof],
                            with mint: Mint,
                            amount: Int? = nil,
                            seed: String?,
                            preferredReturnDistribution: [Int]? = nil) async throws -> (new: [Proof],
                                                                                        change: [Proof],
                                                                                        inputDLEQ: Crypto.DLEQVerificationResult,
                                                                                        outputDLEQ: Crypto.DLEQVerificationResult) {
        
        let inputDLEQ = try Crypto.checkDLEQ(for: inputs, with: mint)
        
        let fee = try calculateFee(for: inputs, of: mint)
        let proofSum = sum(inputs)
        
        let returnAmount:Int
        let changeAmount:Int
        
        if let amount {
            if proofSum >= amount + fee {
                returnAmount = amount
                changeAmount = proofSum - returnAmount - fee
            } else {
                throw CashuError.insufficientInputs("SWAP: sum of proofs (\(proofSum)) is less than amount (\(amount)) + fees (\(fee))")
            }
        } else {
            returnAmount = proofSum - fee
            changeAmount = 0
        }
        
        let units = try units(for: inputs, of: mint)
        
        guard units.count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        guard let activeKeyset = activeKeysetForUnit(units.first!, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("no active keyset could be found for unit \(String(describing: units.first))")
        }
        
        let swapDistribution = CashuSwift.splitIntoBase2Numbers(returnAmount)
        
        let changeDistribution = preferredReturnDistribution.map({ $0 }) ?? splitIntoBase2Numbers(changeAmount)
        
        guard changeDistribution.reduce(0, +) == changeAmount else {
            throw CashuError.preferredDistributionMismatch(
            """
            preferredReturnDistribution does not add up to expected change amount.
            proof sum: \(proofSum), return amount: \(returnAmount), change amount: \
            \(changeAmount), fees: \(fee), preferred distr sum: \(changeDistribution.reduce(0, +))
            """)
        }
        
        let combinedDistribution = (swapDistribution + changeDistribution).sorted()
        
        let deterministicFactors = seed.map({ ($0, activeKeyset.derivationCounter) })

        let (outputs, bfs, secrets) = try Crypto.generateOutputs(amounts: combinedDistribution,
                                                                 keysetID: activeKeyset.keysetID,
                                                                 deterministicFactors: deterministicFactors)
                
        let swapRequest = SwapRequest(inputs: stripDLEQ(inputs),
                                      outputs: outputs)
        
        let swapResponse = try await Network.post(url: mint.url.appending(path: "/v1/swap"),
                                                  body: swapRequest,
                                                  expected: SwapResponse.self)
        
        var changeProofs = try Crypto.unblindPromises(swapResponse.signatures,
                                                      blindingFactors: bfs,
                                                      secrets: secrets,
                                                      keyset: activeKeyset)
        
        var sendProofs = [Proof]()
        for n in swapDistribution {
            if let index = changeProofs.firstIndex(where: {$0.amount == n}) {
                sendProofs.append(changeProofs[index])
                changeProofs.remove(at: index)
            }
        }
        
        let outputDLEQ = try Crypto.checkDLEQ(for: sendProofs + changeProofs, with: mint)
        
        return (sendProofs, changeProofs, inputDLEQ, outputDLEQ)
    }
    
    static func swap(inputs: [Proof],
                     with mint: Mint,
                     sendOutputs: (outputs:[Output], blindingFactors: [String], secrets: [String]),
                     keepOutputs: (outputs:[Output], blindingFactors: [String], secrets: [String])) async throws -> (send: [Proof],
                                                                                                                     keep: [Proof],
                                                                                                                     inputDLEQ: Crypto.DLEQVerificationResult,
                                                                                                                     outputDLEQ: Crypto.DLEQVerificationResult) {
        
        let inputDLEQ = try Crypto.checkDLEQ(for: inputs, with: mint)
        
        let fee = try calculateFee(for: inputs, of: mint)
        let proofSum = sum(inputs)
        
        let outputSum = sum(sendOutputs.0 + keepOutputs.0)
        
        guard (proofSum - fee) == outputSum else {
            throw CashuError.insufficientInputs("SWAP: sum of proofs (\(proofSum)) is less than keep and send outputs (\(outputSum)) + fees (\(fee))")
        }
        
        let units = try units(for: inputs, of: mint)
        
        guard units.count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        let keysetIDs = Set((sendOutputs.0 + keepOutputs.0).map({ $0.id }))
        guard keysetIDs.count == 1 else { // FIXME: use appropriate error or remove
            throw CashuError.unknownError("outputs to send and keep seem to use different keysets, which is not supported \(keysetIDs)")
        }
        
        guard let keyset = mint.keysets.first(where: { $0.keysetID == keysetIDs.first }), keyset.active else {
            throw CashuError.unknownError("keyset \(keysetIDs.first ?? "nil") could not be found or is inactive")
        }
        
        var combined:[(o: Output, i:Int, toSend:Bool)] =
        sendOutputs.0.enumerated().map({ (i, v) in (o: v, i:i, toSend: true) }) +
        keepOutputs.0.enumerated().map({ (i, v) in (o: v, i:i + sendOutputs.0.count, toSend: false) })
        
        combined.sort(by: { $0.o.amount < $1.o.amount })
        
        let swapRequest = SwapRequest(inputs: stripDLEQ(inputs),
                                      outputs: combined.map({ $0.o }))
        
        let swapResponse = try await Network.post(url: mint.url.appending(path: "/v1/swap"),
                                                  body: swapRequest,
                                                  expected: SwapResponse.self)
        
        // restore original order for unblinding to work
        let outputsAndPromises = zip(combined, swapResponse.signatures).sorted { first, second in
            first.0.i < second.0.i
        }
        
        // TODO: repetitive, remove boolean for send/keep, unblind combined
        let sendPromises = outputsAndPromises.filter({ $0.0.toSend })
                                             .map({ $0.1 })
        let keepPromises = outputsAndPromises.filter({ !$0.0.toSend })
                                             .map({ $0.1 })
        
        let sendProofs = try Crypto.unblindPromises(sendPromises,
                                                    blindingFactors: sendOutputs.blindingFactors,
                                                    secrets: sendOutputs.secrets,
                                                    keyset: keyset)
        let keepProofs = try Crypto.unblindPromises(keepPromises,
                                                    blindingFactors: keepOutputs.blindingFactors,
                                                    secrets: keepOutputs.secrets,
                                                    keyset: keyset)
        
        let outputDLEQ = try Crypto.checkDLEQ(for: sendProofs + keepProofs, with: mint)
        
        return (sendProofs, keepProofs, inputDLEQ, outputDLEQ)
    }
}
