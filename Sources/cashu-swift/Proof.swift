//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import SwiftData

@Model
public struct Proof: Codable, Equatable, CustomStringConvertible {
    
    public static func == (lhs: Proof, rhs: Proof) -> Bool {
        lhs.C == rhs.C &&
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount
    }
    
    public enum CodingKeys: String, CodingKey {
        case id, amount, secret, C
    }
    
    let id: String
    let amount: Int
    let secret: String
    let C: String
    
    public var description: String {
        return "C: ...\(C.suffix(6)), amount: \(amount)"
    }
    
    // MARK: - Codable Implementation
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(amount, forKey: .amount)
        try container.encode(secret, forKey: .secret)
        try container.encode(C, forKey: .C)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        amount = try container.decode(Int.self, forKey: .amount)
        secret = try container.decode(String.self, forKey: .secret)
        C = try container.decode(String.self, forKey: .C)
    }
    
    // MARK: - Additional nested types
    
    public enum ProofState: String, Codable {
        case unspent = "UNSPENT"
        case pending = "PENDING"
        case spent = "SPENT"
    }
    
    struct ProofStateListEntry: Codable {
        let Y: String
        let state: ProofState
        let witness: String?
    }
    
    struct StateCheckRequest: Codable {
        let Ys: [String]
    }
    
    public struct StateCheckResponse: Codable {
        let states: [ProofStateListEntry]
    }
}
