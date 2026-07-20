//
//  QuoteOffer.swift
//  CashuSwift
//
//  NUT-XX: Quote Offers. An operator (teller, POS, payment processor) registers
//  a ticket with the mint's payment backend and hands the wallet a serialized
//  offer. The wallet uses it to create a mint or melt quote for itself, so the
//  operation is initiated by the counterparty without ever displaying a quote ID.
//

import Foundation
import SwiftCBOR

extension CashuSwift {
    /// A quote offer per NUT-XX, serialized as `"cquote" + "A" + base64_urlsafe(CBOR(offer))`.
    public struct QuoteOffer: Codable, Sendable, Equatable {

        public enum Operation: String, Codable, Sendable {
            case mint
            case melt
        }

        /// The URL of the mint (`m`).
        public let mintURL: String
        /// The operation of the offer (`o`), either mint or melt.
        public let operation: Operation
        /// The payment method to use (`h`).
        public let method: PaymentMethodID
        /// The unit of the offer (`u`).
        public let unit: String
        /// The ticket (`t`), an identifier for the offered operation issued by the
        /// mint's payment backend. Single-use: claimed by exactly one quote.
        public let ticket: String
        /// The amount of the offer (`a`). MUST be set if the method's quote request
        /// requires an amount.
        public let amount: Int?
        /// Human readable description (`d`) the wallet displays after scanning.
        public let offerDescription: String?
        /// Unix timestamp (`e`) until which the offer can be claimed.
        public let expiry: Int?

        static let prefix = "cquote"
        static let version = "A"

        public init(mintURL: String,
                    operation: Operation,
                    method: PaymentMethodID,
                    unit: String,
                    ticket: String,
                    amount: Int? = nil,
                    offerDescription: String? = nil,
                    expiry: Int? = nil) {
            self.mintURL = mintURL
            self.operation = operation
            self.method = method
            self.unit = unit
            self.ticket = ticket
            self.amount = amount
            self.offerDescription = offerDescription
            self.expiry = expiry
        }

        /// Whether the offer's claim window has passed.
        public func isExpired(at date: Date = Date()) -> Bool {
            guard let expiry else { return false }
            return Int(date.timeIntervalSince1970) > expiry
        }

        public func validate() throws {
            guard !ticket.isEmpty else {
                throw CashuError.quoteOfferValidation("Quote offer ticket must not be empty.")
            }
            guard URL(string: mintURL) != nil, !mintURL.isEmpty else {
                throw CashuError.quoteOfferValidation("Quote offer mint URL is not a valid URL: \(mintURL)")
            }
            guard !unit.isEmpty else {
                throw CashuError.quoteOfferValidation("Quote offer unit must not be empty.")
            }
            if let amount, amount <= 0 {
                throw CashuError.quoteOfferValidation("Quote offer amount must be positive.")
            }
        }

        // MARK: - CBOR Encoding/Decoding

        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.quoteOfferDecoding("Expected CBOR map for QuoteOffer")
            }

            guard let mintURL = cborMap[.utf8String("m")]?.asString(),
                  let operationString = cborMap[.utf8String("o")]?.asString(),
                  let method = cborMap[.utf8String("h")]?.asString(),
                  let unit = cborMap[.utf8String("u")]?.asString(),
                  let ticket = cborMap[.utf8String("t")]?.asString() else {
                throw CashuError.quoteOfferDecoding("Missing required field(s) in QuoteOffer: needs m, o, h, u, t")
            }

            guard let operation = Operation(rawValue: operationString) else {
                throw CashuError.quoteOfferDecoding("QuoteOffer operation must be 'mint' or 'melt', got '\(operationString)'")
            }

            self.mintURL = mintURL
            self.operation = operation
            self.method = PaymentMethodID(rawValue: method)
            self.unit = unit
            self.ticket = ticket

            if let amountUInt = cborMap[.utf8String("a")]?.asUnsignedInt() {
                self.amount = Int(amountUInt)
            } else {
                self.amount = nil
            }

            self.offerDescription = cborMap[.utf8String("d")]?.asString()

            if let expiryUInt = cborMap[.utf8String("e")]?.asUnsignedInt() {
                self.expiry = Int(expiryUInt)
            } else {
                self.expiry = nil
            }
        }

        // MARK: - Serialization

        /// Serializes the quote offer to its `cquoteA...` string representation.
        ///
        /// Fields are encoded in the fixed order of the spec's test vector
        /// (m, o, h, u, a, t, d, e) so encoding is deterministic; the base64 is
        /// URL-safe without padding, matching the NUT-XX example.
        public func serialize() throws -> String {
            try validate()

            var pairs: [(String, CBOR)] = [
                ("m", .utf8String(mintURL)),
                ("o", .utf8String(operation.rawValue)),
                ("h", .utf8String(method.rawValue)),
                ("u", .utf8String(unit)),
            ]
            if let amount {
                pairs.append(("a", .unsignedInt(UInt64(amount))))
            }
            pairs.append(("t", .utf8String(ticket)))
            if let offerDescription {
                pairs.append(("d", .utf8String(offerDescription)))
            }
            if let expiry {
                pairs.append(("e", .unsignedInt(UInt64(expiry))))
            }

            // SwiftCBOR's `.map` encodes from an unordered dictionary, so build the
            // definite-length map manually to keep the deterministic field order.
            var bytes: [UInt8] = [0xA0 | UInt8(pairs.count)]
            for (key, value) in pairs {
                bytes.append(contentsOf: CBOR.utf8String(key).encode())
                bytes.append(contentsOf: value.encode())
            }

            let base64URLSafe = Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))

            return Self.prefix + Self.version + base64URLSafe
        }

        /// Initializes a QuoteOffer from its serialized `cquoteA...` representation.
        public init(encodedOffer: String) throws {
            let expectedPrefix = Self.prefix + Self.version
            guard encodedOffer.hasPrefix(expectedPrefix) else {
                throw CashuError.quoteOfferDecoding("Quote offer must start with '\(expectedPrefix)'")
            }

            let base64URLSafeString = String(encodedOffer.dropFirst(expectedPrefix.count))

            guard let cborData = base64URLSafeString.decodeBase64UrlSafe() else {
                throw CashuError.quoteOfferDecoding("Could not decode base64 string")
            }

            guard let cborValue = try? CBOR.decode([UInt8](cborData)) else {
                throw CashuError.quoteOfferDecoding("Could not decode CBOR data")
            }

            self = try CashuSwift.QuoteOffer(fromCBOR: cborValue)
            try self.validate()
        }
    }
}
