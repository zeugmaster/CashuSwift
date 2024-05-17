//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import CryptoKit

struct Keyset: Codable {
    let id: String
    let keys: Dictionary<String, String>
    var derivationCounter:Int
    let unit:String
    
    init(id: String, keys: Dictionary<String, String>, derivationCounter: Int, unit:String) {
        self.id = id
        self.keys = keys
        self.derivationCounter = derivationCounter
        self.unit = unit
    }
}

class Mint: Identifiable, Hashable {
    
    let url: URL
    var activeKeyset: Keyset
    var allKeysets: [Keyset]
    var info:MintInfo
    var nickname:String?
    
    static func == (lhs: Mint, rhs: Mint) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
            hasher.combine(url) // Combine all properties that contribute to the object's uniqueness
            // If needed, combine more properties:
            // hasher.combine(name)
        }
    
    init(url: URL, activeKeyset: Keyset, allKeysets: [Keyset], info: MintInfo, nickname:String? = nil) {
        self.url = url
        self.activeKeyset = activeKeyset
        self.allKeysets = allKeysets
        self.info = info
        self.nickname = nickname
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
//        do {
//             if the network doesn't throw an error we can assume the mint is online
//            let _ = try await Network.mintInfo(mintURL: self.url)
//            and return true
//            return true
//        } catch {
//            return false
//        }
        fatalError()
    }
}

struct MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let contact: [[String]] //FIXME: array in array?
    let nuts: [String]
    let parameter:Dictionary<String,Bool>
}
