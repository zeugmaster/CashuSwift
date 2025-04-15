//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation
import CryptoKit

extension CashuSwift {
    struct KeysetList: Decodable {
        let keysets:[Keyset]
    }

    public struct Keyset: Codable, Sendable {
        public let keysetID: String
        public var keys: Dictionary<String, String> //FIXME: this should have an integer as key
        public var derivationCounter:Int
        public var active:Bool
        public let unit:String
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
        
        static func calculateHexKeysetID(keyset:Dictionary<String,String>) -> String {
            let sortedValues = keyset.sorted { (firstElement, secondElement) -> Bool in
                guard let firstKey = UInt(firstElement.key),
                      let secondKey = UInt(secondElement.key) else {
                    return false
                }
                return firstKey < secondKey
            }.map { $0.value }
            
            var concatData = [UInt8]()
            for stringKey in sortedValues {
                try! concatData.append(contentsOf: stringKey.bytes)
            }
            
            let hashData = Data(SHA256.hash(data: concatData))
            let result = String(bytes: hashData).prefix(14)
            
            return "00" + result
        }
    }
}
