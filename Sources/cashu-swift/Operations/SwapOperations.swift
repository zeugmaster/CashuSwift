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
    ///   - preferredReturnDistribution: Optional preferred denomination distribution. When
    ///     `amount` is non-nil it shapes the *change* (must sum to the change amount); when
    ///     `amount` is nil (keep everything) it shapes the *entire returned pool* (must sum
    ///     to `proofSum − fee`) — used for receive- and consolidation-time rebalancing.
    ///     A mismatch throws `preferredDistributionMismatch`.
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
                            preferredReturnDistribution: [Int]? = nil, session: URLSession = .shared) async throws -> (new: [Proof],
                                                                                        change: [Proof],
                                                                                        inputDLEQ: Crypto.DLEQVerificationResult,
                                                                                        outputDLEQ: Crypto.DLEQVerificationResult) {
        
        let unit = try singleUnit(for: inputs, of: mint)
        
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
        
        guard let activeKeyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("no active keyset could be found for unit \(unit)")
        }
        
        let swapDistribution: [Int]
        let changeDistribution: [Int]

        if amount == nil {
            // No send portion: the whole returned pool is kept, so a preferred
            // distribution (if given) shapes all of it — enabling receive- and
            // consolidation-time rebalancing toward a denomination target.
            swapDistribution = preferredReturnDistribution ?? splitIntoBase2Numbers(returnAmount)
            changeDistribution = []
            guard swapDistribution.reduce(0, +) == returnAmount else {
                throw CashuError.preferredDistributionMismatch(
                """
                preferredReturnDistribution does not add up to the returned amount.
                proof sum: \(proofSum), return amount: \(returnAmount), fees: \(fee), \
                preferred distr sum: \(swapDistribution.reduce(0, +))
                """)
            }
        } else {
            swapDistribution = CashuSwift.splitIntoBase2Numbers(returnAmount)
            changeDistribution = preferredReturnDistribution ?? splitIntoBase2Numbers(changeAmount)
            guard changeDistribution.reduce(0, +) == changeAmount else {
                throw CashuError.preferredDistributionMismatch(
                """
                preferredReturnDistribution does not add up to expected change amount.
                proof sum: \(proofSum), return amount: \(returnAmount), change amount: \
                \(changeAmount), fees: \(fee), preferred distr sum: \(changeDistribution.reduce(0, +))
                """)
            }
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
                                                  expected: SwapResponse.self, session: session)
        
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
    
}
