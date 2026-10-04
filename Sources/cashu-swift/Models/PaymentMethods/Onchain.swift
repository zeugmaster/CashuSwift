import Foundation

extension CashuSwift {
    /// Bitcoin deposits and withdrawals through a Cashu mint (NUT-30).
    /// Applications own persistence, proof reservations, and polling.
    public enum Onchain {
        public static let id: PaymentMethodID = .onchain

        public enum Error: Swift.Error, Equatable, Sendable, LocalizedError {
            case invalidQuote
            case invalidFeeSelection
            case invalidContext
            case invalidResponse
            case invalidSettings
            case unavailable
            case unsupportedContextVersion
            case http(status: Int, mintCode: Int?)

            public var errorDescription: String? {
                switch self {
                case .invalidQuote: return "Invalid onchain quote."
                case .invalidFeeSelection: return "Select a fee option returned by the mint."
                case .invalidContext: return "Invalid onchain operation recovery context."
                case .invalidResponse: return "Mint response does not match the onchain operation."
                case .invalidSettings: return "Invalid onchain payment settings."
                case .unavailable: return "Onchain payments are unavailable for this unit and direction."
                case .unsupportedContextVersion: return "Unsupported onchain recovery context version."
                case .http(let status, let code):
                    return "Mint HTTP error \(status)" + (code.map { " (code \($0))" } ?? "") + "."
                }
            }
        }

        public struct MintQuoteRequest: CashuSwift.MintQuoteRequest {
            public let unit: String
            public let pubkey: String
            public var method: PaymentMethodID { .onchain }
            public init(unit: String, pubkey: String) {
                self.unit = unit
                self.pubkey = pubkey
            }
        }

        public struct MeltQuoteRequest: CashuSwift.MeltQuoteRequest {
            public let unit: String
            /// Bare Bitcoin address; the mint validates its network and checksum.
            public let request: String
            public let amount: Int
            public var method: PaymentMethodID { .onchain }
            public init(unit: String, request: String, amount: Int) {
                self.unit = unit
                self.request = request
                self.amount = amount
            }
        }

        public struct MintQuote: CashuSwift.MintQuoteResponse {
            public let method: PaymentMethodID
            public let quote: String
            public let request: String
            public let unit: String
            public let expiry: Int?
            public let pubkey: String
            public let amountPaid: Int
            public let amountIssued: Int
            public let updatedAt: Int
            public var amount: Int? { nil }
            public var state: QuoteState? { nil }
            public var mintableAmount: Int { amountPaid - amountIssued }

            public init(quote: String, request: String, unit: String, expiry: Int?, pubkey: String,
                        amountPaid: Int, amountIssued: Int, updatedAt: Int) throws {
                try Onchain.validateQuoteID(quote)
                try Onchain.validateAddress(request)
                guard !unit.isEmpty, updatedAt >= 0, expiry.map({ $0 >= 0 }) ?? true else {
                    throw Error.invalidQuote
                }
                guard amountPaid >= 0, amountIssued >= 0, amountIssued <= amountPaid else {
                    throw CashuError.invalidQuoteAccounting
                }
                _ = try Crypto.nut20PublicKey(pubkey)
                self.method = .onchain
                self.quote = quote
                self.request = request
                self.unit = unit
                self.expiry = expiry
                self.pubkey = pubkey
                self.amountPaid = amountPaid
                self.amountIssued = amountIssued
                self.updatedAt = updatedAt
            }

            /// Merge only a response belonging to this quote. Older snapshots are ignored.
            public func merging(_ newer: MintQuote) throws -> MintQuote {
                guard quote == newer.quote, request == newer.request, unit == newer.unit,
                      pubkey.lowercased() == newer.pubkey.lowercased(), expiry == newer.expiry else {
                    throw Error.invalidResponse
                }
                if newer.updatedAt < updatedAt { return self }
                guard newer.amountPaid >= amountPaid, newer.amountIssued >= amountIssued else {
                    throw CashuError.invalidQuoteAccounting
                }
                if newer.updatedAt == updatedAt {
                    guard newer.amountPaid == amountPaid, newer.amountIssued == amountIssued else {
                        throw CashuError.invalidQuoteAccounting
                    }
                }
                return newer
            }

