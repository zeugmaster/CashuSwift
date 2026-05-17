//
//  Bolt11.swift
//  CashuSwift
//
//  NUT-23: BOLT11 Lightning invoices.
//

import Foundation

extension CashuSwift {
    /// BOLT11 (Lightning invoice) payment method per NUT-23.
    public enum Bolt11 {

        public static let id: PaymentMethodID = .bolt11

        // MARK: - Quote requests

        /// Wallet → mint: request a mint quote (Lightning invoice for the user to pay).
        public struct MintQuoteRequest: CashuSwift.MintQuoteRequest {
            public let unit: String
            public let amount: Int
            public let description: String?

            public var method: PaymentMethodID { .bolt11 }

            public init(unit: String, amount: Int, description: String? = nil) {
                self.unit = unit
                self.amount = amount
                self.description = description
            }

            enum CodingKeys: String, CodingKey {
                case unit, amount, description
            }
        }

        /// Wallet → mint: request a melt quote (have the mint pay a Lightning invoice).
        public struct MeltQuoteRequest: CashuSwift.MeltQuoteRequest {
            public struct Options: Codable, Sendable, Hashable {
                /// Amountless invoice options (NUT-23 §Melt Quote).
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

            public var method: PaymentMethodID { .bolt11 }

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

        /// Mint → wallet: mint quote response, including the BOLT11 invoice to pay.
        public struct MintQuote: CashuSwift.MintQuoteResponse {
            public let quote: String
            public let request: String
            public let amount: Int?
            public let unit: String
            public let state: QuoteState?
            public let expiry: Int?

            public var method: PaymentMethodID { .bolt11 }

            public init(quote: String,
                        request: String,
                        amount: Int?,
                        unit: String,
                        state: QuoteState?,
                        expiry: Int?) {
                self.quote = quote
                self.request = request
                self.amount = amount
                self.unit = unit
                self.state = state
                self.expiry = expiry
            }

            enum CodingKeys: String, CodingKey {
                case quote, request, amount, unit, state, expiry
            }
        }

        /// Mint → wallet: melt quote response with fee reserve and (after payment) preimage.
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

            public var method: PaymentMethodID { .bolt11 }

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

            enum CodingKeys: String, CodingKey {
                case quote, request, amount, unit, state, expiry, change
                case feeReserve = "fee_reserve"
                case paymentPreimage = "payment_preimage"
            }
        }

        // MARK: - Entry points

        /// Requests a BOLT11 mint quote — a Lightning invoice for the user to pay.
        public static func requestMintQuote(_ request: MintQuoteRequest,
                                            from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._requestMintQuote(request, from: mint, as: MintQuote.self)
        }

        /// Requests a BOLT11 melt quote — asks the mint what it will charge to pay an invoice.
        public static func requestMeltQuote(_ request: MeltQuoteRequest,
                                            from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._requestMeltQuote(request, from: mint, as: MeltQuote.self)
        }

        /// Re-fetches the current state of a mint quote.
        public static func mintQuoteState(_ id: String,
                                          from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._mintQuoteState(quoteID: id, method: .bolt11, from: mint, as: MintQuote.self)
        }

        /// Re-fetches the current state of a melt quote.
        public static func meltQuoteState(_ id: String,
                                          from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._meltQuoteState(quoteID: id, method: .bolt11, from: mint, as: MeltQuote.self)
        }

        /// Issues ecash proofs against a paid BOLT11 mint quote.
        ///
        /// The amount to mint is taken from `quote.amount`, which BOLT11 mint quotes always provide.
        public static func mint(quote: MintQuote,
                                from mint: Mint,
                                seed: String?,
                                preferredDistribution: [Int]? = nil) async throws -> IssueResult {
            guard let amount = quote.amount else {
                throw CashuError.missingRequestDetail("BOLT11 mint quote is missing the amount field.")
            }
            return try await CashuSwift._mint(
                quote: quote,
                amount: amount,
                mint: mint,
                seed: seed,
                preferredDistribution: preferredDistribution
            )
        }

        /// Melts proofs to pay the BOLT11 invoice referenced by the quote.
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
                blankOutputs: blankOutputs,
                preferAsync: preferAsync
            )
        }

        /// Re-checks an existing melt quote's state and unblinds any change.
        public static func meltState(_ id: String,
                                     from mint: Mint,
                                     blankOutputs: (outputs: [Output],
                                                    blindingFactors: [String],
                                                    secrets: [String])? = nil) async throws -> MeltResult<MeltQuote> {
            try await CashuSwift._meltState(
                quoteID: id,
                method: .bolt11,
                mint: mint,
                blankOutputs: blankOutputs,
                as: MeltQuote.self
            )
        }

        // MARK: - Utilities

        /// Parses a BOLT11 invoice and returns its amount in satoshis (0 if the invoice is amountless).
        public static func satAmount(from invoice: String) throws -> Int {
            let lower = invoice.lowercased()
            guard let range = lower.range(of: "1", options: .backwards) else {
                throw CashuError.bolt11InvalidInvoiceError("")
            }
            let endIndex = range.lowerBound
            let hrp = String(lower[..<endIndex])

            var prefixLength: Int = 0
            if hrp.hasPrefix("lnbcrt") {
                prefixLength = 6
            } else if hrp.hasPrefix("lntbs") {
                prefixLength = 5
            } else if hrp.hasPrefix("lnbc") {
                prefixLength = 4
            } else if hrp.hasPrefix("lntb") {
                prefixLength = 4
            } else {
                throw CashuError.bolt11InvalidInvoiceError("")
            }

            let amountPart = String(hrp.dropFirst(prefixLength))

            if amountPart.isEmpty { return 0 }

            let validMultipliers: Set<Character> = ["m", "u", "n", "p"]
            let multiplier: Character?
            let numString: String

            if let lastChar = amountPart.last, validMultipliers.contains(lastChar) {
                multiplier = lastChar
                numString = String(amountPart.dropLast())
            } else {
                multiplier = nil
                numString = amountPart
            }

            guard var n = Double(numString) else {
                throw CashuError.bolt11InvalidInvoiceError("")
            }

            switch multiplier {
            case "m": n *= 100000
            case "u": n *= 100
            case "n": n *= 0.1
            case "p": n *= 0.0001
            case nil: n *= 100000000
            default:
                throw CashuError.bolt11InvalidInvoiceError("")
            }

            return n >= 1 ? Int(n) : 0
        }
    }
}
