//
//  PaymentBackendOperations.swift
//  CashuSwift
//
//  Method-agnostic mint and melt operations. Each payment-method namespace
//  (`Bolt11`, `Bolt12`, `Generic`) provides typed entry points that delegate
//  into the generic implementations below.
//

import Foundation
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "PaymentBackend")

extension CashuSwift {

    // MARK: - Wire bodies (shared across all methods)

    struct MintExecutionRequest: Codable {
        let quote: String
        let outputs: [Output]
    }

    struct MintExecutionResponse: Codable {
        let signatures: [Promise]
    }

    struct MeltExecutionRequest: Codable {
        let quote: String
        let inputs: [Proof]
        let outputs: [Output]?
        let preferAsync: Bool?

        enum CodingKeys: String, CodingKey {
            case quote, inputs, outputs
            case preferAsync = "prefer_async"
        }
    }

    // MARK: - Quote requests

    /// Sends a mint quote request to the mint and decodes the response as `Response`.
    static func _requestMintQuote<Request: MintQuoteRequest, Response: MintQuoteResponse>(
        _ request: Request,
        from mint: MintRepresenting,
        as responseType: Response.Type
    ) async throws -> Response {
        guard mint.keysets.contains(where: { $0.unit == request.unit }) else {
            throw CashuError.unitIsNotSupported(
                "No keyset on mint \(mint.url.absoluteString) for unit \(request.unit.uppercased())."
            )
        }
        let url = mint.url.appending(path: "/v1/mint/quote/\(request.method.rawValue)")
        return try await Network.post(url: url, body: request, expected: Response.self)
    }

    /// Sends a melt quote request to the mint and decodes the response as `Response`.
    static func _requestMeltQuote<Request: MeltQuoteRequest, Response: MeltQuoteResponse>(
        _ request: Request,
        from mint: MintRepresenting,
        as responseType: Response.Type
    ) async throws -> Response {
        guard mint.keysets.contains(where: { $0.unit == request.unit }) else {
            throw CashuError.unitIsNotSupported(
                "No keyset on mint \(mint.url.absoluteString) for unit \(request.unit.uppercased())."
            )
        }
        let url = mint.url.appending(path: "/v1/melt/quote/\(request.method.rawValue)")
        return try await Network.post(url: url, body: request, expected: Response.self)
    }

    /// Fetches the current state of a mint quote.
    static func _mintQuoteState<Response: MintQuoteResponse>(
        quoteID: String,
        method: PaymentMethodID,
        from mint: MintRepresenting,
        as responseType: Response.Type
    ) async throws -> Response {
        let url = mint.url.appending(path: "/v1/mint/quote/\(method.rawValue)/\(quoteID)")
        return try await Network.get(url: url, expected: Response.self)
    }

    /// Fetches the current state of a melt quote.
    static func _meltQuoteState<Response: MeltQuoteResponse>(
        quoteID: String,
        method: PaymentMethodID,
        from mint: MintRepresenting,
        as responseType: Response.Type
    ) async throws -> Response {
        let url = mint.url.appending(path: "/v1/melt/quote/\(method.rawValue)/\(quoteID)")
        return try await Network.get(url: url, expected: Response.self)
    }

    // MARK: - Mint (issue)

