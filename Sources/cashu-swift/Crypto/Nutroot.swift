//
//  Nutroot.swift
//  CashuSwift
//
//  NUT-10 nutroot secrets (v3 keysets). A secret is a compressed secp256k1 key: bare
//  `K = k·G`, or tweaked `P = K + t·G` with `t = tagged_hash("Cashu_NutrootTweak", K || root)`
//  committing a merkle tree of condition leaves. Key path: sign with `k` (+ `t`).
//  Script path: reveal one leaf, its merkle path and the signatures it asks for.
//

import Foundation
import CryptoKit
import secp256k1

extension CashuSwift {
    public enum Nutroot {
        typealias PrivateKey = Crypto.PrivateKey
        typealias PublicKey = Crypto.PublicKey

        /// BIP341's NUMS point `lift_x(SHA256(G_uncompressed))`.
        public static let numsPoint = "0250929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"

        static let maxLeaves = 8
        static let maxPath = 3
        static let maxLeafBody = 512

        // MARK: - Leaves

        /// A version-0 condition leaf. `serialized()` is the byte string used everywhere.
        public struct Leaf: Equatable, Sendable {
            public enum Kind: UInt8, Sendable {
                case threshold = 0x01
                case after = 0x02
                case hashlock = 0x03
                case commit = 0x04
            }

            public let kind: Kind
            /// Signature threshold (`threshold`, `after`, `hashlock`).
            public let n: Int?
            /// Listed signer keys, compressed 33-byte hex (`threshold`, `after`, `hashlock`).
            public let keys: [String]
            /// Unix seconds the leaf unlocks at (`after`).
            public let time: UInt64?
            /// SHA-256 digest, hex (`hashlock`, `commit`).
            public let hash: String?

            public init(kind: Kind, n: Int? = nil, keys: [String] = [], time: UInt64? = nil, hash: String? = nil) throws {
                self.kind = kind
                self.n = n
                self.keys = keys
                self.time = time
                self.hash = hash
                try validate()
            }

            public static func threshold(n: Int, keys: [String]) throws -> Leaf {
                try Leaf(kind: .threshold, n: n, keys: keys)
            }

            public static func after(_ time: UInt64, n: Int, keys: [String]) throws -> Leaf {
                try Leaf(kind: .after, n: n, keys: keys, time: time)
            }

            public static func hashlock(_ hash: String, n: Int, keys: [String]) throws -> Leaf {
                try Leaf(kind: .hashlock, n: n, keys: keys, hash: hash)
            }

            public static func commit(_ hash: String) throws -> Leaf {
                try Leaf(kind: .commit, hash: hash)
            }

            private func validate() throws {
                let wantsKeys = kind != .commit
                guard wantsKeys == (n != nil), wantsKeys == !keys.isEmpty,
                      (kind == .after) == (time != nil),
                      (kind == .hashlock || kind == .commit) == (hash != nil) else {
                    throw CashuError.spendingConditionError("leaf fields do not match its type")
                }
                if let n {
                    guard n >= 1, n <= keys.count, n <= 255 else {
                        throw CashuError.spendingConditionError("leaf threshold n out of range")
                    }
                }
                var xs = Set<[UInt8]>()
                for key in keys {
                    let point = try Crypto.nut20PublicKey(key)
                    guard xs.insert(point.xonly.bytes).inserted else {
                        throw CashuError.spendingConditionError("leaf lists one signer twice")
                    }
                }
                if let time { guard time <= (1 << 53) - 1 else { throw CashuError.spendingConditionError("leaf time too large") } }
                if let hash { guard (try? hash.bytes)?.count == 32 else { throw CashuError.spendingConditionError("leaf hash must be 32 bytes") } }
                guard try serialized().count <= maxLeafBody + 1 else {
                    throw CashuError.spendingConditionError("leaf body exceeds 512 bytes")
                }
            }

