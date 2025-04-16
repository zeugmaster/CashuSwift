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
    public static func receive(mint:MintRepresenting,
                               token:Token,
                               seed:String? = nil) async throws -> [ProofRepresenting] {
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        return try await swap(mint:mint, proofs: inputProofs, seed: seed).new
    }
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func receive(mint: Mint,
                             token: Token,
                             seed: String? = nil) async throws -> [Proof] {
        return try await receive(mint: mint as MintRepresenting,
                                token: token,
                                seed: seed) as! [Proof]
    }
    
    public static func receive(token: Token, with mint: Mint, seed: String?) async throws -> (proofs: [Proof], validDLEQ: Bool) {
        
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        let swapResult = try await swap(with: mint, inputs: inputProofs, seed: seed)
        return (swapResult.new, swapResult.validDLEQ)
    }
}
