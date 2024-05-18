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

enum Tag: Codable {
    case sigflag(values: [String])
    case n_sigs(values: [Int])

    // Custom decoding
    enum Tag: Codable {
        case sigflag(values: [String])
        case n_sigs(values: [Int])

        // Custom decoding
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()

            guard let type = try? container.decode(String.self) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode type identifier")
            }
            
            switch type {
            case "sigflag":
                var values = [String]()
                while !container.isAtEnd {
                    let value = try container.decode(String.self)
                    values.append(value)
                }
                self = .sigflag(values: values)
            case "n_sigs":
                var values = [Int]()
                while !container.isAtEnd {
                    let valueString = try container.decode(String.self)
                    if let value = Int(valueString) {
                        values.append(value)
                    } else {
                        throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Expected string representation of Int, got \(valueString)"))
                    }
                }
                self = .n_sigs(values: values)
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tag type: \(type)")
            }
        }

        // Custom encoding
        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()

            switch self {
            case .sigflag(let values):
                try container.encode("sigflag")
                for value in values {
                    try container.encode(value)
                }
            case .n_sigs(let values):
                try container.encode("n_sigs")
                for value in values {
                    try container.encode(String(value))
                }
            }
        }
    }

}

struct SpendingCondition: Codable {
    let nonce: String
    let data: String
    let tags: [Tag] //TODO: should check for types String or Int
}

enum Secret {
    case P2PK(sc:SpendingCondition)
    case HTLC(sc:SpendingCondition)
    case deterministic(s:String)
    
    func serialize() -> String {
        switch self {
        case .deterministic(let s):
            return s
        case let .HTLC(sc):
            let scData = try! JSONEncoder().encode(sc)
            return "\"HTLC\", \(String(data:scData, encoding: .utf8)!)"
        case .P2PK(let sc):
            let scData = try! JSONEncoder().encode(sc)
            return "\"P2PK\", \(String(data:scData, encoding: .utf8)!)"
        }
    }
}
