//
//  BLS.swift
//
//  Cashu v3 (BLS12-381) blind signatures: the pairing-based scheme used by `02…`
//  keysets, layered on the generic point/scalar/pairing primitives in SwiftBLST.
//
//  Curve roles (all wire values are compressed-point hex strings):
//    - Y  = hashToCurveG1(secret bytes)   G1, 48 bytes / 96 hex
//    - B_ = r·Y         (blinded message) G1
//    - C_ = a·B_        (mint signature)  G1
//    - C  = r⁻¹·C_      (unblinded sig)   G1
//    - K  = a·G2        (mint pubkey)     G2, 96 bytes / 192 hex
//  Verification is the pairing equality e(C, G2) == e(Y, K); v3 proofs carry no DLEQ.
//
//  On a v3 keyset the secret is a compressed secp256k1 public key (NUT-10 nutroot) and the
//  bytes fed to hash_to_curve are its decoded 33 bytes (NUT-00 "Secret bytes").
//

import Foundation
import CryptoKit
import secp256k1  // hex helpers: `String(bytes:)` and `String.bytes`
import SwiftBLST

extension CashuSwift.Crypto {
    /// Pairing-based blind signatures for BLS12-381 v3 keysets. Mirrors the secp BDHKE in `Crypto`.
    enum BLS {

        typealias Error = CashuSwift.Crypto.Error

        /// RFC 9380 hash-to-curve domain-separation tag for v3 keysets. Must match the mint.
        static let domainSeparationTag = BLST.BLSScheme.cashu  // "CASHU_BLS12_381_G1_XMD:SHA-256_SSWU_RO_"

        // MARK: - Primitives

        /// `Y = hashToCurveG1(message)` over raw bytes (a v3 proof's decoded 33-byte secret).
        static func hashToCurveG1(_ message: [UInt8]) -> BLST.G1Point {
            BLST.G1Point.hashToCurve(message: message, domainSeparationTag: domainSeparationTag)
        }

        /// Decode a compressed G1 point (`B_`/`C_`/`C`), rejecting bad encodings, the identity,
        /// and points outside the prime-order subgroup (NUT-00 Point Validation).
        static func g1Point(fromHex hex: String) throws -> BLST.G1Point {
            let point: BLST.G1Point
            do {
                point = try BLST.G1Point(compressed: try hex.bytes)
            } catch {
                throw Error.unblinding("Invalid BLS G1 point: \(error)")
            }
            if point.isInfinity { throw Error.unblinding("BLS G1 point is the identity") }
            return point
        }

        /// Decode a compressed G2 mint public key, rejecting bad encodings, the identity, and
        /// points outside the prime-order subgroup.
        static func g2Point(fromHex hex: String) throws -> BLST.G2Point {
            let point: BLST.G2Point
            do {
                point = try BLST.G2Point(compressed: try hex.bytes)
            } catch {
                throw Error.unblinding("Invalid BLS G2 mint key: \(error)")
            }
            if point.isInfinity { throw Error.unblinding("BLS G2 mint key is the identity") }
            return point
        }

        /// Interpret a 32-byte big-endian hex string as an Fr scalar; valid iff in `[1, Fr)`.
        static func scalar(fromHex hex: String) throws -> BLST.Scalar {
            do {
                return try BLST.Scalar(bytes: try hex.bytes)
            } catch {
                throw Error.unblinding("Invalid BLS blinding factor: \(error)")
            }
        }

        /// A uniformly random non-zero scalar in `[1, Fr)` via rejection sampling.
        ///
        /// `BLST.Scalar(bytes:)` accepts only `[1, Fr)` (blst's `blst_sk_check`), so trying random
        /// 32-byte values and keeping the first that decodes avoids the bias a modular reduction
        /// would introduce (Fr ≈ 0.45·2²⁵⁶).
        static func randomScalar() throws -> BLST.Scalar {
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<0x10000 {
                let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
                if let s = try? BLST.Scalar(bytes: bytes) { return s }
            }
            throw Error.unblinding("Failed to sample a valid BLS scalar")
        }

        // MARK: - Blind / Unblind / Verify

        /// `B_ = r·hashToCurveG1(secretBytes)`.
        static func blind(secretBytes: [UInt8], r: BLST.Scalar) -> BLST.G1Point {
            hashToCurveG1(secretBytes).multiplied(by: r)
        }

        /// Wallet-side unblinding `C = r⁻¹·C_`. Unlike secp additive blinding, no mint key is needed.
        static func unblind(C_: BLST.G1Point, r: BLST.Scalar) -> BLST.G1Point {
            C_.multiplied(by: r.inverse())
        }

        /// Single-proof verification via pairing equality `e(C, G2) == e(Y, K)`.
        static func verify(C: BLST.G1Point, mintKey K2: BLST.G2Point, secretBytes: [UInt8]) -> Bool {
            if C.isInfinity || K2.isInfinity { return false }
            let Y = hashToCurveG1(secretBytes)
            // e(C, G2) == e(Y, K)  ⇔  e(-C, G2) · e(Y, K) == 1
            return BLST.Pairing.productIsOne([(C.negated(), .generator), (Y, K2)])
        }

        // MARK: - Output helpers (hex in, hex out)
        //
        // shortcut: the `secret` slot of a v3 output holds the 32-byte private key `k` (64 hex),
        // not the wire secret `K = k·G`; `unblindPromises` derives `K` and attaches `spendInfo.k`.
        // Keeps the (outputs, blindingFactors, secrets) tuple shape every caller already persists.
        // Upgrade to a typed output set when the public tuple API is next broken anyway.

