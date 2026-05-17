//
//  PaymentMethodID.swift
//  CashuSwift
//

import Foundation

extension CashuSwift {
    /// Identifier of a payment method backend a mint exposes (e.g. `bolt11`, `bolt12`,
    /// or any custom string the mint advertises).
    ///
    /// The raw value is the string used in URL paths like `/v1/mint/quote/{method}` and
    /// in the `method` field of `MintMethodSetting` / `MeltMethodSetting`.
    public struct PaymentMethodID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(String.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public static let bolt11 = PaymentMethodID(rawValue: "bolt11")
        public static let bolt12 = PaymentMethodID(rawValue: "bolt12")
    }
}
