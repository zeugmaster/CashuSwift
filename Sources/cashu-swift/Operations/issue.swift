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
    /// After paying the quote amount to the mint, use this function to issue the actual ecash as a list of [`String`]s
    /// Leaving `seed` empty will give you proofs from non-deterministic outputs which cannot be recreated from a seed phrase backup
    // generic types without dleq return
    @available(*, deprecated, message: "This method does not return the boolean flag for successful DLEQ verification which needs to be handled by a wallet application.")
    public static func issue(for quote:Quote,
                             on mint: MintRepresenting,
                             seed:String? = nil,
                             preferredDistribution:[Int]? = nil) async throws -> [some ProofRepresenting] {
        
        guard let quote = quote as? Bolt11.MintQuote else {
            throw CashuError.typeMismatch("Quote to issue proofs for was not a Bolt11.MintQuote")
        }
        
        guard let requestDetail = quote.requestDetail else {
            throw CashuError.missingRequestDetail("You need to set requestDetail associated with the quote.")
        }
        
        var distribution:[Int]
        
        if let preferredDistribution = preferredDistribution {
            guard preferredDistribution.reduce(0, +) == requestDetail.amount else {
                throw CashuError.preferredDistributionMismatch("Specified preferred distribution does not add up to the same amount as the quote.")
            }
            distribution = preferredDistribution
        } else {
            distribution = CashuSwift.splitIntoBase2Numbers(requestDetail.amount)
        }
        
        guard let activeKeyset = mint.keysets.first(where: { $0.active == true &&
                                                       $0.unit == requestDetail.unit }) else {
            throw CashuError.noActiveKeysetForUnit("Could not determine an ACTIVE keyset for this unit \(requestDetail.unit.uppercased())")
        }
        
        // tuple for outputs, blindingfactors, secrets
        // swift does not allow uninitialized tuple declaration
        var outputs = (outputs:[Output](), blindingFactors:[""], secrets:[""])
        if let seed = seed {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: activeKeyset.keysetID,
                                                 deterministicFactors: (seed: seed,
                                                                        counter: activeKeyset.derivationCounter))
            
        } else {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: activeKeyset.keysetID)
        }
        
        let mintRequest = Bolt11.MintRequest(quote: quote.quote, outputs: outputs.outputs)
        
        // TODO: PARSE COMMON ERRORS
        let promises = try await Network.post(url: mint.url.appending(path: "/v1/mint/bolt11"),
                                              body: mintRequest,
                                              expected: Bolt11.MintResponse.self)
                            
        let proofs = try Crypto.unblindPromises(promises.signatures,
                                                blindingFactors: outputs.blindingFactors,
                                                secrets: outputs.secrets,
                                                keyset: activeKeyset)
        
        return proofs
    }
    
    // static types without dleq return
    @available(*, deprecated, message: "This method does not return the boolean flag for successful DLEQ verification which needs to be handled by a wallet application.")
    public static func issue(for quote: Quote,
                             on mint: Mint,
                             seed: String? = nil,
                             preferredDistribution: [Int]? = nil) async throws -> [Proof] {
        return try await issue(for: quote,
                               on: mint as MintRepresenting,
                               seed: seed,
                               preferredDistribution: preferredDistribution) as! [Proof]
    }

    
    public static func issue(for quote:Quote,
                             with mint: Mint,
                             seed:String?,
                             preferredDistribution:[Int]? = nil) async throws -> (proofs: [Proof], validDLEQ: Bool) {
        
        // TODO: completely remove issue function without dleq check
        let proofs = try await issue(for: quote,
                                     on: mint,
                                     seed: seed,
                                     preferredDistribution: preferredDistribution)
        
        let dleqValid: Bool
        do {
            dleqValid = try Crypto.validDLEQ(for: proofs, with: mint)
        } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(let message) {
            logger.warning("""
                           While restoring from mint \(mint.url) DLEQ check could not be performed due to missing data but will still \
                           evaluate as passing because not all wallets and mint support NUT-10. \
                           future versions will consider the check failed.
                           """)
            dleqValid = true
        } catch {
            throw error
        }
        
        return (proofs, dleqValid)
    }
    
    public static func mintQuoteState(for quoteID: String,
                                      mint: Mint) async throws -> Bolt11.MintQuote {
        let url = mint.url.appending(path: "/v1/mint/quote/bolt11/\(quoteID)")
        print(url.absoluteString)
        return try await Network.get(url: url, expected: Bolt11.MintQuote.self)
    }
}
