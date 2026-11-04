import Foundation
import secp256k1

extension CashuSwift {
    /// Persist before distributing a signing package. Contains private output keys and
    /// blinding factors: send co-signers only the package, never this recovery material.
    public struct PreparedMint<Quote: MintQuoteResponse>: Codable, Sendable {
        public let mintURL: URL
        public let quote: Quote
        public let keyset: Keyset
        public let outputs: [Output]
        public let blindingFactors: [String]
        public let secrets: [String]
        /// Persist this keyset counter before submitting; nil for random outputs.
        public let nextCounter: Int?

        public func transaction() throws -> Transaction {
            try Transaction(mintQuote: quote, outputs: outputs)
        }

        func validate() throws {
            guard keyset.version == .v3, keyset.validID, keyset.unit == quote.unit,
                  !outputs.isEmpty, outputs.count == secrets.count, outputs.count == blindingFactors.count,
                  Set(outputs.map(\.B_)).count == outputs.count else {
                throw CashuError.inputError("invalid prepared v3 mint")
            }
            if let nextCounter {
                let (expected, overflow) = keyset.derivationCounter.addingReportingOverflow(outputs.count)
                guard keyset.derivationCounter >= 0, !overflow, expected == nextCounter else {
                    throw CashuError.inputError("invalid prepared mint counter")
                }
            }
            for (i, output) in outputs.enumerated() {
                guard output.id == keyset.keysetID, keyset.keys[String(output.amount)] != nil else {
                    throw CashuError.invalidAmount
                }
                let k = try Crypto.PrivateKey(dataRepresentation: secrets[i].bytes)
                let r = try Crypto.BLS.scalar(fromHex: blindingFactors[i])
                let expected = Crypto.BLS.blind(secretBytes: Array(k.publicKey.dataRepresentation), r: r)
                guard try expected.compressedBytes == Crypto.BLS.g1Point(fromHex: output.B_).compressedBytes else {
                    throw CashuError.inputError("prepared mint output does not match recovery material")
                }
            }
            _ = try transaction().transcript()
        }
    }

    /// Prepares a v3 issuance for external co-signers, without contacting the mint.
    /// Refresh the quote first, serialize issuances per quote, and persist the result
    /// and its nextCounter before sharing signatures or submitting it.
    public static func prepareMint<Quote: MintQuoteResponse>(
        quote: Quote, from mint: Mint, amount: Int, seed: String?, preferredDistribution: [Int]? = nil
    ) throws -> PreparedMint<Quote> {
        guard quote.quotePubkey != nil else { throw CashuError.quoteSigningKeyRequired }
        let prepared = try mintOutputs(amount: amount, unit: quote.unit, mint: mint, seed: seed,
                                       preferredDistribution: preferredDistribution)
        let next: Int?
        if seed != nil {
            let (value, overflow) = prepared.keyset.derivationCounter.addingReportingOverflow(prepared.material.outputs.count)
            guard !overflow else { throw CashuError.invalidAmount }
            next = value
        } else { next = nil }
        let result = PreparedMint(mintURL: mint.url, quote: quote, keyset: prepared.keyset,
                                  outputs: prepared.material.outputs, blindingFactors: prepared.material.blindingFactors,
                                  secrets: prepared.material.secrets, nextCounter: next)
        try result.validate()
        return result
    }

    /// Executes the exact prepared issuance with a completed script-path signing package.
    /// On an ambiguous transport outcome retain the preparation and restore its outputs.
    public static func mint<Quote: MintQuoteResponse>(
        prepared: PreparedMint<Quote>, from mint: Mint, signingPackage: SigningPackage, preimage: String? = nil
    ) async throws -> IssueResult {
        guard mint.url == prepared.mintURL else { throw CashuError.inputError("prepared mint belongs to another mint") }
        try prepared.validate()
        try signingPackage.validate()
        guard signingPackage.transcript == String(bytes: try prepared.transaction().transcript()),
              signingPackage.spends.count == 1, signingPackage.spends[0].input == 0 else {
            throw CashuError.inputError("signing package does not match the prepared mint")
        }
        let witness = try signingPackage.witness(for: 0, preimage: preimage)
        let body = SignedMintExecutionBody(quote: prepared.quote.quote, outputs: prepared.outputs,
                                           signature: try witness.stringJSON())
        let response = try await Network.post(url: mint.url.appending(path: "v1/mint/\(prepared.quote.method.rawValue)"),
                                               body: body, expected: MintExecutionResponse.self)
        return try recoverMint(promises: response.signatures, prepared: prepared)
    }

    /// Verifies and unblinds saved promises against the original keyset snapshot.
    public static func recoverMint<Quote: MintQuoteResponse>(
        promises: [Promise], prepared: PreparedMint<Quote>
    ) throws -> IssueResult {
        try prepared.validate()
        guard promises.count == prepared.outputs.count,
              zip(promises, prepared.outputs).allSatisfy({ $0.id == $1.id && $0.amount == $1.amount }) else {
            throw CashuError.inputError("mint promises do not match the prepared outputs")
        }
        let proofs = try Crypto.unblindPromises(promises, blindingFactors: prepared.blindingFactors,
                                                 secrets: prepared.secrets, keyset: prepared.keyset)
        return IssueResult(proofs: proofs, dleqResult: .valid)
    }

    /// Recovers a submitted preparation through NUT-09 without issuing again.
    /// An empty result means no signatures are available yet; it does not authorize a retry.
    public static func restoreMint<Quote: MintQuoteResponse>(
        prepared: PreparedMint<Quote>, from mint: Mint
    ) async throws -> IssueResult {
        guard mint.url == prepared.mintURL else { throw CashuError.inputError("prepared mint belongs to another mint") }
        try prepared.validate()
        let response = try await Network.post(url: mint.url.appending(path: "v1/restore"),
            body: RestoreRequest(outputs: prepared.outputs), expected: RestoreResponse.self)
        guard response.outputs.count == response.signatures.count else {
            throw CashuError.inputError("restore outputs and signatures differ in count")
        }
        if response.outputs.isEmpty { return IssueResult(proofs: [], dleqResult: .valid) }
        var matches = [String: Promise]()
        let expected = Set(prepared.outputs.map(\.B_))
        for (output, signature) in zip(response.outputs, response.signatures) {
            guard expected.contains(output.B_), matches[output.B_] == nil else {
                throw CashuError.inputError("restore returned an unexpected or repeated output")
            }
            matches[output.B_] = signature
        }
        let ordered = prepared.outputs.compactMap { matches[$0.B_] }
        return try recoverMint(promises: ordered, prepared: prepared)
    }
}
