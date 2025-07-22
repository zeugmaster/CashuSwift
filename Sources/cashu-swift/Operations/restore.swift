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
    public static func restore(mint:MintRepresenting,
                               with seed:String,
                               batchSize:Int = 10) async throws -> [KeysetRestoreResult] {
        // no need to check validity of seed as function would otherwise crash during first det sec generation
        var results = [KeysetRestoreResult]()
        for keyset in mint.keysets {
            logger.info("Attempting restore for keyset: \(keyset.keysetID) of mint: \(mint.url.absoluteString)")
            let (proofs, _, lastMatchCounter) = try await restoreForKeyset(mint:mint, keyset:keyset, with: seed, batchSize: batchSize)
            print("last match counter: \(String(describing: lastMatchCounter))")
            
            // if we dont have any restorable proofs on this keyset, move on to the next
            if proofs.isEmpty {
                logger.debug("No ecash to restore for keyset \(keyset.keysetID).")
                continue
            }
                        
            let states = try await check(proofs, mint: mint) // ignores pending but should not

            guard states.count == proofs.count else {
                throw CashuError.restoreError("unable to filter for unspent ecash during restore")
            }

            var spendableProofs = [Proof]()
            for i in 0..<states.count {
                if states[i] == .unspent { spendableProofs.append(proofs[i]) }
            }
            
            let result = KeysetRestoreResult(keysetID: keyset.keysetID,
                                             derivationCounter: lastMatchCounter + 1,
                                             unitString: keyset.unit,
                                             proofs: spendableProofs,
                                             inputFeePPK: keyset.inputFeePPK)
            results.append(result)
            logger.info("Found \(spendableProofs.count) spendable proofs for keyset \(keyset.keysetID)")
        }
        return results
    }
    
    static func restoreForKeyset(mint:MintRepresenting,
                                 keyset:Keyset,
                                 with seed:String,
                                 batchSize:Int) async throws -> (proofs:[Proof],
                                                                 totalRestored:Int,
                                                                 lastMatchCounter:Int) {
        var proofs = [Proof]()
        var emtpyResponses = 0
        var currentCounter = 0
        var batchLastMatchIndex = 0
        let emptyRuns = 2
        while emtpyResponses < emptyRuns {
            let (outputs,
                 blindingFactors,
                 secrets) = try Crypto.generateOutputs(amounts: Array(repeating: 1, count: batchSize),
                                                       keysetID: keyset.keysetID,
                                                       deterministicFactors: (seed: seed,
                                                                              counter: currentCounter))
            
            
            let request = RestoreRequest(outputs: outputs)
            let response = try await Network.post(url: mint.url.appending(path: "/v1/restore"),
                                                  body: request,
                                                  expected: RestoreResponse.self)
            
            currentCounter += batchSize
            
            if response.signatures.isEmpty {
                emtpyResponses += 1
                continue
            } else {
                //reset counter to ensure they are CONSECUTIVE empty responses
                emtpyResponses = 0
                batchLastMatchIndex = outputs.lastIndex(where: { oldOutput in
                    response.outputs.contains(where: {newOut in oldOutput.B_ == newOut.B_})
                }) ?? 0
            }
            
            // filter blindingfactor and secret arrays to include only the ones for outputs that exist
            var rs = [String]()
            var xs = [String]()
            for i in 0..<outputs.count {
                if response.outputs.contains(where: {$0.B_ == outputs[i].B_}) {
                    rs.append(blindingFactors[i])
                    xs.append(secrets[i])
                }
            }
            
            let batchProofs = try Crypto.unblindPromises(response.signatures,
                                                         blindingFactors: rs,
                                                         secrets: xs,
                                                         keyset: keyset)
            proofs.append(contentsOf: batchProofs)
        }
        currentCounter -= (emptyRuns + 1) * batchSize
        currentCounter += batchLastMatchIndex
        if currentCounter < 0 { currentCounter = 0 }
        return (proofs, proofs.count, currentCounter)
    }
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func restore(mint:Mint,
                               with seed:String,
                               batchSize:Int = 10) async throws -> [KeysetRestoreResult] {
        return try await restore(mint: mint as MintRepresenting,
                                 with: seed,
                                 batchSize: batchSize)
    }
    
    /// Restores proofs from a seed phrase.
    /// - Parameters:
    ///   - mint: The mint to restore from
    ///   - seed: The seed phrase for deterministic proof generation
    ///   - batchSize: Number of outputs to check per batch (default: 50)
    /// - Returns: A tuple containing:
    ///   - result: Array of restoration results for each keyset
    ///   - validDLEQ: Whether DLEQ verification passed
    /// - Throws: An error if the restore operation fails
    public static func restore(from mint: Mint,
                               with seed: String,
                               batchSize: Int = 50) async throws -> (result: [KeysetRestoreResult],
                                                                     validDLEQ: Bool) {
        
        let results = try await restore(mint: mint as MintRepresenting,
                                        with: seed,
                                        batchSize: batchSize)
        
        let flatProofs = results.flatMap({ $0.proofs })
        
        let valid: Bool
        do {
            valid = try Crypto.validDLEQ(for: flatProofs, with: mint)
        } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(_) {
            logger.warning("""
                           DLEQ check could not be performed due to missing data but will still \
                           evaluate as passing because not all wallets and mint support NUT-10. \
                           future versions will consider the check failed.
                           """)
            valid = true
        } catch {
            throw error
        }
        
        return (results, valid)
    }
}
