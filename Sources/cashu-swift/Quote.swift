//
//  File.swift
//  
//
//  Created by zm on 31.05.24.
//

import Foundation

struct MintQuoteBolt11Request:Codable {
    let amount:Int
    let unit:String
}

struct MintQuoteBolt11Response:Codable {
    let quote:String
    let request: String
    let paid:Bool
    let expiry:Int
}
