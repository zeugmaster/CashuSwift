//
//  QuoteOffers.swift
//  CashuSwift
//
//  NUT-XX: wallet-side claiming of quote offers.
//
//  A mint offer is claimed by requesting a NUT-04 mint quote that references the
//  offer's ticket and locks the quote to a mandatory NUT-20 pubkey. A melt offer
//  is claimed by requesting a NUT-05 melt quote with the ticket as the payment
//  request; melt execution for claimed offers is always asynchronous, so the
//  wallet monitors the quote state until completion and can present the quote ID
//  as proof that it initiated the payment.
//
//  The offer's method is dynamic (e.g. "branch"), so requests and responses use
//  the method-agnostic `Generic` types; the wire shape of a mint claim is
//  `{unit, amount, pubkey, ticket}` and of a melt claim `{unit, request}`.
//

import Foundation

extension CashuSwift {
    public enum QuoteOffers {

        /// Mint execution body carrying the NUT-20 signature: `{ quote, outputs, signature }`.
        public struct SignedMintExecutionBody: Codable, Sendable {
            public let quote: String
            public let outputs: [Output]
            public let signature: String

            public init(quote: String, outputs: [Output], signature: String) {
                self.quote = quote
                self.outputs = outputs
                self.signature = signature
            }
        }

        // MARK: - Key derivation

        /// Derives the deterministic NUT-20 quote-locking key `m/129373'/20'/0'/0'/{counter}`
        /// from the wallet seed. The wallet SHOULD use a fresh counter per quote request
        /// and persist the counter (or key) with the pending quote so it can sign at
        /// issuance and after restore.
        public static func quoteLockingKey(seed: String, counter: UInt32) throws -> (privateKey: Data, publicKey: String) {
            try Crypto.nut20QuoteLockingKey(seed: seed, counter: counter)
        }

        // MARK: - Claiming

        /// Claims a mint offer: requests a mint quote referencing the offer's ticket,
        /// locked to `pubkey`. The mint accepts the first claim for a ticket and
        /// rejects all subsequent ones.
        public static func requestMintQuote(offer: QuoteOffer,
                                            pubkey: String,
                                            from mint: Mint) async throws -> Generic.MintQuote {
            guard offer.operation == .mint else {
                throw CashuError.quoteOfferValidation("Offer operation is '\(offer.operation.rawValue)', expected 'mint'.")
            }
            guard !offer.isExpired() else {
                throw CashuError.quoteOfferExpired
            }
            guard !pubkey.isEmpty else {
                throw CashuError.quoteOfferRequiresPubkey
            }
            guard let amount = offer.amount, amount > 0 else {
                // The NUT-04 quote request of every method this library can claim
                // offers for requires an amount, so an amount-less mint offer is invalid.
                throw CashuError.quoteOfferValidation("Mint offer carries no amount.")
            }

            let request = Generic.MintQuoteRequest(
                method: offer.method,
                unit: offer.unit,
                amount: amount,
                extra: [
                    "pubkey": .string(pubkey),
                    "ticket": .string(offer.ticket),
                ]
            )
            return try await Generic.requestMintQuote(request, from: mint)
        }

        /// Claims a melt offer: requests a melt quote using the offer's ticket as the
        /// payment request. The resulting quote's amount is determined by the mint's
        /// payment backend from the ticket, not by the wallet.
        public static func requestMeltQuote(offer: QuoteOffer,
                                            from mint: Mint) async throws -> Generic.MeltQuote {
            guard offer.operation == .melt else {
                throw CashuError.quoteOfferValidation("Offer operation is '\(offer.operation.rawValue)', expected 'melt'.")
            }
            guard !offer.isExpired() else {
                throw CashuError.quoteOfferExpired
            }

            let request = Generic.MeltQuoteRequest(
                method: offer.method,
                unit: offer.unit,
                request: offer.ticket
            )
            return try await Generic.requestMeltQuote(request, from: mint)
        }

        // MARK: - Quote state

        public static func mintQuoteState(_ id: String,
                                          method: PaymentMethodID,
                                          from mint: Mint) async throws -> Generic.MintQuote {
            try await Generic.mintQuoteState(id, method: method, from: mint)
        }

        public static func meltState(_ id: String,
                                     method: PaymentMethodID,
                                     from mint: Mint,
                                     blankOutputs: (outputs: [Output],
                                                    blindingFactors: [String],
                                                    secrets: [String])? = nil) async throws -> MeltResult<Generic.MeltQuote> {
            try await Generic.meltState(id, method: method, from: mint, blankOutputs: blankOutputs)
        }

        // MARK: - Execution

        /// Issues ecash against a paid, claimed mint quote. Because claimed quotes are
        /// always locked, the execution body carries a NUT-20 signature produced with
        /// `quoteKey` — the private key whose public key was passed when claiming.
        public static func mint(quote: Generic.MintQuote,
                                from mint: Mint,
                                seed: String?,
                                quoteKey: Data,
                                amount: Int? = nil,
                                preferredDistribution: [Int]? = nil) async throws -> IssueResult {
            guard let amount = amount ?? quote.amount, amount > 0 else {
                throw CashuError.invalidAmount
            }
            return try await CashuSwift._mint(
                quote: quote,
                amount: amount,
                mint: mint,
                seed: seed,
                preferredDistribution: preferredDistribution
            ) { quoteID, outputs in
                let signature = try Crypto.nut20Signature(
                    quoteID: quoteID,
                    outputs: outputs,
                    privateKey: quoteKey
                )
                return SignedMintExecutionBody(quote: quoteID, outputs: outputs, signature: signature)
            }
        }

        /// Melts proofs to fulfill a claimed melt quote. Execution is always
        /// asynchronous per NUT-XX: the mint returns a `PENDING` state after
        /// validation and the wallet must monitor the quote via `meltState`.
        public static func melt(quote: Generic.MeltQuote,
                                from mint: Mint,
                                proofs: [Proof],
                                timeout: Double = 600,
                                blankOutputs: (outputs: [Output],
                                               blindingFactors: [String],
                                               secrets: [String])? = nil) async throws -> MeltResult<Generic.MeltQuote> {
            try await Generic.melt(
                quote: quote,
                from: mint,
                proofs: proofs,
                timeout: timeout,
                blankOutputs: blankOutputs
            )
        }
    }
}
