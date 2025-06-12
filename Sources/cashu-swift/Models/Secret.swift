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

//extension CashuSwift {
//
//    struct SpendingCondition: Codable, Equatable {
//        
//        public enum Kind: String, Codable {
//            case P2PK, HTLC
//        }
//        
//        fileprivate struct SecretWrapper: Codable {
//            let kind: Kind
//            let condition: SpendingCondition
//
//            init(from decoder: Decoder) throws {
//                var container = try decoder.unkeyedContainer()
//                kind = try container.decode(Kind.self)
//                condition = try container.decode(SpendingCondition.self)
//            }
//        }
//        
//        func serialize() -> String {
//            switch self.kind {
//            case .HTLC:
//                let scData = try! JSONEncoder().encode(self)
//                return "[\"HTLC\", \(String(data:scData, encoding: .utf8)!)]"
//            case .P2PK:
//                let scData = try! JSONEncoder().encode(self)
//                return "[\"P2PK\", \(String(data:scData, encoding: .utf8)!)]"
//            }
//        }
//        
//        static func deserialize(from string:String) throws -> SpendingCondition? {
//            guard let data = string.data(using: .utf8) else {
//                return nil
//            }
//            do {
//                let wrapper = try JSONDecoder().decode(SecretWrapper.self, from: data)
//                return nil
//            } catch {
//                return nil
//            }
//        }
//
//        let kind: Kind
//        let nonce: String
//        let data: String
//        let tags: [Tag]? //TODO: should check for types String or Int
//        
//        static func == (lhs: SpendingCondition, rhs: SpendingCondition) -> Bool {
//            lhs.nonce == rhs.nonce &&
//            lhs.data == rhs.data 
//        }
//        
//        enum CodingKeys: CodingKey {
//            case kind
//            case nonce
//            case data
//            case tags
//        }
//              
//        
//        init(from decoder: any Decoder) throws {
//            let container: KeyedDecodingContainer<CashuSwift.SpendingCondition.CodingKeys> = try decoder.container(keyedBy: CashuSwift.SpendingCondition.CodingKeys.self)
//            self.kind = try container.decode(CashuSwift.SpendingCondition.Kind.self, forKey: CashuSwift.SpendingCondition.CodingKeys.kind)
//            self.nonce = try container.decode(String.self, forKey: CashuSwift.SpendingCondition.CodingKeys.nonce)
//            self.data = try container.decode(String.self, forKey: CashuSwift.SpendingCondition.CodingKeys.data)
//            self.tags = try container.decodeIfPresent([CashuSwift.SpendingCondition.Tag].self, forKey: CashuSwift.SpendingCondition.CodingKeys.tags)
//        }
//        
//        func encode(to encoder: any Encoder) throws {
//            var container = encoder.container(keyedBy: CashuSwift.SpendingCondition.CodingKeys.self)
////            try container.encode(self.kind, forKey: CashuSwift.SpendingCondition.CodingKeys.kind)
//            try container.encode(self.nonce, forKey: CashuSwift.SpendingCondition.CodingKeys.nonce)
//            try container.encode(self.data, forKey: CashuSwift.SpendingCondition.CodingKeys.data)
//            try container.encodeIfPresent(self.tags, forKey: CashuSwift.SpendingCondition.CodingKeys.tags)
//        }
//        
//        enum Tag: Codable, Hashable {
//            case sigflag(values: [String])
//            case n_sigs(values: [Int])
//            case pubkeys(values: [String])
//            case locktime(values: [Int])
//            case refund(values: [String])
//            
//            // Custom decoding
//            init(from decoder: Decoder) throws {
//                var container = try decoder.unkeyedContainer()
//
//                guard let type = try? container.decode(String.self) else {
//                    throw DecodingError.dataCorruptedError(in: container,
//                                                           debugDescription: "Cannot decode type identifier")
//                }
//                
//                switch type {
//                case "sigflag", "pubkeys", "refund": // these tags contain strings
//                    var values = [String]()
//                    while !container.isAtEnd {
//                        let value = try container.decode(String.self)
//                        values.append(value)
//                    }
//                    self = .sigflag(values: values)
//                case "n_sigs", "locktime": // these tags contain integers, encoded as strings
//                    var values = [Int]()
//                    while !container.isAtEnd {
//                        let valueString = try container.decode(String.self)
//                        if let value = Int(valueString) {
//                            values.append(value)
//                        } else {
//                            throw DecodingError.typeMismatch(Int.self,
//                                                             DecodingError.Context(codingPath: container.codingPath,
//                                                                                   debugDescription: "Expected string representation of Int, got \(valueString)"))
//                        }
//                    }
//                    self = .n_sigs(values: values)
//                default:
//                    throw DecodingError.dataCorruptedError(in: container,
//                                                           debugDescription: "Unknown tag type: \(type)")
//                }
//            }
//            
//            // Custom encoding
//            func encode(to encoder: Encoder) throws {
//                var container = encoder.unkeyedContainer()
//
//                switch self {
//                case .sigflag(let values):
//                    try container.encode("sigflag")
//                    for value in values {
//                        try container.encode(value)
//                    }
//                case .n_sigs(let values):
//                    try container.encode("n_sigs")
//                    for value in values {
//                        try container.encode(String(value))
//                    }
//                case .pubkeys(values: let values):
//                    try container.encode("pubkeys")
//                    for value in values {
//                        try container.encode(value)
//                    }
//                case .locktime(values: let values):
//                    try container.encode("locktime")
//                    for value in values {
//                        try container.encode(String(value))
//                    }
//                case .refund(values: let values):
//                    try container.encode("refund")
//                    for value in values {
//                        try container.encode(value)
//                    }
//                }
//            }
//        }
//    }
//}