            enum CodingKeys: String, CodingKey {
                case method, quote, request, unit, expiry, pubkey
                case amountPaid = "amount_paid", amountIssued = "amount_issued", updatedAt = "updated_at"
            }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard try c.decode(PaymentMethodID.self, forKey: .method) == .onchain else { throw Error.invalidQuote }
                try self.init(quote: c.decode(String.self, forKey: .quote),
                              request: c.decode(String.self, forKey: .request), unit: c.decode(String.self, forKey: .unit),
                              expiry: c.decodeIfPresent(Int.self, forKey: .expiry), pubkey: c.decode(String.self, forKey: .pubkey),
                              amountPaid: c.decode(Int.self, forKey: .amountPaid),
                              amountIssued: c.decode(Int.self, forKey: .amountIssued), updatedAt: c.decode(Int.self, forKey: .updatedAt))
            }
        }

        public struct FeeOption: Codable, Sendable, Equatable {
            public let feeIndex: Int
            public let feeReserve: Int
            public let estimatedBlocks: Int
            public init(feeIndex: Int, feeReserve: Int, estimatedBlocks: Int) throws {
                guard feeIndex >= 0, feeReserve >= 0, estimatedBlocks > 0 else { throw Error.invalidQuote }
                self.feeIndex = feeIndex
                self.feeReserve = feeReserve
                self.estimatedBlocks = estimatedBlocks
            }
            enum CodingKeys: String, CodingKey {
                case feeIndex = "fee_index", feeReserve = "fee_reserve", estimatedBlocks = "estimated_blocks"
            }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                try self.init(feeIndex: c.decode(Int.self, forKey: .feeIndex),
                              feeReserve: c.decode(Int.self, forKey: .feeReserve),
                              estimatedBlocks: c.decode(Int.self, forKey: .estimatedBlocks))
            }
        }

        public struct MeltQuote: CashuSwift.MeltQuoteResponse {
            public let method: PaymentMethodID
            public let quote: String
            public let request: String
            public let amount: Int
            public let unit: String
            public let state: QuoteState?
            public let expiry: Int?
            public let feeOptions: [FeeOption]
            public let selectedFeeIndex: Int?
            public let outpoint: String?
            public let change: [Promise]?
            /// Wallet choice, deliberately excluded from the mint's wire representation.
            public private(set) var requestedFeeIndex: Int? = nil

            public init(quote: String, request: String, amount: Int, unit: String, state: QuoteState,
                        expiry: Int, feeOptions: [FeeOption], selectedFeeIndex: Int? = nil,
                        outpoint: String? = nil, change: [Promise]? = nil) throws {
                try Onchain.validateQuoteID(quote)
                try Onchain.validateAddress(request)
                guard amount > 0, !unit.isEmpty, expiry >= 0, state != .issued,
                      !feeOptions.isEmpty, Set(feeOptions.map(\.feeIndex)).count == feeOptions.count,
                      selectedFeeIndex.map({ index in feeOptions.contains { $0.feeIndex == index } }) ?? true,
                      state != .paid || selectedFeeIndex != nil else { throw Error.invalidQuote }
                if let outpoint {
                    let parts = outpoint.split(separator: ":", omittingEmptySubsequences: false)
                    guard parts.count == 2, parts[0].utf8.count == 64,
                          parts[0].utf8.allSatisfy({ Onchain.hexDigits.contains($0) }),
                          !parts[1].isEmpty, parts[1].utf8.allSatisfy({ (48...57).contains($0) }),
                          UInt32(parts[1]) != nil else { throw Error.invalidQuote }
                }
                self.method = .onchain
                self.quote = quote
                self.request = request
                self.amount = amount
                self.unit = unit
                self.state = state
                self.expiry = expiry
                self.feeOptions = feeOptions
                self.selectedFeeIndex = selectedFeeIndex
                self.outpoint = outpoint
                self.change = change
            }

            public func selectingFee(index: Int) throws -> MeltQuote {
                guard feeOptions.contains(where: { $0.feeIndex == index }),
                      selectedFeeIndex == nil || selectedFeeIndex == index else { throw Error.invalidFeeSelection }
                var result = self
                result.requestedFeeIndex = index
                return result
            }

            public var selectedFee: FeeOption {
                get throws {
                    guard let index = requestedFeeIndex ?? selectedFeeIndex,
                          let fee = feeOptions.first(where: { $0.feeIndex == index }) else { throw Error.invalidFeeSelection }
                    return fee
                }
            }
            /// Pass `try quote.requiredInputAmount(inputFee: 0)` to `selectProofs`.
            public func requiredInputAmount(inputFee: Int) throws -> Int {
                try Onchain.add(Onchain.add(amount, selectedFee.feeReserve), inputFee)
            }

            enum CodingKeys: String, CodingKey {
                case method, quote, request, amount, unit, state, expiry, outpoint, change
                case feeOptions = "fee_options", selectedFeeIndex = "selected_fee_index"
            }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                guard try c.decode(PaymentMethodID.self, forKey: .method) == .onchain else { throw Error.invalidQuote }
                // CDK 0.18 may encode an unbroadcast outpoint as an empty string.
                // Its reference decoder also treats this narrowly as absent.
                let outpoint = try c.decodeIfPresent(String.self, forKey: .outpoint)
                try self.init(quote: c.decode(String.self, forKey: .quote), request: c.decode(String.self, forKey: .request),
                              amount: c.decode(Int.self, forKey: .amount), unit: c.decode(String.self, forKey: .unit),
                              state: c.decode(QuoteState.self, forKey: .state), expiry: c.decode(Int.self, forKey: .expiry),
                              feeOptions: c.decode([FeeOption].self, forKey: .feeOptions),
                              selectedFeeIndex: c.decodeIfPresent(Int.self, forKey: .selectedFeeIndex),
                              outpoint: outpoint == "" ? nil : outpoint,
                              change: c.decodeIfPresent([Promise].self, forKey: .change))
            }
        }

        public struct MeltExecutionBody: Codable, Sendable {
            public let quote: String
            public let feeIndex: Int
            public let inputs: [Proof]
            public let outputs: [Output]?
            enum CodingKeys: String, CodingKey {
                case quote, inputs, outputs
                case feeIndex = "fee_index"
            }
        }

        /// An enabled method/unit pair and its limits. Unknown options remain in `Mint.Info`.
        public struct Settings: Sendable {
            public let unit: String
            public let minAmount: Int?
            public let maxAmount: Int?
            public let confirmations: Int?

            public func validate(amount: Int) throws {
                guard amount > 0 else { throw CashuError.invalidAmount }
                if let minAmount, amount < minAmount { throw CashuError.amountOutsideOfLimitRange }
                if let maxAmount, amount > maxAmount { throw CashuError.amountOutsideOfLimitRange }
            }
        }

        public static func settings(in info: Mint.Info, unit: String,
                                    direction: Mint.Info.QuoteDirection) throws -> Settings {
            let nut: Mint.Info.NutInfo?
            switch direction {
            case .mint: nut = info.nuts?.nut04
            case .melt: nut = info.nuts?.nut05
            }
            guard nut?.disabled != true,
                  let setting = info.paymentMethodSetting(direction: direction, method: .onchain, unit: unit) else {
                throw Error.unavailable
            }
            guard setting.minAmount.map({ $0 >= 0 }) ?? true,
                  setting.maxAmount.map({ $0 >= 0 }) ?? true,
                  (setting.minAmount ?? 0) <= (setting.maxAmount ?? Int.max) else { throw Error.invalidSettings }
            let confirmations: Int?
            switch setting.options?["confirmations"] {
            case .integer(let value):
                guard let count = Int(exactly: value), count >= 0 else { throw Error.invalidSettings }
                confirmations = count
            case .none, .null: confirmations = nil
            default: throw Error.invalidSettings
            }
            return Settings(unit: unit, minAmount: setting.minAmount, maxAmount: setting.maxAmount, confirmations: confirmations)
        }

        static let hexDigits = Set("0123456789abcdefABCDEF".utf8)
        static func validateQuoteID(_ id: String) throws {
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".utf8)
            guard !id.isEmpty, id.utf8.count <= 256, id.utf8.allSatisfy({ allowed.contains($0) }) else {
                throw Error.invalidQuote
            }
        }
        static func validateAddress(_ address: String) throws {
            // Format boundary only. Full Bitcoin address/network validation belongs to the mint.
            guard (14...90).contains(address.utf8.count),
                  address.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
                throw Error.invalidQuote
            }
        }
        static func add(_ a: Int, _ b: Int) throws -> Int {
            let (sum, overflow) = a.addingReportingOverflow(b)
            guard a >= 0, b >= 0, !overflow else { throw CashuError.invalidAmount }
            return sum
        }
    }
}
