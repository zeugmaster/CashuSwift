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
    var paid:Bool { get }
    var expiry:Int { get }
}

public struct Bolt11 {
    private init() {}
    
    struct RequestMintQuote:QuoteRequest {
        let unit: String
        let amount:Int
    }
    
    struct RequestMeltQuote: QuoteRequest {
        let unit: String
        let request:String
    }
    
    struct MintQuote:Quote {
        let quote:String
        let request: String
        let paid:Bool
        let expiry:Int
    }

    struct MeltQuote: Quote {
        let quote: String
        let amount: Int
        var feeReserve: Int
        let paid: Bool
        let expiry: Int

        enum CodingKeys: String, CodingKey {
            case quote
            case amount
            case feeReserve = "fee_reserve"
            case paid
            case expiry
        }
    }
}
