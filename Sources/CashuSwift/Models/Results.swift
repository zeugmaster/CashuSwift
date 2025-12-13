//
//  Results.swift
//  CashuSwift
//
//  Created on 08.12.25.
//

import Foundation

extension CashuSwift {
    /// Result of an issue operation (minting new proofs from a paid mint quote)
    public struct IssueResult: Sendable, Codable {
        /// The newly issued proofs
        public let proofs: [Proof]
        /// Result of DLEQ verification for the issued proofs
        public let dleqResult: Crypto.DLEQVerificationResult
    }
    
    /// Result of a melt operation (paying a Lightning invoice with proofs)
    public struct MeltResult: Sendable, Codable {
        /// The melt quote response from the mint
        public let quote: Bolt11.MeltQuote
        /// Change proofs returned if fee was overpaid
        public let change: [Proof]?
        /// Result of DLEQ verification for the change proofs
        public let dleqResult: Crypto.DLEQVerificationResult
    }
    
    /// Result of a send operation (creating a token from proofs)
    public struct SendResult: Sendable {
        /// The created Cashu token to send
        public let token: Token
        /// The proofs that will be sent with the token
        public let send: [Proof]
        /// Change proofs kept by the sender
        public let change: [Proof]
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
        /// Keyset ID and counter increase for deterministic derivation
        public let counterIncrease: (keysetID: String, increase: Int)?
    }
    
    /// Result of a send operation for a payment request
    public struct SendPayloadResult: Sendable {
        /// The payment request payload to send
        public let payload: PaymentRequestPayload
        /// The proofs that will be sent with the payload
        public let send: [Proof]
        /// Change proofs kept by the sender
        public let change: [Proof]
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
        /// Keyset ID and counter increase for deterministic derivation
        public let counterIncrease: (keysetID: String, increase: Int)?
        
    }
    
    /// Result of a receive operation (swapping incoming proofs for new ones)
    public struct ReceiveResult: Sendable, Codable {
        /// The newly received proofs
        public let proofs: [Proof]
        /// Result of DLEQ verification for input proofs
        public let inputDLEQ: Crypto.DLEQVerificationResult
        /// Result of DLEQ verification for output proofs
        public let outputDLEQ: Crypto.DLEQVerificationResult
    }
}

