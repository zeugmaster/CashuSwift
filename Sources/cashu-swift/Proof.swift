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
    let secret: String?
    let C: String
    
    var description: String {
        return "C: ...\(C.suffix(6)), amount: \(amount)"
    }
    
    init(id: String, amount: Int, secret: String? = nil, C: String) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
    }
}

import Foundation

struct Tag: Codable {
    let key: String
    let values: [String]
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        key = try container.decode(String.self)
        var values = [String]()
        while !container.isAtEnd {
            values.append(try container.decode(String.self))
        }
        self.values = values
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key)
        for value in values {
            try container.encode(value)
        }
    }
}

struct SecretData: Codable {
    let nonce: String
    let data: String
    let tags: [[Tag]]?
    
    enum CodingKeys: String, CodingKey {
        case nonce
        case data
        case tags
    }
}

enum Secret: Codable {
    case p2pk(secretData: SecretData)
    case htlc(secretData: SecretData)
    
    enum CodingKeys: String, CodingKey {
        case kind
        case secretData = "data"
    }
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let kindString = try container.decode(String.self)
        let secretData = try container.decode(SecretData.self)
        
        switch kindString.uppercased() {
        case "P2PK":
            self = .p2pk(secretData: secretData)
        case "HTLC":
            self = .htlc(secretData: secretData)
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid kind value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case .p2pk(let secretData):
            try container.encode("P2PK")
            try container.encode(secretData)
        case .htlc(let secretData):
            try container.encode("HTLC")
            try container.encode(secretData)
        }
    }
}