    /// Issues ecash proofs against a paid mint quote.
    ///
    /// - Parameters:
    ///   - quote: The (paid) mint quote.
    ///   - amount: Amount of ecash to issue, in the quote's unit. For BOLT11 this is the
    ///     quote's amount; for BOLT12 it can be any value up to `amountPaid - amountIssued`.
    ///   - mint: The mint to issue from.
    ///   - seed: Optional seed for deterministic secret generation.
    ///   - preferredDistribution: Optional explicit denomination split summing to `amount`.
    static func _mint<Quote: MintQuoteResponse>(
        quote: Quote,
        amount: Int,
        mint: Mint,
        seed: String?,
        preferredDistribution: [Int]? = nil
    ) async throws -> IssueResult {
        let distribution: [Int]
        if let preferredDistribution {
            guard preferredDistribution.reduce(0, +) == amount else {
                throw CashuError.preferredDistributionMismatch(
                    "Specified preferred distribution does not add up to the requested amount."
                )
            }
            distribution = preferredDistribution
        } else {
            distribution = CashuSwift.splitIntoBase2Numbers(amount)
        }

        guard let activeKeyset = mint.keysets.first(where: { $0.active == true && $0.unit == quote.unit }) else {
            throw CashuError.noActiveKeysetForUnit(
                "Could not determine an ACTIVE keyset for unit \(quote.unit.uppercased())."
            )
        }

        var outputs = (outputs: [Output](), blindingFactors: [""], secrets: [""])
        if let seed {
            outputs = try Crypto.generateOutputs(
                amounts: distribution,
                keysetID: activeKeyset.keysetID,
                deterministicFactors: (seed: seed, counter: activeKeyset.derivationCounter)
            )
        } else {
            outputs = try Crypto.generateOutputs(
                amounts: distribution,
                keysetID: activeKeyset.keysetID
            )
        }

        let body = MintExecutionRequest(quote: quote.quote, outputs: outputs.outputs)
        let url = mint.url.appending(path: "/v1/mint/\(quote.method.rawValue)")
        let response = try await Network.post(url: url, body: body, expected: MintExecutionResponse.self)

        let proofs = try Crypto.unblindPromises(
            response.signatures,
            blindingFactors: outputs.blindingFactors,
            secrets: outputs.secrets,
            keyset: activeKeyset
        )

        let dleqResult = try Crypto.checkDLEQ(for: proofs, with: mint)
        return IssueResult(proofs: proofs, dleqResult: dleqResult)
    }

    // MARK: - Melt

    /// Melts ecash proofs to fulfill a melt quote (e.g. pay a Lightning invoice).
    ///
    /// - Parameters:
    ///   - quote: The melt quote describing the payment to be made.
    ///   - mint: The mint to melt with.
    ///   - proofs: Inputs covering `quote.amount + quote.feeReserve + inputFee`.
    ///   - timeout: Request timeout in seconds; synchronous payment methods may need long values.
    ///   - blankOutputs: Optional blank outputs for receiving change from overpaid LN fees.
    ///   - preferAsync: NUT-05 async preference flag, sent through to the mint.
    static func _melt<Quote: MeltQuoteResponse>(
        quote: Quote,
        mint: Mint,
        proofs: [Proof],
        timeout: Double = 600,
        blankOutputs: (outputs: [Output], blindingFactors: [String], secrets: [String])? = nil,
        preferAsync: Bool? = nil
    ) async throws -> MeltResult<Quote> {

        let proofUnit = try singleUnit(for: proofs, of: mint)

        guard quote.unit == proofUnit else {
            throw CashuError.unitError(
                "Melt quote unit '\(quote.unit)' does not match input proof unit '\(proofUnit)'."
            )
        }

        if let blankOutputs, !blankOutputs.outputs.isEmpty {
            let outputUnits = try Set(blankOutputs.outputs.map { output -> String in
                guard let outputKeyset = mint.keysets.first(where: { $0.keysetID == output.id }) else {
                    throw CashuError.unitError(
                        "Blank output keyset \(output.id) is not associated with mint \(mint.url.absoluteString)."
                    )
                }
                return outputKeyset.unit
            })
            guard outputUnits == Set([proofUnit]) else {
                throw CashuError.unitError(
                    "Blank output units \(outputUnits) do not match input proof unit '\(proofUnit)'."
                )
            }
        }

        let lightningFee = quote.feeReserve
        let inputFee = try calculateFee(for: proofs, of: mint)
        let targetAmount = quote.amount + lightningFee + inputFee

        guard sum(proofs) >= targetAmount else {
            throw CashuError.insufficientInputs("Input sum does not cover total amount needed: \(targetAmount)")
        }

        logger.debug("Attempting melt with quote amount: \(quote.amount), LN fee reserve: \(lightningFee), input fee: \(inputFee).")

        guard let keyset = activeKeysetForUnit(proofUnit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit \(proofUnit)")
        }

        let noDLEQ = proofs.map {
            Proof(keysetID: $0.keysetID, amount: $0.amount, secret: $0.secret, C: $0.C, dleq: nil, witness: nil)
        }

        let body = MeltExecutionRequest(
            quote: quote.quote,
            inputs: noDLEQ,
            outputs: blankOutputs.map { $0.outputs },
            preferAsync: preferAsync
        )

        let url = mint.url.appending(path: "/v1/melt/\(quote.method.rawValue)")
        let response = try await Network.post(url: url, body: body, expected: Quote.self, timeout: timeout)

        let change: [Proof]?
        if let promises = response.change, let blankOutputs {
            guard promises.count <= blankOutputs.outputs.count else {
                throw Crypto.Error.unblinding("could not unblind blank outputs for fee return")
            }
            do {
                change = try Crypto.unblindPromises(
                    promises,
                    blindingFactors: Array(blankOutputs.blindingFactors.prefix(promises.count)),
                    secrets: Array(blankOutputs.secrets.prefix(promises.count)),
                    keyset: keyset
                )
            } catch {
                logger.error("Unable to unblind change from melt operation due to error: \(error). Operation will still return successful.")
                change = nil
            }
        } else {
            change = nil
        }

        let dleqResult: Crypto.DLEQVerificationResult
        if let change {
            dleqResult = try Crypto.checkDLEQ(for: change, with: mint)
            if case .noData = dleqResult {
                logger.warning("Melt change DLEQ check could not be performed due to missing data.")
            }
        } else {
            dleqResult = .valid
        }

        return MeltResult(quote: response, change: change, dleqResult: dleqResult)
    }

