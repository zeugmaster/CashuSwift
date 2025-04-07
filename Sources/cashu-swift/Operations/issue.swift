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
        // TODO: CHECK FOR DUPLICATE OUTPUT ERROR, RETRY ACC TO `skipDuplicateOutputs`
        let promises = try await Network.post(url: mint.url.appending(path: "/v1/mint/bolt11"),
                                              body: mintRequest,
                                              expected: Bolt11.MintResponse.self)
                    
        let proofs = try Crypto.unblindPromises(promises.signatures,
                                                blindingFactors: outputs.blindingFactors,
                                                secrets: outputs.secrets,
                                                keyset: activeKeyset)
        
        return proofs
    }

    
    public static func issue(for quote: Quote,
                           on mint: Mint,
                           seed: String? = nil,
                           preferredDistribution: [Int]? = nil) async throws -> [Proof] {
        return try await issue(for: quote,
                             on: mint as MintRepresenting,
                             seed: seed,
                             preferredDistribution: preferredDistribution) as! [Proof]
    }

}
