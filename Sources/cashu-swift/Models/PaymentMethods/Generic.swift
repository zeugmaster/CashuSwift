//
//  Generic.swift
//  CashuSwift
//
//  Escape-hatch types for payment methods the library has no first-class
//  support for. The wallet UI can pass through arbitrary fields via `extra`
//  and inspect arbitrary response fields via `raw`.
//

import Foundation

extension CashuSwift {
    public enum Generic {

        // Custom coding key used to flatten arbitrary fields into the top-level JSON object.
        private struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
            init(_ string: String) { self.stringValue = string }
        }

        // MARK: - Quote requests

        public struct MintQuoteRequest: CashuSwift.MintQuoteRequest {
            public let method: PaymentMethodID
            public let unit: String
            public let amount: Int?
            /// Arbitrary additional fields the mint expects for this method. Encoded
            /// flat into the top-level JSON body.
            public let extra: JSONObject?

            public init(method: PaymentMethodID,
                        unit: String,
                        amount: Int? = nil,
                        extra: JSONObject? = nil) {
                self.method = method
                self.unit = unit
                self.amount = amount
                self.extra = extra
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: DynamicKey.self)
                try c.encode(unit, forKey: DynamicKey("unit"))
                if let amount {
                    try c.encode(amount, forKey: DynamicKey("amount"))
                }
                if let extra {
                    for (key, value) in extra {
                        try c.encode(value, forKey: DynamicKey(key))
                    }
                }
            }

            public init(from decoder: Decoder) throws {
                // Decoding is exposed only for completeness — Generic requests are
                // typically authored by the wallet rather than received.
                let c = try decoder.container(keyedBy: DynamicKey.self)
                self.unit = try c.decode(String.self, forKey: DynamicKey("unit"))
                self.amount = try c.decodeIfPresent(Int.self, forKey: DynamicKey("amount"))
                if let m = try c.decodeIfPresent(String.self, forKey: DynamicKey("method")) {
                    self.method = PaymentMethodID(rawValue: m)
                } else {
                    self.method = PaymentMethodID(rawValue: "")
                }
                var extra = JSONObject()
                for key in c.allKeys where !["unit", "amount", "method"].contains(key.stringValue) {
                    extra[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
                }
                self.extra = extra.isEmpty ? nil : extra
            }
        }

        public struct MeltQuoteRequest: CashuSwift.MeltQuoteRequest {
            public let method: PaymentMethodID
            public let unit: String
            public let request: String
            public let extra: JSONObject?

