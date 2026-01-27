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
        
        /// Final expiry time for this keyset after which the mint is not obligated to any longer accept ecash of the keyset
        public let finalExpiry: Int?
        
        enum CodingKeys: String, CodingKey {
            case keysetID = "id" , keys, derivationCounter, active, unit
            case inputFeePPK = "input_fee_ppk"
            case finalExpiry = "final_expiry"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keysetID = try container.decode(String.self, forKey: .keysetID)
            unit = try container.decode(String.self, forKey: .unit)
            
            derivationCounter = try container.decodeIfPresent(Int.self,
                                                              forKey: .derivationCounter) ?? 0
            active = try container.decodeIfPresent(Bool.self,
                                                   forKey: .active) ?? false
            
            // we allow keys to be nil initially when loading from /keysets
            // and then we add them later, allowing us to only need one Keyset struct for loading them
            keys = try container.decodeIfPresent(Dictionary<String, String>.self,
                                                 forKey: .keys) ?? ["":""]
            
            inputFeePPK = try container.decodeIfPresent(Int.self,
                                                        forKey: .inputFeePPK) ?? 0
            finalExpiry = try container.decodeIfPresent(Int.self, forKey: .finalExpiry)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keysetID, forKey: .keysetID)
            try container.encode(unit, forKey: .unit)
            try container.encode(derivationCounter, forKey: .derivationCounter)
            try container.encode(active, forKey: .active)
            try container.encode(keys, forKey: .keys)
            try container.encode(inputFeePPK, forKey: .inputFeePPK)
            try container.encode(finalExpiry, forKey: .finalExpiry)
        }
        
        public var validID: Bool {
            if self.keysetID.count == 12 {
                return self.keysetID == Keyset.calculateLegacyKeysetID(keyset: self.keys)
            } else {
                do {
                    if self.keysetID.hasPrefix("00") {
                        return try Keyset.calculateHexKeysetID(keyset: self.keys) == self.keysetID
                    } else if self.keysetID.hasPrefix("01") {
                        return try Keyset.calculateHexKeysetIDv2(keyset: self.keys,
                                                                 unit: self.unit,
                                                                 inputFeePPK: self.inputFeePPK,
                                                                 finalExpiry: self.finalExpiry) == self.keysetID
                    } else {
                        return false
                    }
                } catch {
                    return false
                }
            }
        }
        
        public var shortID: String {
            if self.keysetID.count != 12 && self.keysetID.hasPrefix("01") {
                return String(self.keysetID.prefix(16))
            }
            return self.keysetID
        }
        
        static func calculateLegacyKeysetID(keyset:Dictionary<String,String>) -> String {
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
            let concatData = try concatKeysV0(keyset: keyset)
            
            let hashData = Data(SHA256.hash(data: concatData))
            let hexString = hashData.map { String(format: "%02x", $0) }.joined()
            let result = String(hexString.prefix(14))
            
            return "00" + result
        }
        
        static func calculateHexKeysetIDv2(keyset: Dictionary<String, String>,
                                            unit: String,
                                            inputFeePPK: Int?,
                                            finalExpiry: Int?) throws -> String {
            // 1. Sort keys by amount in ascending numerical order
            // 2. Concatenate as "amount:pubkey_hex" separated by commas
            let sortedPairs = keyset.sorted { (firstElement, secondElement) -> Bool in
                guard let firstKey = UInt(firstElement.key),
                      let secondKey = UInt(secondElement.key) else {
                    return false
                }
                return firstKey < secondKey
            }
            
            let keyStrings = sortedPairs.map { "\($0.key):\($0.value.lowercased())" }
            var preimage = keyStrings.joined(separator: ",")
            
            // 3. Add unit with "|unit:" prefix
            preimage += "|unit:\(unit.lowercased())"
            
            // 4. Add input_fee_ppk if non-zero
            if let fee = inputFeePPK, fee != 0 {
                preimage += "|input_fee_ppk:\(fee)"
            }
            
            // 5. Add final_expiry if present and non-zero
            if let finalExpiry, finalExpiry != 0 {
                preimage += "|final_expiry:\(finalExpiry)"
            }
            
            // 6. SHA256 hash
            let hash = Data(SHA256.hash(data: preimage.data(using: .utf8)!))
            
            // 7. Prefix with version byte "01" and return full hex
            return "01" + hash.map { String(format: "%02x", $0) }.joined()
        }
        
        private static func concatKeysV0(keyset: Dictionary<String, String>) throws -> [UInt8] {
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
            
            return concatData
        }
    }
}
