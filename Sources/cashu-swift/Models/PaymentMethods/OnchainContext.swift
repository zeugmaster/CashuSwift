import Foundation

extension CashuSwift.Onchain {
    /// Reserved NUT-13 indices. Persist `next` before sending the prepared operation.
    public struct CounterRange: Codable, Sendable {
        public let keysetID: String
        public let start: Int
        public let next: Int
    }

    /// Sensitive recovery material. Store securely; never log or send to another party.
    /// The keyset snapshot allows recovery after rotation without using new signing keys.
    public struct OutputMaterial: Codable, Sendable {
        public let keyset: CashuSwift.Keyset
        public let outputs: [CashuSwift.Output]
        public let blindingFactors: [String]
        public let secrets: [String]
        public let counterRange: CounterRange?
    }

    /// Persist this before minting, including for random output secrets.
    /// The signature authorizes only the prepared outputs; the private quote key is not stored here.
    public struct MintContext: Codable, Sendable {
        public let version: Int
        public let mintURL: URL
        public let quote: MintQuote
        public let material: OutputMaterial
        public let signature: String
        public var executionBody: CashuSwift.SignedMintExecutionBody {
            .init(quote: quote.quote, outputs: material.outputs, signature: signature)
        }
    }

    /// Persist this and reserve its inputs before submission. Keep it through timeouts,
    /// pending states, and change recovery. Decoding a context does not submit it.
    public struct MeltContext: Codable, Sendable {
        public let version: Int
        public let mintURL: URL
        public let quote: MeltQuote
        public let feeIndex: Int
        public let inputs: [CashuSwift.Proof]
        public let inputFee: Int
        public let material: OutputMaterial
        public var executionBody: MeltExecutionBody {
            .init(quote: quote.quote, feeIndex: feeIndex,
                  inputs: inputs.map {
                      CashuSwift.Proof(keysetID: $0.keysetID, amount: $0.amount, secret: $0.secret,
                                       C: $0.C, dleq: nil, witness: $0.witness)
                  }, outputs: material.outputs.isEmpty ? nil : material.outputs)
        }
    }

    public enum RecoveryFailure: String, Codable, Sendable {
        case invalidPromises
        case missingDLEQ
        case invalidDLEQ
    }

    /// Only `.complete` contains spendable proofs. Failed verification never credits value.
    public enum RecoveryResult: Codable, Sendable {
        case pending
        case complete([CashuSwift.Proof])
        case failed(RecoveryFailure)

        public var proofs: [CashuSwift.Proof]? {
            if case .complete(let proofs) = self { return proofs }
            return nil
        }
    }

    public struct MintResult: Sendable {
        /// Retain the raw promises if recovery fails.
        public let promises: [CashuSwift.Promise]
        public let recovery: RecoveryResult
    }

    public struct MeltResult: Sendable {
        /// Payment status is independent from verification of the returned change.
        public let quote: MeltQuote
        public let changeRecovery: RecoveryResult
    }
}
