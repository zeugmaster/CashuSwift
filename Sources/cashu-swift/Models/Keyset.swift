//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation
import CryptoKit
import secp256k1

extension CashuSwift {
    struct KeysetList: Decodable {
        let keysets:[Keyset]
    }

    /// Represents a mint's keyset.
    public struct Keyset: Codable, Sendable {
        /// The keyset identifier.
        public let keysetID: String
        
        /// Mapping of amounts to public keys.
        public var keys: Dictionary<String, String> //FIXME: this should have an integer as key
        
        /// Counter for deterministic derivation.
        public var derivationCounter:Int
        
        /// Whether this keyset is active.
        public var active:Bool
        
        /// The unit this keyset supports.
        public let unit:String
        
        /// Input fee in parts per thousand.
        public let inputFeePPK:Int
        
        enum CodingKeys: String, CodingKey {
            case keysetID = "id" , keys, derivationCounter, active, unit
            case inputFeePPK = "input_fee_ppk"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keysetID = try container.decode(String.self, forKey: .keysetID)
            unit = try container.decode(String.self, forKey: .unit)
            
            derivationCounter = try container.decodeIfPresent(Int.self,
                                                              forKey: .derivationCounter) ?? 0
            active = try container.decodeIfPresent(Bool.self,
                                                   forKey: .active) ?? false
            keys = try container.decodeIfPresent(Dictionary<String, String>.self,
                                                 forKey: .keys) ?? ["none":"none"]
            inputFeePPK = try container.decodeIfPresent(Int.self,
                                                        forKey: .inputFeePPK) ?? 0
        }
        
        public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(keysetID, forKey: .keysetID)
                try container.encode(unit, forKey: .unit)
                try container.encode(derivationCounter, forKey: .derivationCounter)
                try container.encode(active, forKey: .active)
                try container.encode(keys, forKey: .keys)
                try container.encode(inputFeePPK, forKey: .inputFeePPK)
            }
        
        public var validID: Bool {
            if self.keysetID.count == 12 {
                return self.keysetID == Keyset.calculateKeysetID(keyset: self.keys)
            } else if keysetID.count == 16 {
                do {
                    return try self.keysetID == Keyset.calculateHexKeysetID(keyset: self.keys)
                } catch {
                    return false
                }
            } else {
                fatalError()
            }
        }
        
        static func calculateKeysetID(keyset:Dictionary<String,String>) -> String {
            let sortedValues = keyset.sorted { (firstElement, secondElement) -> Bool in
                guard let firstKey = UInt(firstElement.key),
                      let secondKey = UInt(secondElement.key) else {
                    return false
                }
                return firstKey < secondKey
            }.map { $0.value }
            
            let concat = sortedValues.joined()
            let hashData = Data(SHA256.hash(data: concat.data(using: .utf8)!))
            
            let id = String(hashData.base64EncodedString().prefix(12))
            
            return id
        }
        
        static func calculateHexKeysetID(keyset:Dictionary<String,String>) throws -> String {
            let sortedValues = keyset.sorted { (firstElement, secondElement) -> Bool in
                guard let firstKey = UInt(firstElement.key),
                      let secondKey = UInt(secondElement.key) else {
                    return false
                }
                return firstKey < secondKey
            }.map { $0.value }
            
            // Convert hex public key strings to bytes using secp256k1 extension, concatenate them, then hash
            var concatData = [UInt8]()
            for stringKey in sortedValues {
                // Use the secp256k1 String.bytes extension which properly parses hex strings
                let bytes = try stringKey.bytes
                concatData.append(contentsOf: bytes)
            }
            
            let hashData = Data(SHA256.hash(data: concatData))
            let hexString = hashData.map { String(format: "%02x", $0) }.joined()
            let result = String(hexString.prefix(14))
            
            return "00" + result
        }
    }
}
