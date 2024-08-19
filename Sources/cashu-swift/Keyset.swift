//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation
import CryptoKit

struct KeysetList: Codable {
    let keysets:[Keyset]
}

#warning("Make sure derivation counter is not being reset when updating keyset info from mint.")

final class Keyset: Codable {
    let id: String
    var keys: Dictionary<String, String>
    var derivationCounter:Int
    var active:Bool
    let unit:String
    let inputFeePPK:Int
    
    enum CodingKeys: String, CodingKey {
        case id, keys, derivationCounter, active, unit
        case inputFeePPK = "input_fee_ppk"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
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
    
    init(id:String,
         keys:Dictionary<String,String>,
         derivationCounter:Int = 0,
         active:Bool = true,
         unit:String = "sat",
         inputFeePPK:Int) {
        self.id = id
        self.keys = keys
        self.derivationCounter = derivationCounter
        self.active = active
        self.unit = unit
        self.inputFeePPK = inputFeePPK
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
