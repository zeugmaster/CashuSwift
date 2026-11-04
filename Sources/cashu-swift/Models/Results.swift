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

    /// Outcome of recovering NUT-08 change after a melt.
    ///
    /// Once the mint accepts a melt the Lightning payment is irreversible and the
    /// inputs are spent, so a failure to unblind the returned change can never fail
    /// the melt itself. This type makes that partial-success state explicit instead
    /// of hiding it behind an empty `change` array.
    public enum MeltChange: Sendable {
        /// No change was returned: no blank outputs were supplied, the quote is not
        /// paid yet, or the mint owed no change.
        case none
        /// Change was unblinded successfully. `dleq` is advisory; callers must
        /// inspect it themselves.
        case recovered([Proof], dleq: Crypto.DLEQVerificationResult)
        /// The mint returned change promises but they could not be unblinded.
        ///
        /// The melt itself succeeded and the inputs are spent. Persist `promises`
        /// together with the blank outputs' blinding factors and secrets so the
        /// unblinding can be retried (for example after reloading the mint's keysets),
        /// or rely on NUT-13 restore if the blank outputs were derived deterministically.
        case unrecoverable(promises: [Promise], error: any Error)

        /// Proofs for `.recovered`, `nil` otherwise. Backs the legacy `MeltResult.change`.
        var recoveredProofs: [Proof]? {
            if case .recovered(let proofs, _) = self { return proofs }
            return nil
        }

        /// DLEQ result for `.recovered`; `.valid` otherwise, mirroring the historical
        /// behaviour of `MeltResult.dleqResult` when there was nothing to verify.
        var legacyDLEQResult: Crypto.DLEQVerificationResult {
            if case .recovered(_, let dleq) = self { return dleq }
            return .valid
        }
    }

    /// Result of a melt operation. Generic over the concrete melt quote type so callers
    /// using a specific payment-method namespace (e.g. `Bolt11.melt`) get a fully typed quote back.
    public struct MeltResult<Quote>: Sendable where Quote: MeltQuoteResponse {
        public let quote: Quote
        /// Unblinded change, if any. Kept for source compatibility: it cannot distinguish
        /// "no change was due" from "change could not be unblinded". Prefer `changeOutcome`.
        public let change: [Proof]?
        /// DLEQ result for `change`. Reports `.valid` when there was nothing to verify.
        /// Kept for source compatibility; prefer `changeOutcome`.
        public let dleqResult: Crypto.DLEQVerificationResult
        /// Explicit outcome of change recovery. Check this to detect change that the
        /// mint returned but the wallet could not unblind.
        public let changeOutcome: MeltChange
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
