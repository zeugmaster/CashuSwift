//
//  File.swift
//  
//
//  Created by zm on 31.05.24.
//

import Foundation

extension CashuSwift {
    /// Protocol for quote request types.
    public protocol QuoteRequest: Codable, Sendable {
        /// The unit for this quote request.
        var unit:String { get }
    }

    /// Protocol for quote response types.
    public protocol Quote: Codable, Sendable {
        /// The quote identifier.
        var quote:String { get }
        /// Whether the quote has been paid.
        var paid:Bool? { get }
        /// The state of the quote.
        var state:QuoteState? { get }
        /// The expiry timestamp.
        var expiry:Int? { get }
    }

    /// Represents the state of a quote.
    public enum QuoteState: String, Codable, Sendable {
        /// The quote has been paid.
        case paid = "PAID"
        /// The quote has not been paid.
        case unpaid = "UNPAID"
        /// The quote payment is pending.
        case pending = "PENDING"
    }

    /// Bolt11-specific quote types.
    public enum Bolt11 {
        /// Request for a mint quote (Lightning invoice).
        public struct RequestMintQuote:QuoteRequest {
            /// The unit for this quote.
            public let unit: String
            /// The amount to mint.
            public let amount:Int
            
            /// Creates a new mint quote request.
            /// - Parameters:
            ///   - unit: The unit for this quote
            ///   - amount: The amount to mint
            public init(unit: String, amount: Int) {
                self.unit = unit
                self.amount = amount
            }
        }
        
        /// Request for a melt quote (pay Lightning invoice).
        public struct RequestMeltQuote: QuoteRequest {
            
            /// Options for melt quote requests.
            public struct Options: Codable, Sendable {
                /// Multi-part payment options.
                public struct MPP: Codable, Sendable {
                    /// The amount for multi-part payment.
                    public let amount:Int
                    
                    public init(amount: Int) {
                        self.amount = amount
                    }
                }
                /// The multi-part payment configuration.
                public let mpp:MPP
                
                public init(mpp: MPP) {
                    self.mpp = mpp
                }
            }
            
            /// The unit for this quote.
            public let unit: String
            /// The Lightning invoice to pay.
            public let request:String
            
            /// Optional request options.
            public let options:Options?
            
            /// Creates a new melt quote request.
            /// - Parameters:
            ///   - unit: The unit for this quote
            ///   - request: The Lightning invoice to pay
            ///   - options: Optional request options
            public init(unit: String, request: String, options: Options?) {
                self.unit = unit
                self.request = request
                self.options = options
            }
        }
        
        /// Response for a mint quote request.
        public struct MintQuote:Quote {
            /// The quote identifier.
            public let quote:String
            /// The Lightning invoice to pay.
            public let request: String
            /// Whether the quote has been paid.
            public let paid:Bool?
            /// The state of the quote.
            public let state:QuoteState?
            /// The expiry timestamp.
            public let expiry:Int?
            /// Associated request details.
            public var requestDetail: RequestMintQuote?
        }

        /// Response for a melt quote request.
        public struct MeltQuote: Quote {
            /// Whether the quote has been paid.
            public var paid: Bool?
            
            /// The state of the quote.
            public var state: QuoteState?
            
            /// Associated request details.
            public var quoteRequest: RequestMeltQuote?
            
            /// The quote identifier.
            public let quote: String
            /// The amount to be paid.
            public let amount: Int
            /// The fee reserve amount.
            public var feeReserve: Int
            /// The expiry timestamp.
            public let expiry: Int?
            /// The payment preimage (if paid).
            public let paymentPreimage: String?
            
            /// Change proofs if the fee was overpaid.
            public let change:[Promise]?
            
            enum CodingKeys: String, CodingKey {
                case quote
                case amount
                case feeReserve = "fee_reserve"
                case paid
                case expiry
                case paymentPreimage = "payment_preimage"
                case change
                case quoteRequest
                case state
            }
        }
        
        /// Request to melt tokens for a Lightning payment.
        public struct MeltRequest:Codable {
            let quote:String
            let inputs:[Proof]
            let outputs:[Output]?
        }
        
        /// Request to mint tokens after paying a Lightning invoice.
        public struct MintRequest:Codable {
            let quote:String
            let outputs:[Output]
        }
        
        struct MintResponse:Codable {
            let signatures:[Promise]
        }
        
        public static func satAmountFromInvoice(pr:String) throws -> Int {
            guard let range = pr.range(of: "1", options: .backwards) else {
                throw CashuError.bolt11InvalidInvoiceError("")
            }
            let endIndex = range.lowerBound
            let hrp = String(pr[..<endIndex])
            if hrp.prefix(4) == "lnbc" {
                var num = hrp.dropFirst(4)
                let multiplier = num.popLast()
                guard var n = Double(num) else {
                    throw CashuError.bolt11InvalidInvoiceError("")
                }
                switch multiplier {
                case "m": n *= 100000
                case "u": n *= 100
                case "n": n *= 0.1
                case "p": n *= 0.0001
                default: throw CashuError.bolt11InvalidInvoiceError("")
                }
                return n >= 1 ? Int(n) : 0
            } else {
                throw CashuError.bolt11InvalidInvoiceError("")
            }
        }
    }

}
