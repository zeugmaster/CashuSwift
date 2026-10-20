//
//  Transcript.swift
//  CashuSwift
//
//  NUT-00 §0.4 transactions (v3 keysets): the TLV transcript, per-input digests and the
//  signing rule. Every v3 input signs
//
//    transaction_digest = SHA256(transcript)
//    input_id           = SHA256(input container record)
//    input_digest       = tagged_hash("Cashu_TransactionInput", transaction_digest || input_id)
//
//  with a BIP-340 signature by its secret's key (proof) or its quote lock key (mint quote).
//

import Foundation
import CryptoKit
import secp256k1

extension CashuSwift {

    /// Byte helpers shared by keyset ids, transcripts and NUT-10 leaves.
    enum TLV {
        /// Minimal big-endian integer: zero encodes to no bytes.
        static func minimalBE(_ value: UInt64) -> [UInt8] {
            var v = value
            var out = [UInt8]()
            while v > 0 {
                out.insert(UInt8(v & 0xff), at: 0)
                v >>= 8
            }
            return out
        }

        /// Parses a minimal big-endian integer; a leading zero byte or more than 8 bytes is rejected.
        static func integer(_ bytes: [UInt8]) throws -> UInt64 {
            guard bytes.count <= 8, bytes.first != 0 else {
                throw CashuError.inputError("non-minimal TLV integer")
            }
            return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }

        static func u32BE(_ n: Int) -> [UInt8] {
            withUnsafeBytes(of: UInt32(n).bigEndian, Array.init)
        }

        /// `len32(x) || x`.
        static func framed(_ bytes: [UInt8]) -> [UInt8] {
            u32BE(bytes.count) + bytes
        }

        /// `type (1) || length (2, BE) || value`.
        static func record(_ type: UInt8, _ value: [UInt8]) throws -> [UInt8] {
            guard value.count <= 0xffff else {
                throw CashuError.inputError("TLV value exceeds 65535 bytes")
            }
            return [type] + withUnsafeBytes(of: UInt16(value.count).bigEndian, Array.init) + value
        }

        /// Splits a stream into `(type, value, raw record)` triples.
        static func records(_ bytes: [UInt8]) throws -> [(type: UInt8, value: [UInt8], raw: [UInt8])] {
            var out = [(type: UInt8, value: [UInt8], raw: [UInt8])]()
            var i = 0
            while i < bytes.count {
                guard i + 3 <= bytes.count else { throw CashuError.inputError("truncated TLV record") }
                let length = Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
                let end = i + 3 + length
                guard end <= bytes.count else { throw CashuError.inputError("truncated TLV record") }
                out.append((bytes[i], Array(bytes[(i + 3)..<end]), Array(bytes[i..<end])))
                i = end
            }
            return out
        }

        /// BIP-340 style `SHA256(SHA256(tag) || SHA256(tag) || message)`.
        static func taggedHash(_ tag: String, _ message: [UInt8]) -> [UInt8] {
            let tagHash = Array(SHA256.hash(data: Data(tag.utf8)))
            return Array(SHA256.hash(data: Data(tagHash + tagHash + message)))
        }

        static func sha256(_ bytes: [UInt8]) -> [UInt8] {
            Array(SHA256.hash(data: Data(bytes)))
        }

        /// A keyset id is hex-decoded iff it is an even-length string of lowercase hex digits,
        /// else its UTF-8 bytes are used.
        static func keysetIDBytes(_ id: String) -> [UInt8] {
            let hexDigits = Set("0123456789abcdef")
            if !id.isEmpty, id.count % 2 == 0, id.allSatisfy({ hexDigits.contains($0) }),
               let bytes = try? id.bytes {
                return bytes
            }
            return Array(id.utf8)
        }
    }

    /// A v3 transaction: value sources in, value sinks out, serialized as one TLV container
    /// record per element.
    public struct Transaction: Sendable {
        public enum Input: Sendable {
            case proof(Proof)
            /// A paid mint quote being drawn on: `amount` is what this transaction issues,
            /// `issued` the quote's `amount_issued` before it.
            case mintQuote(id: String, amount: Int, lockKey: String, issued: Int)
        }

        public enum Output: Sendable {
            case blinded(CashuSwift.Output)
            /// A melt quote: `amount` is the quote amount plus the selected fee reserve.
            case meltQuote(id: String, amount: Int)
        }

        public let inputs: [Input]
        public let outputs: [Output]

        public init(inputs: [Input], outputs: [Output]) {
            self.inputs = inputs
            self.outputs = outputs
        }

        static func container(_ input: Input) throws -> [UInt8] {
            switch input {
            case .proof(let proof):
                guard proof.amount >= 0 else { throw CashuError.invalidAmount }
                let fields = try TLV.record(0x01, TLV.minimalBE(UInt64(proof.amount)))
                    + TLV.record(0x02, TLV.keysetIDBytes(proof.keysetID))
                    + TLV.record(0x03, try CashuSwift.stateCheckY(for: proof).bytes)
                    + TLV.record(0x04, try proof.C.bytes)
                return try TLV.record(0x11, fields)
            case .mintQuote(let id, let amount, let lockKey, let issued):
                guard amount >= 0, issued >= 0 else { throw CashuError.invalidAmount }
                let fields = try TLV.record(0x01, TLV.minimalBE(UInt64(amount)))
                    + TLV.record(0x02, Array(id.utf8))
                    + TLV.record(0x03, Array(try Crypto.nut20PublicKey(lockKey).dataRepresentation))
                    + TLV.record(0x04, TLV.minimalBE(UInt64(issued)))
                return try TLV.record(0x12, fields)
            }
        }