            public init(method: PaymentMethodID,
                        unit: String,
                        request: String,
                        extra: JSONObject? = nil) {
                self.method = method
                self.unit = unit
                self.request = request
                self.extra = extra
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: DynamicKey.self)
                try c.encode(unit, forKey: DynamicKey("unit"))
                try c.encode(request, forKey: DynamicKey("request"))
                if let extra {
                    for (key, value) in extra {
                        try c.encode(value, forKey: DynamicKey(key))
                    }
                }
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: DynamicKey.self)
                self.unit = try c.decode(String.self, forKey: DynamicKey("unit"))
                self.request = try c.decode(String.self, forKey: DynamicKey("request"))
                if let m = try c.decodeIfPresent(String.self, forKey: DynamicKey("method")) {
                    self.method = PaymentMethodID(rawValue: m)
                } else {
                    self.method = PaymentMethodID(rawValue: "")
                }
                var extra = JSONObject()
                for key in c.allKeys where !["unit", "request", "method"].contains(key.stringValue) {
                    extra[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
                }
                self.extra = extra.isEmpty ? nil : extra
            }
        }

        // MARK: - Quote responses

        /// Method-agnostic mint quote. The full server response is preserved in `raw`
        /// so the wallet UI can present method-specific fields without library support.
        public struct MintQuote: CashuSwift.MintQuoteResponse {
            public let method: PaymentMethodID
            public let quote: String
            public let request: String
            public let unit: String
            public let amount: Int?
            public let state: QuoteState?
            public let expiry: Int?
            public let raw: JSONObject

            public init(method: PaymentMethodID,
                        quote: String,
                        request: String,
                        unit: String,
                        amount: Int?,
                        state: QuoteState?,
                        expiry: Int?,
                        raw: JSONObject) {
                self.method = method
                self.quote = quote
                self.request = request
                self.unit = unit
                self.amount = amount
                self.state = state
                self.expiry = expiry
                self.raw = raw
            }

            public init(from decoder: Decoder) throws {
                // Decode the whole body into JSON, then extract known fields.
                let c = try decoder.container(keyedBy: DynamicKey.self)
                var dict = JSONObject()
                for key in c.allKeys {
                    dict[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
                }
                self.raw = dict
                self.quote = try Generic.requireString(dict, key: "quote", on: "Generic.MintQuote")
                self.request = try Generic.requireString(dict, key: "request", on: "Generic.MintQuote")
                self.unit = try Generic.requireString(dict, key: "unit", on: "Generic.MintQuote")
                self.amount = Generic.optionalInt(dict, key: "amount")
                self.expiry = Generic.optionalInt(dict, key: "expiry")
                if case let .string(s) = dict["state"] ?? .null {
                    self.state = QuoteState(rawValue: s)
                } else {
                    self.state = nil
                }
                if case let .string(m) = dict["method"] ?? .null {
                    self.method = PaymentMethodID(rawValue: m)
                } else {
                    // The mint does not echo a `method` field — it is embedded in the URL.
                    // The namespace entry point grafts the correct method via `withInjectedMethod`.
                    self.method = PaymentMethodID(rawValue: "")
                }
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: DynamicKey.self)
                for (key, value) in raw {
                    try c.encode(value, forKey: DynamicKey(key))
                }
            }
        }

        public struct MeltQuote: CashuSwift.MeltQuoteResponse {
            public let method: PaymentMethodID
            public let quote: String
            public let amount: Int
            public let unit: String
            public let feeReserve: Int
            public let state: QuoteState?
            public let expiry: Int?
            public let paymentPreimage: String?
            public let change: [Promise]?
            public let raw: JSONObject

            public init(method: PaymentMethodID,
                        quote: String,
                        amount: Int,
                        unit: String,
                        feeReserve: Int,
                        state: QuoteState?,
                        expiry: Int?,
                        paymentPreimage: String?,
                        change: [Promise]?,
                        raw: JSONObject) {
                self.method = method
                self.quote = quote
                self.amount = amount
                self.unit = unit
                self.feeReserve = feeReserve
                self.state = state
                self.expiry = expiry
                self.paymentPreimage = paymentPreimage
                self.change = change
                self.raw = raw
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: DynamicKey.self)
                var dict = JSONObject()
                for key in c.allKeys {
                    dict[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
                }
                self.raw = dict
                self.quote = try Generic.requireString(dict, key: "quote", on: "Generic.MeltQuote")
                self.unit = try Generic.requireString(dict, key: "unit", on: "Generic.MeltQuote")
                guard let amount = Generic.optionalInt(dict, key: "amount") else {
                    throw DecodingError.dataCorruptedError(
                        forKey: DynamicKey("amount"),
                        in: c,
                        debugDescription: "Generic.MeltQuote is missing required field 'amount'."
                    )
                }
                self.amount = amount
                self.feeReserve = Generic.optionalInt(dict, key: "fee_reserve") ?? 0
                self.expiry = Generic.optionalInt(dict, key: "expiry")
                if case let .string(s) = dict["state"] ?? .null {
                    self.state = QuoteState(rawValue: s)
                } else {
                    self.state = nil
                }
                if case let .string(p) = dict["payment_preimage"] ?? .null {
                    self.paymentPreimage = p
                } else {
                    self.paymentPreimage = nil
                }
                // Change is opaque per JSONValue, so decode it again as the typed array.
                if let changeValue = dict["change"], case .array = changeValue {
                    self.change = try Generic.decodeChange(from: decoder)
                } else {
                    self.change = nil
                }
                if case let .string(m) = dict["method"] ?? .null {
                    self.method = PaymentMethodID(rawValue: m)
                } else {
                    self.method = PaymentMethodID(rawValue: "")
                }
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: DynamicKey.self)
                for (key, value) in raw {
                    try c.encode(value, forKey: DynamicKey(key))
                }
            }
        }

        // MARK: - Entry points

        /// Requests a mint quote for an arbitrary method. Use this when the mint
        /// advertises a `method` the library has no first-class support for.
        public static func requestMintQuote(_ request: MintQuoteRequest,
                                            from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._requestMintQuote(request, from: mint, as: MintQuote.self)
                .withInjectedMethod(request.method)
        }

        public static func requestMeltQuote(_ request: MeltQuoteRequest,
                                            from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._requestMeltQuote(request, from: mint, as: MeltQuote.self)
                .withInjectedMethod(request.method)
        }

        public static func mintQuoteState(_ id: String,
                                          method: PaymentMethodID,
                                          from mint: Mint) async throws -> MintQuote {
            try await CashuSwift._mintQuoteState(quoteID: id, method: method, from: mint, as: MintQuote.self)
                .withInjectedMethod(method)
        }

        public static func meltQuoteState(_ id: String,
                                          method: PaymentMethodID,
                                          from mint: Mint) async throws -> MeltQuote {
            try await CashuSwift._meltQuoteState(quoteID: id, method: method, from: mint, as: MeltQuote.self)
                .withInjectedMethod(method)
        }

        public static func mint(quote: MintQuote,
                                from mint: Mint,
                                amount: Int,
                                seed: String?,
                                preferredDistribution: [Int]? = nil) async throws -> IssueResult {
            guard amount > 0 else {
                throw CashuError.invalidAmount
            }
            return try await CashuSwift._mint(
                quote: quote,
                amount: amount,
                mint: mint,
                seed: seed,
                preferredDistribution: preferredDistribution
            )
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
                blankOutputs: blankOutputs,
                preferAsync: preferAsync
            )
        }

        public static func meltState(_ id: String,
                                     method: PaymentMethodID,
                                     from mint: Mint,
                                     blankOutputs: (outputs: [Output],
                                                    blindingFactors: [String],
                                                    secrets: [String])? = nil) async throws -> MeltResult<MeltQuote> {
            try await CashuSwift._meltState(
                quoteID: id,
                method: method,
                mint: mint,
                blankOutputs: blankOutputs,
                as: MeltQuote.self
            )
        }

        // MARK: - Decoding helpers

        fileprivate static func requireString(_ dict: JSONObject, key: String, on type: String) throws -> String {
            guard case let .string(value) = dict[key] ?? .null else {
                throw CashuError.unknownError("\(type) is missing required field '\(key)' or has wrong type.")
            }
            return value
        }

        fileprivate static func optionalInt(_ dict: JSONObject, key: String) -> Int? {
            switch dict[key] {
            case .integer(let v): return Int(v)
            case .double(let v): return Int(v)
            default: return nil
            }
        }

        fileprivate static func decodeChange(from decoder: Decoder) throws -> [Promise]? {
            // Re-decode using a dedicated wrapper that pulls just the `change` field.
            struct ChangeOnly: Decodable {
                let change: [Promise]?
            }
            let wrapper = try ChangeOnly(from: decoder)
            return wrapper.change
        }
    }
}

// MARK: - Method injection
//
// Server responses do not include a top-level `method` field — the spec embeds it in
// the URL. For Generic quotes we know the method from the caller's request and have
// to graft it onto the decoded response so the protocol conformance is satisfied.

private extension CashuSwift.Generic.MintQuote {
    func withInjectedMethod(_ method: CashuSwift.PaymentMethodID) -> CashuSwift.Generic.MintQuote {
        var newRaw = raw
        newRaw["method"] = .string(method.rawValue)
        return CashuSwift.Generic.MintQuote(
            method: method,
            quote: quote,
            request: request,
            unit: unit,
            amount: amount,
            state: state,
            expiry: expiry,
            raw: newRaw
        )
    }
}

private extension CashuSwift.Generic.MeltQuote {
    func withInjectedMethod(_ method: CashuSwift.PaymentMethodID) -> CashuSwift.Generic.MeltQuote {
        var newRaw = raw
        newRaw["method"] = .string(method.rawValue)
        return CashuSwift.Generic.MeltQuote(
            method: method,
            quote: quote,
            amount: amount,
            unit: unit,
            feeReserve: feeReserve,
            state: state,
            expiry: expiry,
            paymentPreimage: paymentPreimage,
            change: change,
            raw: newRaw
        )
    }
}
