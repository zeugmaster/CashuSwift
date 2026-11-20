import Foundation

extension CashuSwift {
    /// Sensitive recovery material. Store securely until the send has been reconciled.
    public struct SendContext: Codable, Sendable {
        let version: Int
        public let mintURL: URL
        public let unit: String
        let memo: String?
        let inputs: [Proof]
        let keyset: Keyset
        let outputs: [Output]
        let blindingFactors: [String]
        let secrets: [String]
        let toSend: [Bool]
        let derivationCounterIncrease: Int

        public var counterIncrease: (keysetID: String, increase: Int) {
            (keyset.keysetID, derivationCounterIncrease)
        }
    }

    public enum SendRecoveryError: Swift.Error {
        case invalidContext, invalidResponse
    }

    /// Submit once. On an ambiguous failure keep the inputs reserved and use `restoreSend`.
    /// This never changes a caller's counters or proof states.
    public static func send(context: SendContext, from mint: Mint,
                            session: URLSession = .shared) async throws -> SendResult {
        try validateSendContext(context, mint: mint)
        let response = try await Network.post(url: mint.url.appending(path: "v1/swap"),
            body: SwapRequest(inputs: stripDLEQ(context.inputs), outputs: context.outputs),
            expected: SwapResponse.self, session: session)
        return try recoverSend(signatures: response.signatures, context: context)
    }

    /// NUT-09 recovery of the exact saved outputs; never resubmits the swap.
    /// Nil means no signatures are available yet, not that inputs are safe to reuse.
    public static func restoreSend(context: SendContext, from mint: Mint,
                                   session: URLSession = .shared) async throws -> SendResult? {
        try validateSendContext(context, mint: mint)
        let response = try await Network.post(url: mint.url.appending(path: "v1/restore"),
            body: RestoreRequest(outputs: context.outputs), expected: RestoreResponse.self, session: session)
        guard response.outputs.count == response.signatures.count else { throw SendRecoveryError.invalidResponse }
        if response.outputs.isEmpty { return nil }
        var signatures: [String: Promise] = [:]
        let expected = Dictionary(uniqueKeysWithValues: context.outputs.map { ($0.B_, $0) })
        for (output, signature) in zip(response.outputs, response.signatures) {
            guard let original = expected[output.B_], original.id == output.id, original.amount == output.amount,
                  signatures.updateValue(signature, forKey: output.B_) == nil else {
                throw SendRecoveryError.invalidResponse
            }
        }
        guard signatures.count == context.outputs.count else { throw SendRecoveryError.invalidResponse }
        return try recoverSend(signatures: context.outputs.compactMap { signatures[$0.B_] }, context: context)
    }

    private static func validateSendContext(_ context: SendContext, mint: Mint) throws {
        let count = context.outputs.count
        guard context.version == 1, context.mintURL == mint.url, count > 0,
              !context.inputs.isEmpty, context.keyset.unit == context.unit,
              context.blindingFactors.count == count, context.secrets.count == count,
              context.toSend.count == count, context.toSend.contains(true),
              context.derivationCounterIncrease >= 0,
              Set(context.outputs.map(\.B_)).count == count,
              context.outputs.allSatisfy({ $0.id == context.keyset.keysetID && $0.amount > 0 }),
              Set(context.secrets).count == count else { throw SendRecoveryError.invalidContext }
    }

    private static func recoverSend(signatures: [Promise], context: SendContext) throws -> SendResult {
        guard signatures.count == context.outputs.count,
              zip(signatures, context.outputs).allSatisfy({ $0.id == $1.id && $0.amount == $1.amount }) else {
            throw SendRecoveryError.invalidResponse
        }
        let proofs = try Crypto.unblindPromises(signatures, blindingFactors: context.blindingFactors,
                                                secrets: context.secrets, keyset: context.keyset)
        let send = zip(proofs, context.toSend).filter { $0.1 }.map { $0.0 }
        let keep = zip(proofs, context.toSend).filter { !$0.1 }.map { $0.0 }
        let dleq = try Crypto.checkDLEQ(for: proofs, with: Mint(url: context.mintURL, keysets: [context.keyset]))
        guard dleq != .fail else { throw SendRecoveryError.invalidResponse }
        return SendResult(token: Token(proofs: [context.mintURL.absoluteString: send.withShortKeysetID()],
                                        unit: context.unit, memo: context.memo),
                          send: send, change: keep, outputDLEQ: dleq, counterIncrease: context.counterIncrease)
    }
}
