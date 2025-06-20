//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation


extension CashuSwift {
    public struct SpendingCondition: Codable {
        
        public enum Kind: String, Codable {
            case P2PK, HTLC
        }
        
        let kind: Kind
        let payload: Payload
        
        public struct Payload: Codable {
            let nonce: String
            let data: String
            let tags: [Tag]?
        }
        
        init(kind: Kind, payload: Payload) {
            self.kind = kind
            self.payload = payload
        }
        
        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.kind = try container.decode(SpendingCondition.Kind.self)
            self.payload = try container.decode(SpendingCondition.Payload.self)
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(self.kind)
            try container.encode(self.payload)
        }
        
        public static func deserialize(from string: String) -> SpendingCondition? {
            guard let data = string.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(SpendingCondition.self, from: data)
        }
        
        public func serialize() throws -> String {
            let data = try JSONEncoder().encode(self)
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        public enum Tag: Codable, Hashable {
            case sigflag(values: [String])
            case n_sigs(values: [Int])
            case pubkeys(values: [String])
            case locktime(values: [Int])
            case refund(values: [String])
            
            // Custom decoding
            public init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()

                guard let type = try? container.decode(String.self) else {
                    throw DecodingError.dataCorruptedError(in: container,
                                                           debugDescription: "Cannot decode type identifier")
                }
                
                switch type {
                case "sigflag", "pubkeys", "refund": // these tags contain strings
                    var values = [String]()
                    while !container.isAtEnd {
                        let value = try container.decode(String.self)
                        values.append(value)
                    }
                    self = .sigflag(values: values)
                case "n_sigs", "locktime": // these tags contain integers, encoded as strings
                    var values = [Int]()
                    while !container.isAtEnd {
                        let valueString = try container.decode(String.self)
                        if let value = Int(valueString) {
                            values.append(value)
                        } else {
                            throw DecodingError.typeMismatch(Int.self,
                                                             DecodingError.Context(codingPath: container.codingPath,
                                                                                   debugDescription: "Expected string representation of Int, got \(valueString)"))
                        }
                    }
                    self = .n_sigs(values: values)
                default:
                    throw DecodingError.dataCorruptedError(in: container,
                                                           debugDescription: "Unknown tag type: \(type)")
                }
            }
            
            // Custom encoding
            public func encode(to encoder: Encoder) throws {
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
                case .pubkeys(values: let values):
                    try container.encode("pubkeys")
                    for value in values {
                        try container.encode(value)
                    }
                case .locktime(values: let values):
                    try container.encode("locktime")
                    for value in values {
                        try container.encode(String(value))
                    }
                case .refund(values: let values):
                    try container.encode("refund")
                    for value in values {
                        try container.encode(value)
                    }
                }
            }
        }
    }
}
