import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    
    /// Receives a Cashu token by swapping its proofs with the mint.
    ///
    /// This function allows a wallet to receive a token by swapping its inputs with the provided mint, thus finalizing the ecash transfer.
    ///
    /// - Parameters:
    ///   - token: A Cashu token to receive
    ///   - mint: The mint to receive with via swap operation (must be same as in token)
    ///   - seed: Optional seed for deterministic secret generation
    ///   - privateKey: Optional hex string of 32-byte Schnorr private key for unlocking P2PK-locked tokens
    ///
    /// - Returns: A `ReceiveResult` containing the received proofs and DLEQ verification results
    /// - Throws: An error if the receive operation fails
    public static func receive(token: Token,
                               of mint: Mint,
                               seed: String?,
                               privateKey: String?) async throws -> ReceiveResult {
        
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let tokenProofs = token.proofsByMint.first?.value,
              try units(for: tokenProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        // make sure tokens with shortened keyset ids resolve correctly
        var inputProofs = try tokenProofs.withFullKeysetID(of: mint)
        
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
        
        let swapResult = try await swap(inputs: inputProofs, with: mint, seed: seed)
        return ReceiveResult(proofs: swapResult.new,
                             inputDLEQ: swapResult.inputDLEQ,
                             outputDLEQ: swapResult.outputDLEQ)
    }
}
