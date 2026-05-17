//
//  Results.swift
//  CashuSwift
//

import Foundation

extension CashuSwift {
    /// Result of an issue (mint) operation.
    public struct IssueResult: Sendable, Codable {
        public let proofs: [Proof]
        public let dleqResult: Crypto.DLEQVerificationResult
    }

    /// Result of a melt operation. Generic over the concrete melt quote type so callers
    /// using a specific payment-method namespace (e.g. `Bolt11.melt`) get a fully typed quote back.
    public struct MeltResult<Quote>: Sendable where Quote: MeltQuoteResponse {
        public let quote: Quote
        public let change: [Proof]?
        public let dleqResult: Crypto.DLEQVerificationResult
    }

    /// Result of a send operation (creating a token from proofs).
    public struct SendResult: Sendable {
        public let token: Token
        public let send: [Proof]
        public let change: [Proof]
        public let outputDLEQ: Crypto.DLEQVerificationResult
        public let counterIncrease: (keysetID: String, increase: Int)?
    }

    /// Result of a send operation for a payment request.
    public struct SendPayloadResult: Sendable {
        public let payload: PaymentRequestPayload
        public let send: [Proof]
        public let change: [Proof]
        public let outputDLEQ: Crypto.DLEQVerificationResult
        public let counterIncrease: (keysetID: String, increase: Int)?
    }

    /// Result of a receive operation.
    public struct ReceiveResult: Sendable, Codable {
        public let proofs: [Proof]
        public let inputDLEQ: Crypto.DLEQVerificationResult
        public let outputDLEQ: Crypto.DLEQVerificationResult
    }
}
