//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

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
    
    func calculateFee(for proofs:[Proof]) throws -> Int {
        var sumFees = 0
        // FIXME: UNSAFE UNWRAPPING
        for proof in proofs {
            if let feeRate = self.keysets.first(where: { $0.id == proof.id })?.inputFeePPK {
                sumFees += feeRate
            } else {
                fatalError("trying to calculate fees for proofs of keyset with unknown ID")
            }
        }
        return (sumFees + 999) / 1000
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
