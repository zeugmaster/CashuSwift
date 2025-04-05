//
//  File.swift
//  
//
//  Created by zm on 31.05.24.
//

import Foundation

extension CashuSwift {
    public protocol QuoteRequest: Codable, Sendable {
        var unit:String { get }
    }

    public protocol Quote: Codable, Sendable {
        var quote:String { get }
        var paid:Bool? { get }          // paid and state are both optional for compatibility
        var state:QuoteState? { get }   // TODO: use custom decoding to unify
        var expiry:Int { get }
    }

    public enum QuoteState: String, Codable, Sendable {
        case paid = "PAID"
        case unpaid = "UNPAID"
        case pending = "PENDING"
    }

    public enum Bolt11 {
        public struct RequestMintQuote:QuoteRequest {
            public let unit: String
            public let amount:Int
            
            public init(unit: String, amount: Int) {
                self.unit = unit
                self.amount = amount
            }
        }
        
        public struct RequestMeltQuote: QuoteRequest {
            
            public struct Options: Codable, Sendable {
                public struct MPP: Codable, Sendable {
                    public let amount:Int
                    
                    public init(amount: Int) {
                        self.amount = amount
                    }
                }
                public let mpp:MPP
                
                public init(mpp: MPP) {
                    self.mpp = mpp
                }
            }
            
            public let unit: String
            public let request:String
            
            public let options:Options?
            
            public init(unit: String, request: String, options: Options?) {
                self.unit = unit
                self.request = request
                self.options = options
            }
        }
        
        public struct MintQuote:Quote {
            public let quote:String
            public let request: String
            public let paid:Bool?
            public let state:QuoteState?
            public let expiry:Int
            public var requestDetail: RequestMintQuote?
        }

        public struct MeltQuote: Quote {
            public var paid: Bool?
            
            public var state: QuoteState?
            
            public var quoteRequest: RequestMeltQuote?
            
            public let quote: String
            public let amount: Int
            public var feeReserve: Int
            public let expiry: Int
            public let paymentPreimage: String?
            
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
        
        public struct MeltRequest:Codable {
            let quote:String
            let inputs:[Proof]
            let outputs:[Output]?
        }
        
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