            /// `0x00 || type || field TLVs` with fields in ascending type order.
            public func serialized() throws -> [UInt8] {
                var out: [UInt8] = [0x00, kind.rawValue]
                if let n { out += try TLV.record(0x02, [UInt8(n)]) }
                if !keys.isEmpty { out += try TLV.record(0x04, try keys.flatMap { try $0.bytes }) }
                if let time { out += try TLV.record(0x06, TLV.minimalBE(time)) }
                if let hash { out += try TLV.record(0x08, try hash.bytes) }
                return out
            }

            public func serializedHex() throws -> String {
                String(bytes: try serialized())
            }

            /// Parses a leaf, failing closed on an unknown version, type or field.
            public static func parse(_ bytes: [UInt8]) throws -> Leaf {
                guard bytes.count >= 2 else { throw CashuError.spendingConditionError("leaf too short") }
                guard bytes[0] == 0x00 else { throw CashuError.spendingConditionError("unknown leaf version") }
                guard let kind = Kind(rawValue: bytes[1]) else { throw CashuError.spendingConditionError("unknown leaf type") }
                guard bytes.count - 1 <= maxLeafBody else { throw CashuError.spendingConditionError("leaf body exceeds 512 bytes") }

                var n: Int?
                var keys = [String]()
                var time: UInt64?
                var hash: String?
                var lastType: UInt8 = 0
                for record in try TLV.records(Array(bytes[2...])) {
                    guard record.type > lastType else { throw CashuError.spendingConditionError("leaf fields not strictly ascending") }
                    lastType = record.type
                    switch record.type {
                    case 0x02:
                        guard record.value.count == 1 else { throw CashuError.spendingConditionError("leaf n must be one byte") }
                        n = Int(record.value[0])
                    case 0x04:
                        guard record.value.count % 33 == 0, !record.value.isEmpty else {
                            throw CashuError.spendingConditionError("leaf keys must be 33-byte points")
                        }
                        keys = stride(from: 0, to: record.value.count, by: 33).map {
                            String(bytes: Array(record.value[$0..<($0 + 33)]))
                        }
                    case 0x06:
                        time = try TLV.integer(record.value)
                    case 0x08:
                        hash = String(bytes: record.value)
                    default:
                        throw CashuError.spendingConditionError("unknown leaf field")
                    }
                }
                let leaf = try Leaf(kind: kind, n: n, keys: keys, time: time, hash: hash)
                guard try leaf.serialized() == bytes else {
                    throw CashuError.spendingConditionError("leaf is not canonically encoded")
                }
                return leaf
            }

            public static func parse(hex: String) throws -> Leaf {
                try parse(try hex.bytes)
            }
        }

        // MARK: - The tree

        static func leafHash(_ leaf: [UInt8]) -> [UInt8] {
            TLV.taggedHash("Cashu_NutrootLeaf", leaf)
        }

        static func branch(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
            let (lo, hi) = a.lexicographicallyPrecedes(b) ? (a, b) : (b, a)
            return TLV.taggedHash("Cashu_NutrootBranch", lo + hi)
        }

        /// Merkle root and the sibling path for `index`: sort leaf hashes ascending, pair per level,
        /// promote an unpaired last hash, never deduplicate.
        static func fold(leaves: [[UInt8]], index: Int?) throws -> (root: [UInt8], path: [[UInt8]]) {
            guard !leaves.isEmpty, leaves.count <= maxLeaves else {
                throw CashuError.spendingConditionError("a tree holds 1 to 8 leaves")
            }
            let hashes = leaves.map(leafHash)
            var level = hashes.sorted { $0.lexicographicallyPrecedes($1) }
            var position = index.flatMap { i in level.firstIndex(of: hashes[i]) }
            var path = [[UInt8]]()
            while level.count > 1 {
                var next = [[UInt8]]()
                var i = 0
                while i < level.count {
                    if i + 1 < level.count {
                        if let p = position, p == i || p == i + 1 { path.append(level[p == i ? i + 1 : i]) }
                        next.append(branch(level[i], level[i + 1]))
                    } else {
                        next.append(level[i])
                    }
                    i += 2
                }
                position = position.map { $0 / 2 }
                level = next
            }
            return (level[0], path)
        }