    /// Re-checks an existing melt quote's state and unblinds any change that the
    /// mint has produced for overpaid fees.
    static func _meltState<Quote: MeltQuoteResponse>(
        quoteID: String,
        method: PaymentMethodID,
        mint: Mint,
        blankOutputs: (outputs: [Output], blindingFactors: [String], secrets: [String])? = nil,
        as responseType: Quote.Type
    ) async throws -> MeltResult<Quote> {
        let url = mint.url.appending(path: "/v1/melt/quote/\(method.rawValue)/\(quoteID)")
        let quote = try await Network.get(url: url, expected: Quote.self)

        var change: [Proof]?

        switch quote.state {
        case .paid:
            guard let promises = quote.change else {
                logger.info("Melt quote contained no change promises.")
                return MeltResult(quote: quote, change: [], dleqResult: .valid)
            }
            guard let blankOutputs else {
                logger.warning("Melt quote returned change but no blank outputs were supplied to unblind it.")
                return MeltResult(quote: quote, change: [], dleqResult: .valid)
            }

            let ids = Set(blankOutputs.outputs.map { $0.id })
            guard let id = ids.first, ids.count == 1 else {
                throw CashuError.unknownError("Could not determine singular keyset id from blankOutput list. result: \(ids)")
            }
            guard let keyset = mint.keysets.first(where: { $0.keysetID == id }) else {
                throw CashuError.unknownError("Could not find keyset for ID \(id)")
            }

            do {
                change = try Crypto.unblindPromises(
                    promises,
                    blindingFactors: Array(blankOutputs.blindingFactors.prefix(promises.count)),
                    secrets: Array(blankOutputs.secrets.prefix(promises.count)),
                    keyset: keyset
                )
            } catch {
                logger.error("Unable to unblind change from melt state due to error: \(error). Operation will still return successful.")
                change = []
            }

        case .pending, .unpaid, .issued, .none:
            change = nil
        }

        let dleqResult: Crypto.DLEQVerificationResult
        if let change, !change.isEmpty {
            dleqResult = try Crypto.checkDLEQ(for: change, with: mint)
            if case .noData = dleqResult {
                logger.warning("Melt state DLEQ check could not be performed due to missing data.")
            }
        } else {
            dleqResult = .valid
        }

        return MeltResult(quote: quote, change: change, dleqResult: dleqResult)
    }
}
