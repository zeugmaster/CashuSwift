//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

class Proof: Codable, Equatable, CustomStringConvertible {
    
    static func == (lhs: Proof, rhs: Proof) -> Bool {
        lhs.C == rhs.C && 
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount
    }
    
    let id: String
    let amount: Int
    let secret: String
    let C: String
    
    var description: String {
        return "C: ...\(C.suffix(6)), amount: \(amount)"
    }
    
    init(id: String, amount: Int, secret: String, C: String) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
    }
}

