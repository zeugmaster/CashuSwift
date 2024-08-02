//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import CryptoKit

struct KeysetList: Codable {
    let keysets:[Keyset]
}

#warning("Make sure derivation counter is not being reset when updating keyset info from mint.")

struct Keyset: Codable {
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
}

class Mint: Identifiable, Hashable, Codable {
    
    let url: URL
    var keysets: [Keyset]
    var info:MintInfo?
    var nickname:String?
    
    static func == (lhs: Mint, rhs: Mint) -> Bool {
        lhs.url == rhs.url
    }
    
    init(with url:URL) async throws {
        self.url = url
        
        // load keysets or fail with error propagating up
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            var new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.id.makeURLSafe())"),
                                                expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        // TODO: load mint info
        
        self.keysets = keysetsWithKeys
    }
    
    func hash(into hasher: inout Hasher) {
            hasher.combine(url) // Combine all properties that contribute to the object's uniqueness
            // If needed, combine more properties:
            // hasher.combine(name)
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
    
    ///Pings the mint for it's info to check wether it is online or not
    func isReachable() async -> Bool {
        do {
             //if the network doesn't throw an error we can assume the mint is online
            let url = self.url.appending(path: "/v1/info")
            let _ = try await Network.get(url: url)
            return true
        } catch {
            return false
        }
    }
}

struct MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let description: String?
    let descriptionLong: String?
    let contact: [[String]]
    let motd: String?
    let nuts: [String: Nut]

    enum CodingKeys: String, CodingKey {
        case name, pubkey, version, description, contact, motd, nuts
        case descriptionLong = "description_long"
    }
    
    struct Nut: Codable {
        let methods: [PaymentMethod]?
        let disabled: Bool?
        let supported: Bool?

        enum CodingKeys: String, CodingKey {
            case methods, disabled, supported
        }
    }
    
    //TODO: ADD MPP SETTINGS STRUCT
    
    struct PaymentMethod: Codable {
        let method: String
        let unit: String
        let minAmount: Int?
        let maxAmount: Int?

        enum CodingKeys: String, CodingKey {
            case method, unit
            case minAmount = "min_amount"
            case maxAmount = "max_amount"
        }
    }
}
