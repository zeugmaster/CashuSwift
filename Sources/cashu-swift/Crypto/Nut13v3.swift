//
//  Nut13v3.swift
//  CashuSwift
//
//  NUT-13 derivation for v3 (`02…`) keysets. One framed HMAC message, five derivation
//  types, every secp output rejection-sampled against the curve order and the BLS
//  blinding factor against `BLS_FR_ORDER`:
//
//    message_v3 = "Cashu_KDF_HMAC_SHA256" || u32_BE(len(scope)) || scope
//                 || u64_BE(counter) || type || u32_BE(attempt) || suffix
//
//  Types 0x00–0x03 scope to the 33-byte keyset id and share the proof counter;
//  type 0x04 scopes to the mint's NUT-06 identity key and has its own quote counter.
//

import Foundation
import CryptoKit
import secp256k1
import SwiftBLST

extension CashuSwift.Crypto {

    /// NUT-13 v3 `derivation_type_byte`.
    enum V3DerivationType: UInt8 {
        case secretKey = 0x00
        case blindingFactor = 0x01
        case numsOffset = 0x02
        case leafKey = 0x03
        case quoteLockKey = 0x04
    }

    /// The HMAC message for one `(scope, counter, type, attempt)`; `scope` must be 33 bytes
    /// (a full keyset id or a compressed identity key), so short keyset ids are refused.
    static func v3Message(scope: [UInt8],
                          counter: UInt64,
                          type: V3DerivationType,
                          attempt: UInt32,
                          suffix: [UInt8] = []) throws -> [UInt8] {
        guard scope.count == 33 else {
            throw Error.secretDerivation("NUT-13 v3 scope must be 33 bytes (full keyset id or identity key)")
        }
        var m = Array("Cashu_KDF_HMAC_SHA256".utf8)
        m += withUnsafeBytes(of: UInt32(scope.count).bigEndian, Array.init) + scope
        m += withUnsafeBytes(of: counter.bigEndian, Array.init)
        m.append(type.rawValue)
        m += withUnsafeBytes(of: attempt.bigEndian, Array.init)
        m += suffix
        return m
    }

    /// First HMAC digest (attempt 0, 1, 2, …) that is a valid secp256k1 private key in `[1, n)`.
    static func v3SecpKey(seed: [UInt8],
                          scope: [UInt8],
                          counter: UInt64,
                          type: V3DerivationType,
                          suffix: [UInt8] = []) throws -> PrivateKey {
        for attempt in 0..<UInt32(0x10000) {
            let digest = hmacSHA256(key: seed, message: try v3Message(scope: scope, counter: counter,
                                                                       type: type, attempt: attempt,
                                                                       suffix: suffix))
            if let key = try? PrivateKey(dataRepresentation: digest) { return key }
        }
        throw Error.secretDerivation("NUT-13 v3 secp derivation exhausted its attempts")
    }

    /// First HMAC digest that is a valid Fr scalar in `[1, BLS_FR_ORDER)` (type `0x01`).
    static func v3BlindingFactor(seed: [UInt8], scope: [UInt8], counter: UInt64) throws -> BLST.Scalar {
        for attempt in 0..<UInt32(0x10000) {
            let digest = hmacSHA256(key: seed, message: try v3Message(scope: scope, counter: counter,
                                                                       type: .blindingFactor, attempt: attempt))
            if let r = try? BLST.Scalar(bytes: digest) { return r }
        }
        throw Error.secretDerivation("NUT-13 v3 blinding factor derivation exhausted its attempts")
    }

    /// The proof keys for one counter value: internal private key `k` (secret `K = k·G`) and
    /// blinding factor `r`.
    static func v3ProofKeys(seed: String, keysetID: String, counter: UInt64) throws -> (k: PrivateKey, r: BLST.Scalar) {
        let seedBytes = try seed.bytes
        let scope = try keysetID.bytes
        return (try v3SecpKey(seed: seedBytes, scope: scope, counter: counter, type: .secretKey),
                try v3BlindingFactor(seed: seedBytes, scope: scope, counter: counter))
    }

    /// NUMS offset `u` (type `0x02`) for a script-only secret at this counter.
    static func v3NumsOffset(seed: String, keysetID: String, counter: UInt64) throws -> PrivateKey {
        try v3SecpKey(seed: try seed.bytes, scope: try keysetID.bytes, counter: counter, type: .numsOffset)
    }

    /// Self-owned leaf key `i` (type `0x03`, suffix `u32_BE(i)`) at this counter.
    static func v3LeafKey(seed: String, keysetID: String, counter: UInt64, index: UInt32) throws -> PrivateKey {
        try v3SecpKey(seed: try seed.bytes, scope: try keysetID.bytes, counter: counter, type: .leafKey,
                      suffix: withUnsafeBytes(of: index.bigEndian, Array.init))
    }

    /// Mint quote lock key (type `0x04`) under the mint's NUT-06 identity `pubkey`, with its own
    /// quote counter. Returns the raw private key and the compressed public key hex.
    static func v3QuoteLockKey(seed: String, mintPubkey: String, counter: UInt64) throws -> (privateKey: Data, publicKey: String) {
        let scope = try nut20PublicKey(mintPubkey).dataRepresentation
        let key = try v3SecpKey(seed: try seed.bytes, scope: Array(scope), counter: counter, type: .quoteLockKey)
        return (key.dataRepresentation, String(bytes: key.publicKey.dataRepresentation))
    }

    static func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        Array(HMAC<CryptoKit.SHA256>.authenticationCode(for: Data(message), using: SymmetricKey(data: Data(key))))
    }
}
