//
//  QuoteProtocols.swift
//  CashuSwift
//

import Foundation

extension CashuSwift {
    /// Lifecycle state of a mint or melt quote.
    ///
    /// Mint quotes (NUT-23 BOLT11) cycle through `unpaid` → `paid` → `issued`.
    /// Melt quotes cycle through `unpaid` → `pending` → `paid`. Bolt12 mint quotes
    /// per NUT-25 omit the `state` field entirely; in that case the value is `nil`
    /// and the wallet should consult `amountPaid` / `amountIssued` instead.
    public enum QuoteState: String, Codable, Sendable {
        case unpaid = "UNPAID"
        case pending = "PENDING"
        case paid = "PAID"
        case issued = "ISSUED"
    }

    /// Request to create a mint quote — the wallet asks the mint to issue a
    /// payment instrument (e.g. a Lightning invoice) that the user can pay.
    ///
    /// Concrete conformances live in `Bolt11`, `Bolt12`, and `Generic` namespaces.
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
    /// payment on its behalf (e.g. pay a Lightning invoice).
    public protocol MeltQuoteRequest: Codable, Sendable {
        var method: PaymentMethodID { get }
        var unit: String { get }
        var request: String { get }
    }

    /// Melt quote returned by the mint, including the amount and fee reserve
    /// the wallet must cover with input proofs.
    public protocol MeltQuoteResponse: Codable, Sendable {
        var method: PaymentMethodID { get }
        var quote: String { get }
        var amount: Int { get }
        var unit: String { get }
        var feeReserve: Int { get }
        var state: QuoteState? { get }
        var expiry: Int? { get }
        var paymentPreimage: String? { get }
        var change: [Promise]? { get }
    }
}