        static func container(_ output: Output) throws -> [UInt8] {
            switch output {
            case .blinded(let output):
                guard output.amount >= 0 else { throw CashuError.invalidAmount }
                let point: [UInt8]
                if KeysetVersion(keysetID: output.id)?.isBLS == true {
                    point = try Crypto.BLS.g1Point(fromHex: output.B_).compressedBytes
                } else {
                    point = Array(try Crypto.PublicKey(dataRepresentation: output.B_.bytes, format: .compressed).dataRepresentation)
                }
                let fields = try TLV.record(0x01, TLV.minimalBE(UInt64(output.amount)))
                    + TLV.record(0x02, TLV.keysetIDBytes(output.id))
                    + TLV.record(0x03, TLV.sha256(point))
                return try TLV.record(0x21, fields)
            case .meltQuote(let id, let amount):
                guard amount >= 0 else { throw CashuError.invalidAmount }
                let fields = try TLV.record(0x01, TLV.minimalBE(UInt64(amount)))
                    + TLV.record(0x02, Array(id.utf8))
                return try TLV.record(0x22, fields)
            }
        }

        /// Containers grouped by ascending type, request order within a type.
        public func transcript() throws -> [UInt8] {
            guard !inputs.isEmpty, !outputs.isEmpty else {
                throw CashuError.inputError("a transaction needs at least one input and one output")
            }
            let inputRecords = try inputs.map(Transaction.container)
            let outputRecords = try outputs.map(Transaction.container)
            let grouped = inputRecords.enumerated().sorted { a, b in
                a.element[0] != b.element[0] ? a.element[0] < b.element[0] : a.offset < b.offset
            } + outputRecords.enumerated().sorted { a, b in
                a.element[0] != b.element[0] ? a.element[0] < b.element[0] : a.offset < b.offset
            }
            return grouped.flatMap { $0.element }
        }

        public func digest() throws -> [UInt8] {
            TLV.sha256(try transcript())
        }

        /// The digest input `index` signs.
        public func inputDigest(_ index: Int) throws -> [UInt8] {
            Transaction.inputDigest(transactionDigest: try digest(),
                                    container: try Transaction.container(inputs[index]))
        }

        static func inputDigest(transactionDigest: [UInt8], container: [UInt8]) -> [UInt8] {
            TLV.taggedHash("Cashu_TransactionInput", transactionDigest + TLV.sha256(container))
        }
    }
}

// MARK: - BIP-340 over a 32-byte digest

extension CashuSwift.Crypto {
    /// BIP-340 signature over a 32-byte digest (no re-hashing), hex-encoded. Auxiliary randomness
    /// is left to libsecp256k1's default, which equals 32 zero bytes and matches the spec vectors.
    static func schnorrSign(digest: [UInt8], key: secp256k1.Schnorr.PrivateKey) throws -> String {
        guard digest.count == 32 else { throw CashuError.cryptoError("digest must be 32 bytes") }
        var message = digest
        let signature = try key.signature(message: &message, auxiliaryRand: nil, strict: true)
        return String(bytes: signature.dataRepresentation)
    }

    /// Verifies a BIP-340 signature over a 32-byte digest against a compressed public key (x-only).
    static func schnorrVerify(digest: [UInt8], signatureHex: String, publicKey: [UInt8]) -> Bool {
        guard digest.count == 32, publicKey.count == 33,
              let sigBytes = try? signatureHex.bytes, sigBytes.count == 64,
              let signature = try? secp256k1.Schnorr.SchnorrSignature(dataRepresentation: sigBytes) else {
            return false
        }
        var message = digest
        let xonly = secp256k1.Schnorr.XonlyKey(dataRepresentation: Array(publicKey[1...]), keyParity: 0)
        return xonly.isValid(signature, for: &message)
    }
}

// MARK: - The signing rule

extension CashuSwift {
    /// Signs every v3 proof input that has no witness yet with its key-path key, derived from
    /// the proof's spend info (`k`, tweaked by its tree if it discloses one). Pre-v3 inputs and
    /// inputs that already carry a witness (NUT-11, or a merged script-path witness) are left as is.
    static func signV3Inputs(_ proofs: [Proof], outputs: [Transaction.Output]) throws -> [Proof] {
        let needsSigning = proofs.indices.filter {
            KeysetVersion(keysetID: proofs[$0].keysetID)?.isBLS == true && proofs[$0].witness == nil
        }
        if needsSigning.isEmpty { return proofs }

        let transaction = Transaction(inputs: proofs.map { .proof($0) }, outputs: outputs)
        var signed = proofs
        for i in needsSigning {
            let key = try Nutroot.keyPathKey(for: proofs[i])
            let signature = try Crypto.schnorrSign(digest: try transaction.inputDigest(i), key: key)
            signed[i].witness = try Proof.Witness(signatures: [signature]).stringJSON()
        }
        return signed
    }
}
