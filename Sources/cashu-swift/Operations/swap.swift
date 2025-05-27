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
    
    @available(*, deprecated, message: "function does not check DLEQ, or support proofs with witness for NUT-10 spending conditions.")
    public static func swap(mint:MintRepresenting,
                            proofs:[ProofRepresenting],
                            amount:Int? = nil,
                            seed:String? = nil,
                            preferredReturnDistribution:[Int]? = nil) async throws -> (new:[ProofRepresenting],
                                                                                       change:[ProofRepresenting]) {
        
        let inputs = proofs.map({ Proof($0) })
        let mint = Mint(mint)
        
        let result = try await swap(with: mint, inputs: inputs, amount: amount, seed: seed, preferredReturnDistribution: preferredReturnDistribution)
        return (result.new, result.change)
    }

    @available(*, deprecated, message: "function does not check DLEQ")
    public static func swap(mint: Mint,
                           proofs: [Proof],
                           amount: Int? = nil,
                           seed: String? = nil,
                           preferredReturnDistribution: [Int]? = nil) async throws -> (new: [Proof], change: [Proof]) {
        let result = try await swap(mint: mint as MintRepresenting,
                                   proofs: proofs as [ProofRepresenting],
                                   amount: amount,
                                   seed: seed,
                                   preferredReturnDistribution: preferredReturnDistribution)
        return (result.new as! [Proof], result.change as! [Proof])
    }
    
    public static func swap(with mint: Mint,
                            inputs: [Proof],
                            amount: Int? = nil,
                            seed: String?,
                            preferredReturnDistribution: [Int]? = nil) async throws -> (new: [Proof],
                                                                                        change: [Proof],
                                                                                        validDLEQ: Bool) {
        let result = try await swap(inputs: inputs,
                                    with: mint,
                                    amount: amount,
                                    seed: seed,
                                    preferredReturnDistribution: preferredReturnDistribution)
        
        let valid = result.2 == .valid && result.3 == result.2
        
        return (result.0, result.1, valid)
    }
    
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
        
        // TODO: implement true output selection
        
        let swapDistribution = CashuSwift.splitIntoBase2Numbers(returnAmount)
        let changeDistribution:[Int]
        
        if let preferredReturnDistribution {
            // TODO: CHECK THAT AMOUNTS ARE ONLY VALID INTEGERS
            let preferredReturnDistributionSum = preferredReturnDistribution.reduce(0, +)
            guard preferredReturnDistribution.reduce(0, +) == changeAmount else {
                throw CashuError.preferredDistributionMismatch(
                """
                preferredReturnDistribution does not add up to expected change amount.
                proof sum: \(proofSum), return amount: \(returnAmount), change amount: \(changeAmount), fees: \(fee), preferred distr sum: \(preferredReturnDistributionSum)
                """)
            }
            changeDistribution = preferredReturnDistribution
        } else {
            changeDistribution = CashuSwift.splitIntoBase2Numbers(changeAmount)
        }
        
        let combinedDistribution = (swapDistribution + changeDistribution).sorted()
        
        let deterministicFactors:(String, Int)?
        if let seed {
            deterministicFactors = (seed, activeKeyset.derivationCounter)
        } else {
            deterministicFactors = nil
        }
        
        let (outputs, bfs, secrets) = try Crypto.generateOutputs(amounts: combinedDistribution,
                                                                 keysetID: activeKeyset.keysetID,
                                                                 deterministicFactors: deterministicFactors)
        
        let internalProofs = stripDLEQ(inputs)
                
        let swapRequest = SwapRequest(inputs: internalProofs, outputs: outputs)
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
}
