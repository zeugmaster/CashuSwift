//
//  P2BK.swift
//  CashuSwift
//
//  NUT-28 slot blinding, as used by v3 nutroot secrets: a sender with ephemeral `e` blinds a
//  receiver's static key `P` at slot `i` to `P' = P + rᵢ·G`,
//  `rᵢ = SHA256("Cashu_P2BK_v1" || x(e·P) || i)` (one retry with a trailing `0xff`), and the
//  receiver recovers the private key `p + rᵢ` (or `-p + rᵢ` on a parity mismatch).
//

import Foundation
import CryptoKit
import secp256k1

extension CashuSwift.Crypto {
    enum P2BK {
        typealias PrivateKey = CashuSwift.Crypto.PrivateKey
        typealias PublicKey = CashuSwift.Crypto.PublicKey

        static let domainSeparator = Array("Cashu_P2BK_v1".utf8)

        /// `x(scalar·point)`.
        static func sharedX(scalar: PrivateKey, point: PublicKey) throws -> [UInt8] {
            Array(try point.multiply(Array(scalar.dataRepresentation)).dataRepresentation.dropFirst())
        }

        /// The slot's blinding scalar, retried once with `0xff` when out of range.
        static func blindingScalar(sharedX: [UInt8], slot: UInt8) throws -> PrivateKey {
            let first = Array(SHA256.hash(data: Data(domainSeparator + sharedX + [slot])))
            if let r = try? PrivateKey(dataRepresentation: first) { return r }
            let second = Array(SHA256.hash(data: Data(domainSeparator + sharedX + [slot, 0xff])))
            if let r = try? PrivateKey(dataRepresentation: second) { return r }
            throw CashuError.cryptoError("P2BK blinding scalar out of range; discard the ephemeral")
        }

        /// Sender: `P' = P + rᵢ·G`.
        static func blind(_ key: PublicKey, ephemeral e: PrivateKey, slot: UInt8) throws -> PublicKey {
            let r = try blindingScalar(sharedX: try sharedX(scalar: e, point: key), slot: slot)
            return try key.add(Array(r.dataRepresentation))
        }

        /// Receiver: the private key behind `blinded` at `slot`, or `nil` when it is not ours.
        static func unblind(_ blinded: PublicKey,
                            receiverKey p: PrivateKey,
                            ephemeral E: PublicKey,
                            slot: UInt8) throws -> PrivateKey? {
            let r = try blindingScalar(sharedX: try sharedX(scalar: p, point: E), slot: slot)
            let unblinded = try blinded.combine([r.publicKey.negation])
            let natural = p.publicKey
            guard unblinded.xonly.bytes == natural.xonly.bytes else { return nil }
            let base = unblinded.dataRepresentation.first == natural.dataRepresentation.first ? p : try p.negation
            return try base.add(Array(r.dataRepresentation))
        }
    }
}
