//
//  Bolt12.swift
//  CashuSwift
//
//  NUT-25: BOLT12 Lightning offers.
//

import Foundation

extension CashuSwift {
    /// BOLT12 (Lightning offer) payment method per NUT-25.
    ///
    /// Unlike BOLT11, a BOLT12 offer can be paid multiple times. The mint tracks
    /// `amountPaid` and `amountIssued` and the wallet may call `mint` any number of
    /// times for the same quote up to the unfunded delta.
    public enum Bolt12 {

        public static let id: PaymentMethodID = .bolt12

        // MARK: - Quote requests

        /// Wallet → mint: request a BOLT12 mint quote.
        ///
        /// `pubkey` is required by NUT-25 (the mint MUST refuse the quote without one).
        /// Wallets SHOULD use a fresh pubkey per quote to prevent linkability.
        public struct MintQuoteRequest: CashuSwift.MintQuoteRequest {
            public let unit: String
            public let amount: Int?
            public let description: String?
            public let pubkey: String

            public var method: PaymentMethodID { .bolt12 }

            public init(unit: String, amount: Int?, description: String? = nil, pubkey: String) {
                self.unit = unit
                self.amount = amount
                self.description = description
                self.pubkey = pubkey
            }

            enum CodingKeys: String, CodingKey {
                case unit, amount, description, pubkey
            }
        }

        public struct MeltQuoteRequest: CashuSwift.MeltQuoteRequest {
            public struct Options: Codable, Sendable, Hashable {
                public struct Amountless: Codable, Sendable, Hashable {
                    public let amountMsat: Int
                    public init(amountMsat: Int) { self.amountMsat = amountMsat }
                    enum CodingKeys: String, CodingKey { case amountMsat = "amount_msat" }
                }
                public let amountless: Amountless?
                public init(amountless: Amountless?) { self.amountless = amountless }
            }

            public let unit: String
            public let request: String
            public let options: Options?

            public var method: PaymentMethodID { .bolt12 }

            public init(unit: String, request: String, options: Options? = nil) {
                self.unit = unit
                self.request = request
                self.options = options
            }

            enum CodingKeys: String, CodingKey {
                case unit, request, options
            }
        }

        // MARK: - Quote responses

        /// Mint → wallet: BOLT12 mint quote (offer).
        ///
        /// `amountPaid - amountIssued` is the remaining amount the wallet can mint.
        public struct MintQuote: CashuSwift.MintQuoteResponse {
            public let quote: String
            public let request: String
            public let amount: Int?
            public let unit: String
            public let expiry: Int?
            public let pubkey: String
            public let amountPaid: Int
            public let amountIssued: Int

            /// NUT-25 BOLT12 mint quote responses do not carry a `state` field.
            public var state: QuoteState? { nil }

            public var method: PaymentMethodID { .bolt12 }

            /// Amount remaining to be minted from this quote.
            public var mintableAmount: Int { max(amountPaid - amountIssued, 0) }

            public init(quote: String,
                        request: String,
                        amount: Int?,
                        unit: String,
                        expiry: Int?,
                        pubkey: String,
                        amountPaid: Int,
                        amountIssued: Int) {
                self.quote = quote
                self.request = request
                self.amount = amount
                self.unit = unit
                self.expiry = expiry
                self.pubkey = pubkey
                self.amountPaid = amountPaid
                self.amountIssued = amountIssued
            }

            enum CodingKeys: String, CodingKey {
                case quote, request, amount, unit, expiry, pubkey
                case amountPaid = "amount_paid"
                case amountIssued = "amount_issued"
            }
        }

        public struct MeltQuote: CashuSwift.MeltQuoteResponse {
            public let quote: String
            public let request: String?
            public let amount: Int
            public let unit: String
            public let feeReserve: Int
            public let state: QuoteState?
            public let expiry: Int?
            public let paymentPreimage: String?
            public let change: [Promise]?

            public var method: PaymentMethodID { .bolt12 }

            public init(quote: String,
                        request: String? = nil,
                        amount: Int,
                        unit: String,
                        feeReserve: Int,
                        state: QuoteState?,
                        expiry: Int?,
                        paymentPreimage: String? = nil,
                        change: [Promise]? = nil) {
                self.quote = quote
                self.request = request
                self.amount = amount
                self.unit = unit
                self.feeReserve = feeReserve
                self.state = state
                self.expiry = expiry
                self.paymentPreimage = paymentPreimage
                self.change = change
            }

            public func requiredInputAmount(inputFee: Int) throws -> Int {
                amount + feeReserve + inputFee
            }

            enum CodingKeys: String, CodingKey {
                case quote, request, amount, unit, state, expiry, change
                case feeReserve = "fee_reserve"
                case paymentPreimage = "payment_preimage"
            }
        }

        // MARK: - Entry points

        /// Requests a BOLT12 mint quote.
        public static func requestMintQuote(_ request: MintQuoteRequest,
                                            from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._requestMintQuote(request, from: mint, as: MintQuote.self)
        }

        public static func requestMeltQuote(_ request: MeltQuoteRequest,
                                            from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._requestMeltQuote(request, from: mint, as: MeltQuote.self)
        }

        public static func mintQuoteState(_ id: String,
                                          from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._mintQuoteState(quoteID: id, method: .bolt12, from: mint, as: MintQuote.self)
        }

        public static func meltQuoteState(_ id: String,
                                          from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._meltQuoteState(quoteID: id, method: .bolt12, from: mint, as: MeltQuote.self)
        }

        /// Issues `amount` ecash against a BOLT12 mint quote.
        ///
        /// `amount` must be ≤ `quote.mintableAmount` (the difference between the
        /// amount paid into the offer and the amount already issued). For multiple
        /// partial mints, refresh the quote between calls via `mintQuoteState`.
        public static func mint(quote: MintQuote,
                                from mint: Mint,
                                amount: Int,
                                seed: String?,
                                preferredDistribution: [Int]? = nil) async throws -> IssueResult {
            guard amount > 0 else {
                throw CashuError.invalidAmount
            }
            guard amount <= quote.mintableAmount else {
                throw CashuError.amountOutsideOfLimitRange
            }
            return try await CashuSwift._mint(
                quote: quote,
                amount: amount,
                mint: mint,
                seed: seed,
                preferredDistribution: preferredDistribution
            ) { quoteID, outputs in
                StandardMintExecutionBody(quote: quoteID, outputs: outputs)
            }
        }

        public static func melt(quote: MeltQuote,
                                from mint: Mint,
                                proofs: [Proof],
                                timeout: Double = 600,
                                blankOutputs: (outputs: [Output],
                                               blindingFactors: [String],
                                               secrets: [String])? = nil,
                                preferAsync: Bool? = nil) async throws -> MeltResult<MeltQuote> {
            try await CashuSwift._melt(
                quote: quote,
                mint: mint,
                proofs: proofs,
                timeout: timeout,
                blankOutputs: blankOutputs
            ) { quoteID, inputs, outputs in
                StandardMeltExecutionBody(quote: quoteID, inputs: inputs, outputs: outputs, preferAsync: preferAsync)
            }
        }

        public static func meltState(_ id: String,
                                     from mint: Mint,
                                     blankOutputs: (outputs: [Output],
                                                    blindingFactors: [String],
                                                    secrets: [String])? = nil) async throws -> MeltResult<MeltQuote> {
            try await CashuSwift._meltState(
                quoteID: id,
                method: .bolt12,
                mint: mint,
                blankOutputs: blankOutputs,
                as: MeltQuote.self
            )
        }
    }
}
