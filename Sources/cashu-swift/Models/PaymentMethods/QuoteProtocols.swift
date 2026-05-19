//
//  QuoteProtocols.swift
//  CashuSwift
//

import Foundation

extension CashuSwift {
    /// Lifecycle state of a mint or melt quote.
    ///
    /// Mint quotes (NUT-23 BOLT11) cycle through `unpaid` → `paid` → `issued`.
    /// Melt quotes cycle through `unpaid` → `pending` → `paid`. Some method-specific
    /// NUTs omit the `state` field (e.g. NUT-25 BOLT12 mint quotes, NUT-XX onchain
    /// mint quotes); in those cases the value is `nil` and the wallet should consult
    /// the method's own progress fields (e.g. `amountPaid` / `amountIssued`).
    public enum QuoteState: String, Codable, Sendable {
        case unpaid = "UNPAID"
        case pending = "PENDING"
        case paid = "PAID"
        case issued = "ISSUED"
    }

    /// Request to create a mint quote — the wallet asks the mint to issue a
    /// payment instrument (e.g. a Lightning invoice, a Bitcoin address) that the
    /// user can pay.
    ///
    /// Concrete conformances live in the per-method namespaces (`Bolt11`, `Bolt12`,
    /// `Generic`, future `Onchain`).
    public protocol MintQuoteRequest: Codable, Sendable {
        var method: PaymentMethodID { get }
        var unit: String { get }
    }

    /// Mint quote returned by the mint, including the payment instructions the
    /// user must fulfill before calling `mint`.
    public protocol MintQuoteResponse: Codable, Sendable {
        var method: PaymentMethodID { get }
        var quote: String { get }
        var request: String { get }
        var unit: String { get }
        var amount: Int? { get }
        var state: QuoteState? { get }
        var expiry: Int? { get }
    }

    /// Request to create a melt quote — the wallet asks the mint to make a
    /// payment on its behalf.
    public protocol MeltQuoteRequest: Codable, Sendable {
        var method: PaymentMethodID { get }
        var unit: String { get }
        var request: String { get }
    }

    /// Melt quote returned by the mint.
    ///
    /// Method-specific fee details (BOLT11/12 flat `fee_reserve`, onchain
    /// `fee_options` + `selected_estimated_blocks`) and method-specific payment
    /// proofs (BOLT11/12 `payment_preimage`, onchain `outpoint`) live on the
    /// concrete conforming types. The protocol exposes `requiredInputAmount(inputFee:)`
    /// so the generic melt core can compute the input sum the wallet must cover
    /// without baking in the BOLT11 fee model.
    public protocol MeltQuoteResponse: Codable, Sendable {
        var method: PaymentMethodID { get }
        var quote: String { get }
        var amount: Int { get }
        var unit: String { get }
        var state: QuoteState? { get }
        var expiry: Int? { get }
        var change: [Promise]? { get }

        /// The minimum total proof amount the wallet must include in the melt request,
        /// given a calculated keyset-derived `inputFee`. For methods with a flat fee
        /// reserve (BOLT11, BOLT12) this is `amount + fee_reserve + inputFee`.
        /// Methods with tiered fee options (onchain) throw if no option has been
        /// selected yet.
        func requiredInputAmount(inputFee: Int) throws -> Int
    }
}
