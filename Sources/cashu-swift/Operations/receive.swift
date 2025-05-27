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
    
    public static func receive(token: Token,
                               with mint: Mint,
                               seed: String?,
                               privateKey: String?) async throws -> (proofs: [Proof],
                                                                     validDLEQ: Bool) {
        
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard var inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        var publicKey: String? = nil
        if let privateKey {
            guard let k = try? secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey.bytes) else {
                throw CashuError.spendingConditionError("Token contains locked proofs but private key was not provided or invalid.")
            }
            publicKey = String(bytes: k.publicKey.dataRepresentation)
        }
        
        switch try token.checkAllInputsLocked(to: publicKey) {
        case .match:
            // TODO: for now we skip failing DLEQ verification alltogether
            
            let proofsWitness = try inputProofs.map { p in
                // FIXME: redundant
                guard let privateKey,
                      let k = try? secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey.bytes) else {
                    throw CashuError.spendingConditionError("Token contains locked proofs but private key was not provided or invalid.")
                }
                let sigBytes = try k.signature(for: p.secret.data(using: .utf8)!).bytes
                let witness = Proof.Witness(signatures: [String(bytes: sigBytes)])
                return try Proof(keysetID: p.keysetID,
                                 amount: p.amount,
                                 secret: p.secret,
                                 C: p.C,
                                 witness: witness.stringJSON())
            }
            inputProofs = proofsWitness
            
        case .mismatch:
            throw CashuError.spendingConditionError("P2PK locking keys did not match")
        case .noKey:
            throw CashuError.spendingConditionError("The token is locked but no key was provided")
        case .partial:
            throw CashuError.spendingConditionError("Token contains proofs with different spending conditions, which the library can not yet handle.")
        case .notLocked:
            break
        }
        
        let swapResult = try await swap(with: mint, inputs: inputProofs, seed: seed)
        return (swapResult.new, swapResult.validDLEQ)
    }
}