        public static func root(leaves: [String]) throws -> String {
            String(bytes: try fold(leaves: try leaves.map { try $0.bytes }, index: nil).root)
        }

        public static func merklePath(leaves: [String], index: Int) throws -> [String] {
            guard leaves.indices.contains(index) else { throw CashuError.spendingConditionError("leaf index out of range") }
            return try fold(leaves: try leaves.map { try $0.bytes }, index: index).path.map { String(bytes: $0) }
        }

        static func rootFrom(leaf: [UInt8], path: [[UInt8]]) throws -> [UInt8] {
            guard path.count <= maxPath else { throw CashuError.spendingConditionError("merkle path longer than 3") }
            return path.reduce(leafHash(leaf)) { branch($0, $1) }
        }

        // MARK: - The tweak

        /// secp256k1 curve order `n`.
        private static let curveOrder: [UInt8] = [
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
            0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2, 0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41
        ]

        /// Reduces a 32-byte hash mod `n` (one subtraction suffices since the hash is below 2n).
        static func reduceModN(_ hash: [UInt8]) -> [UInt8] {
            guard !hash.lexicographicallyPrecedes(curveOrder) else { return hash }
            var out = [UInt8](repeating: 0, count: 32)
            var borrow = 0
            for i in stride(from: 31, through: 0, by: -1) {
                let d = Int(hash[i]) - Int(curveOrder[i]) - borrow
                out[i] = UInt8((d + 256) & 0xff)
                borrow = d < 0 ? 1 : 0
            }
            return out
        }

        /// `t = tagged_hash("Cashu_NutrootTweak", K || root) mod n`; `root == nil` is the empty tweak.
        static func tweak(internalKey K: [UInt8], root: [UInt8]?) -> [UInt8] {
            reduceModN(TLV.taggedHash("Cashu_NutrootTweak", K + (root ?? [])))
        }

        /// Adds `t·G` to a point; a zero tweak returns the point unchanged.
        static func add(_ key: PublicKey, tweak: [UInt8]) throws -> PublicKey {
            tweak.allSatisfy({ $0 == 0 }) ? key : try key.add(tweak)
        }

        static func add(_ key: PrivateKey, tweak: [UInt8]) throws -> PrivateKey {
            tweak.allSatisfy({ $0 == 0 }) ? key : try key.add(tweak)
        }

        /// The secret for internal key `K` under `leaves` (`nil` = bare key, `[]` = empty tweak).
        static func secret(internalKey K: PublicKey, leaves: [[UInt8]]?) throws -> PublicKey {
            guard let leaves else { return K }
            let root: [UInt8]? = leaves.isEmpty ? nil : try fold(leaves: leaves, index: nil).root
            return try add(K, tweak: tweak(internalKey: Array(K.dataRepresentation), root: root))
        }

        /// The key-path private key for `k` under `leaves`: `k + t`.
        static func keyPathPrivateKey(k: PrivateKey, leaves: [[UInt8]]?) throws -> PrivateKey {
            guard let leaves else { return k }
            let root: [UInt8]? = leaves.isEmpty ? nil : try fold(leaves: leaves, index: nil).root
            return try add(k, tweak: tweak(internalKey: Array(k.publicKey.dataRepresentation), root: root))
        }

        /// `K = H + u·G`.
        static func numsInternalKey(offset u: PrivateKey) throws -> PublicKey {
            try Crypto.nut20PublicKey(numsPoint).add(Array(u.dataRepresentation))
        }

        // MARK: - Spend info resolution (NUT-00 receive-time check 1)

        /// What the wallet learned about a v3 proof from its spend info.
        struct Resolved {
            let internalKey: PublicKey
            /// The key-path private key (already tweaked), when the wallet holds it.
            let keyPathKey: PrivateKey?
            /// The bearer `k` behind `internalKey`, when held.
            let internalPrivateKey: PrivateKey?
            let leaves: [[UInt8]]?
        }

