//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

// AKA BlindedMessage
struct Output: Codable {
    let amount: Int
    let B_: String
    let id: String
}

// AKA BlindedSignature
struct Promise: Codable {
    let id: String
    let amount: Int
    let C_: String
}
