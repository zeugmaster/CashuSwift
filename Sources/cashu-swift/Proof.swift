//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

public struct Proof: Codable, Equatable, CustomStringConvertible {
    
    public static func == (lhs: Proof, rhs: Proof) -> Bool {
        lhs.C == rhs.C &&
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount
    }
    
    let id: String
    let amount: Int
    let secret: String
    let C: String
    
    public var description: String {
        return "C: ...\(C.suffix(6)), amount: \(amount)"
    }
    
    public enum ProofState: String, Codable {
        case unspent = "UNSPENT"
        case pending = "PENDING"
        case spent = "SPENT"
    }
    
    struct ProofStateListEntry: Codable {
        let Y:String
        let state:ProofState
        let witness:String?
    }
    
    struct StateCheckRequest: Codable {
        let Ys:[String]
    }
    
    public struct StateCheckResponse: Codable {
        let states: [ProofStateListEntry]
    }
}