        /// A random blinded output: a fresh secp keypair `(k, K)` and a random Fr blinding factor.
        static func randomOutput() throws -> (B_: String, blindingFactor: String, secret: String) {
            let k = try CashuSwift.Crypto.PrivateKey()
            let r = try randomScalar()
            let B_ = blind(secretBytes: Array(k.publicKey.dataRepresentation), r: r)
            return (String(bytes: B_.compressedBytes), String(bytes: r.bytes), String(bytes: k.dataRepresentation))
        }

        /// A NUT-13 v3 deterministic blinded output for `(keysetID, counter)`:
        /// `k` by derivation type `0x00`, `r` by type `0x01`, `B_ = r·hashToCurveG1(k·G)`.
        static func deterministicOutput(keysetID: String,
                                        seed: String,
                                        index: Int) throws -> (B_: String, blindingFactor: String, secret: String) {
            guard index >= 0 else { throw Error.secretDerivation("negative derivation counter") }
            let derived = try CashuSwift.Crypto.v3ProofKeys(seed: seed, keysetID: keysetID, counter: UInt64(index))
            let B_ = blind(secretBytes: Array(derived.k.publicKey.dataRepresentation), r: derived.r)
            return (String(bytes: B_.compressedBytes),
                    String(bytes: derived.r.bytes),
                    String(bytes: derived.k.dataRepresentation))
        }

        /// Unblind a v3 promise to a proof's `C`, verifying the pairing equality against the mint's
        /// G2 key for the amount. Throws if verification fails.
        static func unblindAndVerify(C_Hex: String,
                                     blindingFactorHex: String,
                                     secretBytes: [UInt8],
                                     mintKeyHex: String) throws -> String {
            let C_ = try g1Point(fromHex: C_Hex)
            let r = try scalar(fromHex: blindingFactorHex)
            let K2 = try g2Point(fromHex: mintKeyHex)
            let C = unblind(C_: C_, r: r)
            guard verify(C: C, mintKey: K2, secretBytes: secretBytes) else {
                throw Error.unblinding("v3 pairing verification failed for unblinded signature")
            }
            return String(bytes: C.compressedBytes)
        }

        // MARK: - Batch verification

        typealias BatchItem = (C: BLST.G1Point, K2: BLST.G2Point, secret: [UInt8])

        /// Deterministic Fiat-Shamir per-proof batch weights, each a non-zero Fr scalar.
        ///
        /// Transcript: `"Cashu_BLS_Batch_v1" || (C || K2 || u32BE(len(secret)) || secret)*`, collapsed
        /// to a 32-byte challenge; per item `wᵢ` = first `SHA256(challenge || u32BE(i) || u32BE(ctr))`
        /// digest in `[1, Fr)`.
        static func deriveBatchWeights(_ items: [BatchItem]) throws -> [BLST.Scalar] {
            let challenge = batchChallenge(items)

            var weights = [BLST.Scalar]()
            weights.reserveCapacity(items.count)
            for i in 0..<items.count {
                var weight: BLST.Scalar? = nil
                for ctr in 0..<0x10000 {
                    let digest = Array(CryptoKit.SHA256.hash(data: Data(challenge + u32BE(i) + u32BE(ctr))))
                    if let s = try? BLST.Scalar(bytes: digest) { weight = s; break }
                }
                guard let w = weight else {
                    throw Error.unblinding("v3 batch weight derivation failed")
                }
                weights.append(w)
            }
            return weights
        }

        /// Batch-verify many proofs with a single multi-pairing. Returns `true` iff every individual
        /// `e(Cᵢ, G2) == e(Yᵢ, K2ᵢ)` holds. Equivalent to, but faster than, verifying each proof.
        static func batchVerify(_ items: [BatchItem]) throws -> Bool {
            if items.isEmpty { return true }
            for item in items where item.C.isInfinity || item.K2.isInfinity { return false }

            let weights = try deriveBatchWeights(items)

            // Left term: -Σ wᵢ·Cᵢ
            let weightedC = zip(items, weights).map { $0.0.C.multiplied(by: $0.1) }
            let sumC = try BLST.G1Point.aggregate(weightedC)

            // Right terms: Σ wᵢ·Yᵢ grouped by mint key K2.
            var grouped = [Data: (K2: BLST.G2Point, terms: [BLST.G1Point])]()
            for (item, w) in zip(items, weights) {
                let term = hashToCurveG1(item.secret).multiplied(by: w)
                let key = Data(item.K2.compressedBytes)
                grouped[key, default: (item.K2, [])].terms.append(term)
            }

            var pairs: [(g1: BLST.G1Point, g2: BLST.G2Point)] = [(sumC.negated(), .generator)]
            for (_, group) in grouped {
                let sumY = try BLST.G1Point.aggregate(group.terms)
                pairs.append((sumY, group.K2))
            }

            return BLST.Pairing.productIsOne(pairs)
        }

        /// 32-byte Fiat-Shamir challenge that collapses the whole batch transcript
        /// `"Cashu_BLS_Batch_v1" || (C || K2 || u32BE(len(secret)) || secret)*`.
        static func batchChallenge(_ items: [BatchItem]) -> [UInt8] {
            var transcript = CryptoKit.SHA256()
            transcript.update(data: Data("Cashu_BLS_Batch_v1".utf8))
            for item in items {
                transcript.update(data: Data(item.C.compressedBytes))
                transcript.update(data: Data(item.K2.compressedBytes))
                transcript.update(data: Data(u32BE(item.secret.count)))
                transcript.update(data: Data(item.secret))
            }
            return Array(transcript.finalize())
        }

        private static func u32BE(_ n: Int) -> [UInt8] {
            withUnsafeBytes(of: UInt32(n).bigEndian, Array.init)
        }
    }
}
