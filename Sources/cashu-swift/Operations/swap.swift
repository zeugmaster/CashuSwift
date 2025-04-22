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
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func swap(mint:MintRepresenting,
                            proofs:[ProofRepresenting],
                            amount:Int? = nil,
                            seed:String? = nil,
                            preferredReturnDistribution:[Int]? = nil) async throws -> (new:[ProofRepresenting],
                                                                         change:[ProofRepresenting]) {
        let fee = try calculateFee(for: proofs, of: mint)
        let proofSum = sum(proofs)
        
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
        
        // the number of units from potentially mutliple keysets across input proofs must be 1:
        // less than 1 would mean no matching keyset/unit
        // more than one would imply multiple unit input proofs, which is not supported
        
        let units = try units(for: proofs, of: mint)
        
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
        
        let internalProofs = normalize(proofs)
                
        let swapRequest = SwapRequest(inputs: internalProofs, outputs: outputs)
        let swapResponse = try await Network.post(url: mint.url.appending(path: "/v1/swap"),
                                                  body: swapRequest,
                                                  expected: SwapResponse.self)
        
        var newProofs = try Crypto.unblindPromises(swapResponse.signatures,
                                                   blindingFactors: bfs,
                                                   secrets: secrets,
                                                   keyset: activeKeyset)
        
        var sendProofs = [Proof]()
        for n in swapDistribution {
            if let index = newProofs.firstIndex(where: {$0.amount == n}) {
                sendProofs.append(newProofs[index])
                newProofs.remove(at: index)
            }
        }
        
        return (sendProofs, newProofs)
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
        
        // check incoming proofs dleq
        // check incoming inputs dleq but no not fail if the dleq data is missing
        // only fail if dleq data is present but is invalid
        let inputsValidDLEQ: Bool
        do {
            inputsValidDLEQ = try Crypto.validDLEQ(for: inputs, with: mint)
        } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(_) {
            logger.warning("""
                           Before swap: DLEQ check could not be performed due to missing data but will still \
                           evaluate as passing because not all wallets and mint support NUT-10. \
                           future versions will consider the check failed.
                           """)
            inputsValidDLEQ = true
        } catch {
            throw error
        }
        
        let swapResult = try await swap(mint: mint,
                                        proofs: stripDLEQ(inputs), // Making sure no DLEQ data is submitted to the mint
                                        amount: amount,
                                        seed: seed,
                                        preferredReturnDistribution: preferredReturnDistribution)
        
        // check output proofs dleq
        let outputsValidDLEQ: Bool
        do {
            outputsValidDLEQ = try Crypto.validDLEQ(for: swapResult.new + swapResult.change, with: mint)
        } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(_) {
            logger.warning("""
                           After swap: DLEQ check could not be performed due to missing data but will still \
                           evaluate as passing because not all wallets and mint support NUT-10. \
                           future versions will consider the check failed.
                           """)
            outputsValidDLEQ = true
        } catch {
            throw error
        }
        
        let validDLEQ = (inputsValidDLEQ && outputsValidDLEQ)
        
        return (swapResult.new, swapResult.change, validDLEQ)
    }

}