        /// Reconstructs the secret from the proof's spend info, taking the internal key from `k`,
        /// deriving it at NUT-28 slot 0 from `E` and `receiverKey`, or using the disclosed `K`
        /// (always for a NUMS offset). Throws when the spend info does not reproduce
        /// `proof.secret` or is malformed.
        static func resolve(_ proof: Proof, receiverKey: PrivateKey? = nil) throws -> Resolved {
            guard KeysetVersion(keysetID: proof.keysetID)?.isBLS == true else {
                throw CashuError.spendingConditionError("not a v3 proof")
            }
            guard let info = proof.spendInfo else {
                throw CashuError.spendingConditionError("v3 proof carries no spend info")
            }
            try info.validateShape()
            let secretPoint = try Crypto.nut20PublicKey(proof.secret)
            let leaves = try info.tree?.map { try $0.bytes }
            for leaf in leaves ?? [] { _ = try Leaf.parse(leaf) }
            let disclosed = try info.K.map { try Crypto.nut20PublicKey($0) }

            // Candidate internal keys by precedence: bearer, receiver-keyed, disclosed.
            var candidates: [(key: PublicKey, priv: PrivateKey?)]
            if let kHex = info.k {
                let k = try PrivateKey(dataRepresentation: try kHex.bytes)
                candidates = [(k.publicKey, k)]
            } else if let eHex = info.E, info.u == nil {
                guard let receiverKey else {
                    throw CashuError.spendingConditionError("receiver-keyed proof needs the receiver's private key")
                }
                let E = try Crypto.nut20PublicKey(eHex)
                let r = Array(try Crypto.P2BK.blindingScalar(sharedX: try Crypto.P2BK.sharedX(scalar: receiverKey, point: E), slot: 0).dataRepresentation)
                candidates = try [receiverKey, receiverKey.negation].map { base in
                    let k = try base.add(r)
                    return (k.publicKey, k)
                }
            } else if let disclosed {
                candidates = [(disclosed, nil)]
            } else {
                throw CashuError.spendingConditionError("spend info has no key source")
            }
            if let disclosed {
                candidates = candidates.filter { $0.key.dataRepresentation == disclosed.dataRepresentation }
                guard !candidates.isEmpty else {
                    throw CashuError.spendingConditionError("disclosed K differs from the derived internal key")
                }
            }

            // The spend-info shape fixes which tweak must reproduce the secret.
            let forms: [[[UInt8]]?] = leaves.map { [$0] } ?? [nil, []]
            for candidate in candidates {
                for form in forms where try secret(internalKey: candidate.key, leaves: form).dataRepresentation == secretPoint.dataRepresentation {
                    if let uHex = info.u {
                        let u = try PrivateKey(dataRepresentation: try uHex.bytes)
                        guard try candidate.key.combine([u.publicKey.negation]).dataRepresentation
                                == Crypto.nut20PublicKey(numsPoint).dataRepresentation else {
                            throw CashuError.spendingConditionError("NUMS offset does not reproduce H")
                        }
                        return Resolved(internalKey: candidate.key, keyPathKey: nil, internalPrivateKey: nil, leaves: form)
                    }
                    return Resolved(internalKey: candidate.key,
                                    keyPathKey: try candidate.priv.map { try keyPathPrivateKey(k: $0, leaves: form) },
                                    internalPrivateKey: candidate.priv,
                                    leaves: form)
                }
            }
            throw CashuError.spendingConditionError(info.E != nil && info.k == nil && info.u == nil
                                                    ? "proof is not keyed to this receiver"
                                                    : "spend info does not reproduce the secret")
        }

        /// The key that key-path signs this proof, from its bearer spend info.
        static func keyPathKey(for proof: Proof) throws -> secp256k1.Schnorr.PrivateKey {
            guard let key = try resolve(proof).keyPathKey else {
                throw CashuError.spendingConditionError("no key path for this proof; provide a script-path witness")
            }
            return try secp256k1.Schnorr.PrivateKey(dataRepresentation: key.dataRepresentation)
        }

