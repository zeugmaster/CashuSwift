//
//  File.swift
//  
//
//  Created by zm on 31.05.24.
//

import Foundation

public protocol QuoteRequest:Codable {
    var unit:String { get }
}

public protocol Quote:Codable {
    var quote:String { get }
    var paid:Bool? { get }          // paid and state are both optional for compatibility
    var state:QuoteState? { get }   // TODO: use custom decoding to unify
    var expiry:Int { get }
}

public enum QuoteState: String,Codable {
    case paid = "PAID"
    case unpaid = "UNPAID"
    case pending = "PENDING"
}

public enum Bolt11 {
    public struct RequestMintQuote:QuoteRequest {
        public let unit: String
        public let amount:Int
    }
    
    public struct RequestMeltQuote: QuoteRequest {
        
        public struct Options:Codable {
            public struct MPP:Codable {
                public let amount:Int
            }
            public let mpp:MPP
        }
        
        public let unit: String
        public let request:String
        
        public let options:Options?
    }
    
    public struct MintQuote:Quote {
        public let quote:String
        public let request: String
        public let paid:Bool?
        public let state:QuoteState?
        public let expiry:Int
        public var requestDetail:RequestMintQuote?
    }

    public struct MeltQuote: Quote {
        public var paid: Bool?
        
        public var state: QuoteState?
        
        public let quote: String
        public let amount: Int
        public var feeReserve: Int
        public let expiry: Int
        public let paymentPreimage: String?
        
        enum CodingKeys: String, CodingKey {
            case quote
            case amount
            case feeReserve = "fee_reserve"
            case paid
            case expiry
            case paymentPreimage = "payment_preimage"
        }
    }
    
    public struct MeltRequest:Codable {
        public let quote:String
        public let inputs:[Proof]
    }
    
    public struct MintRequest:Codable {
        let quote:String
        let outputs:[Output]
    }
    
    struct MintResponse:Codable {
        let signatures:[Promise]
    }
    
}
