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

enum Bolt11 {
    struct RequestMintQuote:QuoteRequest {
        let unit: String
        let amount:Int
    }
    
    struct RequestMeltQuote: QuoteRequest {
        
        struct Options:Codable {
            struct MPP:Codable {
                let amount:Int
            }
            let mpp:MPP
        }
        
        let unit: String
        let request:String
        
        let options:Options?
    }
    
    struct MintQuote:Quote {
        let quote:String
        let request: String
        let paid:Bool?
        let state:QuoteState?
        let expiry:Int
        var requestDetail:RequestMintQuote?
    }

    struct MeltQuote: Quote {
        var paid: Bool?
        
        var state: QuoteState?
        
        let quote: String
        let amount: Int
        var feeReserve: Int
        let expiry: Int
        let paymentPreimage: String?
        
        enum CodingKeys: String, CodingKey {
            case quote
            case amount
            case feeReserve = "fee_reserve"
            case paid
            case expiry
            case paymentPreimage = "payment_preimage"
        }
    }
    
    struct MeltRequest:Codable {
        let quote:String
        let inputs:[Proof]
    }
    
    struct MintRequest:Codable {
        let quote:String
        let outputs:[Output]
    }
    
    struct MintResponse:Codable {
        let signatures:[Promise]
    }
    
}