        /// Rewrites a receiver-keyed proof (`E`) into bearer form (`k`) using the receiver's private
        /// key, so the generic signing rule can spend it. Leaves other proofs untouched.
        static func claim(_ proof: Proof, receiverKey: PrivateKey?) throws -> Proof {
            guard KeysetVersion(keysetID: proof.keysetID)?.isBLS == true, proof.spendInfo != nil else { return proof }
            let resolved = try resolve(proof, receiverKey: receiverKey)
            guard let k = resolved.internalPrivateKey, proof.spendInfo?.E != nil else { return proof }
            var claimed = proof
            claimed.spendInfo = SpendInfo(k: String(bytes: k.dataRepresentation),
                                          K: proof.spendInfo?.tree == nil ? nil : String(bytes: resolved.internalKey.dataRepresentation),
                                          tree: proof.spendInfo?.tree,
                                          u: proof.spendInfo?.u)
            return claimed
        }

        // MARK: - Script path

        /// Builds a script-path witness revealing `leaves[leafIndex]`, signed over `inputDigest` by
        /// every `keys` entry the leaf lists. `preimage` is required for a hashlock leaf.
        public static func scriptPathWitness(internalKey: String,
                                             leaves: [String],
                                             leafIndex: Int,
                                             inputDigest: [UInt8],
                                             keys: [secp256k1.Schnorr.PrivateKey],
                                             preimage: String? = nil) throws -> Proof.Witness {
            let leaf = try Leaf.parse(hex: leaves[leafIndex])
            guard leaf.kind != .commit else { throw CashuError.spendingConditionError("a commit leaf cannot be spent") }
            let signatures = try keys
                .filter { leaf.keys.contains(String(bytes: $0.publicKey.dataRepresentation)) }
                .map { try Crypto.schnorrSign(digest: inputDigest, key: $0) }
            return Proof.Witness(signatures: signatures,
                                 leaf: leaves[leafIndex],
                                 control: .init(K: internalKey, path: try merklePath(leaves: leaves, index: leafIndex)),
                                 preimage: leaf.kind == .hashlock ? preimage : nil)
        }

        /// Verifies a script-path witness against `secret` and `inputDigest` (NUT-10 §Script path).
        public static func verifyScriptPath(_ witness: Proof.Witness,
                                            secret: String,
                                            inputDigest: [UInt8],
                                            now: UInt64 = UInt64(Date().timeIntervalSince1970)) throws {
            guard let leafHex = witness.leaf, let control = witness.control else {
                throw CashuError.spendingConditionError("witness is not a script-path witness")
            }
            let leafBytes = try leafHex.bytes
            let path = try control.path.map { try $0.bytes }
            let K = try Crypto.nut20PublicKey(control.K)
            let root = try rootFrom(leaf: leafBytes, path: path)
            let expected = try add(K, tweak: tweak(internalKey: Array(K.dataRepresentation), root: root))
            guard try expected.dataRepresentation == Crypto.nut20PublicKey(secret).dataRepresentation else {
                throw CashuError.spendingConditionError("control block does not commit to the secret")
            }
            let leaf = try Leaf.parse(leafBytes)
            guard leaf.kind != .commit else { throw CashuError.spendingConditionError("commit leaf revealed") }
            guard witness.preimage == nil || leaf.kind == .hashlock else {
                throw CashuError.spendingConditionError("preimage on a non-hashlock leaf")
            }
            if leaf.kind == .after, let time = leaf.time, now < time {
                throw CashuError.spendingConditionError("leaf locktime not reached")
            }
            if leaf.kind == .hashlock {
                guard let preimage = try witness.preimage?.bytes, preimage.count == 32,
                      String(bytes: TLV.sha256(preimage)) == leaf.hash else {
                    throw CashuError.spendingConditionError("hashlock preimage missing or wrong")
                }
            }
            guard witness.signatures.count <= leaf.keys.count else {
                throw CashuError.spendingConditionError("more signatures than listed keys")
            }
            var satisfied = Set<String>()
            for signature in witness.signatures {
                guard (try? signature.bytes)?.count == 64 else { throw CashuError.spendingConditionError("malformed signature") }
                for key in leaf.keys where !satisfied.contains(key) {
                    if Crypto.schnorrVerify(digest: inputDigest, signatureHex: signature, publicKey: try key.bytes) {
                        satisfied.insert(key)
                        break
                    }
                }
            }
            guard satisfied.count >= (leaf.n ?? Int.max) else {
                throw CashuError.spendingConditionError("threshold not met")
            }
        }

