//
//  SpendInfo.swift
//  CashuSwift
//
//  NUT-00 spend info: what the receiver of a v3 proof needs to spend it. JSON field
//  `spend_info` with keys `k/E/K/tree/u`; V4 token CBOR map `si` with byte-string
//  values under `k/e/i/t/u`.
//
//  Fund-critical: a proof whose tree is lost cannot be spent, and `k` is a bearer key.
//  Never log or put these values in error strings.
//

import Foundation
import SwiftCBOR
import secp256k1  // hex helpers: `String(bytes:)` and `String.bytes`

extension CashuSwift {
    public struct SpendInfo: Codable, Equatable, Hashable, Sendable {
        /// Bearer private key, 32-byte hex: "here is the key".
        public var k: String?
        /// Ephemeral public key, 33-byte hex: "derive your key" (NUT-28 slot 0).
        public var E: String?
        /// Internal public key, 33-byte hex: the key the secret is built from.
        public var K: String?
        /// Serialized NUT-10 leaves, hex, in slot order.
        public var tree: [String]?
        /// NUMS offset, 32-byte hex: proves `K = H + u·G` has no key path.
        public var u: String?

        public init(k: String? = nil, E: String? = nil, K: String? = nil, tree: [String]? = nil, u: String? = nil) {
            self.k = k
            self.E = E
            self.K = K
            self.tree = tree
            self.u = u
        }

        /// NUT-00 shape rules: `k` xor `E`; a disclosed tree is non-empty and has a key source;
        /// `u` needs a tree.
        public func validateShape() throws {
            if k != nil && E != nil {
                throw CashuError.spendingConditionError("spend info carries both k and E")
            }
            if let tree {
                guard !tree.isEmpty else { throw CashuError.spendingConditionError("spend info tree is empty") }
                guard k != nil || E != nil || K != nil else {
                    throw CashuError.spendingConditionError("spend info tree has no key source")
                }
            } else if u != nil {
                throw CashuError.spendingConditionError("spend info u without a tree")
            }
        }

        // shortcut: unknown `si` fields are dropped on re-serialization (NUT-00 says preserve);
        // add a raw-field carrier once a NUT defines any.
        init(fromCBOR cbor: CBOR) throws {
            guard let map = cbor.asMap() else {
                throw CashuError.tokenDecoding("spend info is not a CBOR map")
            }
            func hex(_ key: String) throws -> String? {
                guard let value = map[.utf8String(key)] else { return nil }
                guard let bytes = value.asByteString() else {
                    throw CashuError.tokenDecoding("spend info field \(key) is not a byte string")
                }
                return bytes.hexEncodedString()
            }
            k = try hex("k")
            E = try hex("e")
            K = try hex("i")
            u = try hex("u")
            if let t = map[.utf8String("t")] {
                guard let array = t.asArray() else { throw CashuError.tokenDecoding("spend info tree is not an array") }
                tree = try array.map { leaf in
                    guard let bytes = leaf.asByteString() else {
                        throw CashuError.tokenDecoding("spend info leaf is not a byte string")
                    }
                    return bytes.hexEncodedString()
                }
            }
        }

        func toCBOR() throws -> CBOR {
            var map = [CBOR: CBOR]()
            if let k { map[.utf8String("k")] = .byteString(try k.bytes) }
            if let E { map[.utf8String("e")] = .byteString(try E.bytes) }
            if let K { map[.utf8String("i")] = .byteString(try K.bytes) }
            if let u { map[.utf8String("u")] = .byteString(try u.bytes) }
            if let tree { map[.utf8String("t")] = .array(try tree.map { .byteString(try $0.bytes) }) }
            return .map(map)
        }
    }
}
