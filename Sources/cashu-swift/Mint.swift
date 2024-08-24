//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import SwiftData

/// This is the mint object.

@Model
public class Mint: Identifiable, Hashable {
    
    @Attribute(.unique) let url: URL
    var keysets: [Keyset]
    var info:MintInfo?
    var nickname:String?
    
    public static func == (lhs: Mint, rhs: Mint) -> Bool {
        lhs.url == rhs.url
    }
    
    public init(with url:URL) async throws {
        self.url = url
        
        // load keysets or fail with error propagating up
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            let new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.id.makeURLSafe())"),
                                                expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        // TODO: load mint info
        
        self.keysets = keysetsWithKeys
    }
    
    public func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
    
    ///Pings the mint for it's info to check wether it is online or not
    public func isReachable() async -> Bool {
        do {
             //if the network doesn't throw an error we can assume the mint is online
            let url = self.url.appending(path: "/v1/info")
            let _ = try await Network.get(url: url)
            return true
        } catch {
            return false
        }
    }
    
    public func calculateFee(for proofs:[Proof]) throws -> Int {
        var sumFees = 0
        for proof in proofs {
            if let feeRate = self.keysets.first(where: { $0.id == proof.id })?.inputFeePPK {
                sumFees += feeRate
            } else {
                throw CashuError.feeCalculationError("trying to calculate fees for proofs of keyset \(proof.keysetID) which does not seem to axxociated with mint \(self.url.absoluteString).")
            }
        }
        return (sumFees + 999) / 1000
    }
}

struct MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let descriptionShort: String?
    let descriptionLong: String?
    let contact: [[String]]
    let motd: String?
    let nuts: [String: Nut]

    enum CodingKeys: String, CodingKey {
        case name, pubkey, version, contact, motd, nuts
        case descriptionLong = "description_long"
        case descriptionShort = "description"
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