        // MARK: - Receiver-keyed outputs (NUT-18 nutroot / NUT-28 slot map)

        struct LockedOutput {
            let output: CashuSwift.Output
            let blindingFactor: String
            let secret: String
            let spendInfo: SpendInfo
        }

        /// Builds one receiver-keyed output per amount for `option`: a fresh ephemeral per output,
        /// the static key blinded at slot 0 (or `H + u·G` for a NUMS request), the requested leaves
        /// reproduced byte for byte with blind-me keys substituted at slots `1..`, and the tweaked
        /// secret `P = K + t·G`.
        static func receiverKeyedOutputs(amounts: [Int],
                                         keysetID: String,
                                         option: NutrootOption) throws -> [LockedOutput] {
            try option.validate()
            let staticKey = try Crypto.nut20PublicKey(option.k)
            let isNums = option.k == numsPoint
            let blindMe = Set(option.b ?? [])
            let requested = try (option.l ?? []).map { try Leaf.parse(hex: $0) }
            guard !isNums || !requested.isEmpty else {
                throw CashuError.paymentRequestValidation("a NUMS nutroot request needs leaves")
            }

            return try amounts.map { amount in
                let needsEphemeral = !isNums || !blindMe.isEmpty
                let e = needsEphemeral ? try PrivateKey() : nil

                let internalKey: PublicKey
                var u: String?
                if isNums {
                    let offset = try PrivateKey()
                    u = String(bytes: offset.dataRepresentation)
                    internalKey = try numsInternalKey(offset: offset)
                } else {
                    internalKey = try Crypto.P2BK.blind(staticKey, ephemeral: e!, slot: 0)
                }

                var slot = 1
                var tree = [String]()
                for leaf in requested {
                    let keys = try leaf.keys.map { key -> String in
                        guard slot <= 255 else { throw CashuError.paymentRequestValidation("more than 255 leaf keys") }
                        defer { slot += 1 }
                        guard blindMe.contains(key) else { return key }
                        return String(bytes: try Crypto.P2BK.blind(try Crypto.nut20PublicKey(key), ephemeral: e!, slot: UInt8(slot)).dataRepresentation)
                    }
                    tree.append(try Leaf(kind: leaf.kind, n: leaf.n, keys: keys, time: leaf.time, hash: leaf.hash).serializedHex())
                }

                let leaves: [[UInt8]]? = tree.isEmpty ? nil : try tree.map { try $0.bytes }
                let secret = try self.secret(internalKey: internalKey, leaves: leaves)
                let r = try Crypto.BLS.randomScalar()
                let B_ = Crypto.BLS.blind(secretBytes: Array(secret.dataRepresentation), r: r)
                let info = SpendInfo(E: e.map { String(bytes: $0.publicKey.dataRepresentation) },
                                     K: tree.isEmpty ? nil : String(bytes: internalKey.dataRepresentation),
                                     tree: tree.isEmpty ? nil : tree,
                                     u: u)
                return LockedOutput(output: CashuSwift.Output(amount: amount, B_: String(bytes: B_.compressedBytes), id: keysetID),
                                    blindingFactor: String(bytes: r.bytes),
                                    secret: String(bytes: secret.dataRepresentation),
                                    spendInfo: info)
            }
        }
    }
}
