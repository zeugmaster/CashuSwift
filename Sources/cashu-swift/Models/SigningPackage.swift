//
//  SigningPackage.swift
//  CashuSwift
//
//  NUT-XX signing packages (nuts #464): one or more script-path spends awaiting signatures,
//  passed between wallets as `nutspA` + base64url(JSON, no padding). A signer checks that
//  each spend's leaf commits to its secret and that the secret belongs to the named input,
//  then appends BIP-340 signatures by the leaf keys it holds over that input's digest.
//

import Foundation
import secp256k1

extension CashuSwift {
    /// Experimental wallet-to-wallet format following the draft NUT signing-package proposal.
    public struct SigningPackage: Codable, Equatable, Sendable {
        public static let prefix = "nutspA"

        public struct Spend: Codable, Equatable, Sendable {
            /// Index of the input's container in the transcript (among inputs).
            public var input: Int
            /// The point the input spends: a v3 proof's secret or a mint quote's lock key.
            public var secret: String
            public var leaf: String
            public var control: Proof.Witness.Control
            /// Ephemeral of a receiver-keyed input (NUT-28).
            public var E: String?
            /// NUT-28 slot hints for the leaf keys; a signer that matches no slot scans.
            public var slots: [Int]?
            public var signatures: [String]

            public init(input: Int, secret: String, leaf: String, control: Proof.Witness.Control,
                        E: String? = nil, slots: [Int]? = nil, signatures: [String] = []) {
                self.input = input
                self.secret = secret
                self.leaf = leaf
                self.control = control
                self.E = E
                self.slots = slots
                self.signatures = signatures
            }
        }

        public var version: String
        public var transcript: String
        public var spends: [Spend]

        public init(transcript: String, spends: [Spend]) {
            self.version = SigningPackage.prefix
            self.transcript = transcript
            self.spends = spends
        }

        /// Builds a package for `transaction`, one spend per `(inputIndex, leafIndex)`, from the
        /// proofs' spend info.
        public init(transaction: Transaction, spends: [(inputIndex: Int, leafIndex: Int)]) throws {
            self.version = SigningPackage.prefix
            self.transcript = String(bytes: try transaction.transcript())
            self.spends = try spends.map { spend in
                guard transaction.inputs.indices.contains(spend.inputIndex),
                      case .proof(let proof) = transaction.inputs[spend.inputIndex],
                      let info = proof.spendInfo, let tree = info.tree, tree.indices.contains(spend.leafIndex) else {
                    throw CashuError.spendingConditionError("input has no disclosed tree to spend through")
                }
                let K = try info.K ?? Nutroot.resolve(proof).internalKey.dataRepresentation.hexEncodedString()
                return Spend(input: spend.inputIndex,
                             secret: proof.secret,
                             leaf: tree[spend.leafIndex],
                             control: .init(K: K, path: try Nutroot.merklePath(leaves: tree, index: spend.leafIndex)),
                             E: info.E)
            }
            let records = try inputs()
            for i in self.spends.indices {
                let record = try Transaction.container(transaction.inputs[self.spends[i].input])
                guard let index = records.firstIndex(where: { $0.record == record }) else {
                    throw CashuError.inputError("input is absent from transcript")
                }
                self.spends[i].input = index
            }
            try validate()
        }

        /// Extracts the script path of a locked mint quote (NUT-04), using its disclosed tree.
        public init(transaction: Transaction, mintQuoteInput: Int, internalKey: String, tree: [String], leafIndex: Int) throws {
            guard transaction.inputs.indices.contains(mintQuoteInput), tree.indices.contains(leafIndex),
                  case .mintQuote(_, _, let lockKey, _) = transaction.inputs[mintQuoteInput] else {
                throw CashuError.inputError("invalid mint quote script-path plan")
            }
            self.init(transcript: String(bytes: try transaction.transcript()), spends: [])
            let record = try Transaction.container(transaction.inputs[mintQuoteInput])
            guard let input = try inputs().firstIndex(where: { $0.record == record }) else {
                throw CashuError.inputError("quote is absent from transcript")
            }
            spends = [Spend(input: input, secret: lockKey, leaf: tree[leafIndex],
                            control: .init(K: internalKey, path: try Nutroot.merklePath(leaves: tree, index: leafIndex)))]
            try validate()
        }

        // MARK: - Codec

        public func serialize() throws -> String {
            try validate()
            let json = try JSONEncoder().encode(self)
            return SigningPackage.prefix + json.base64URLsafe.replacingOccurrences(of: "=", with: "")
        }

        public init(serialized: String) throws {
            guard serialized.hasPrefix(SigningPackage.prefix),
                  let data = String(serialized.dropFirst(SigningPackage.prefix.count)).decodeBase64UrlSafe() else {
                throw CashuError.tokenDecoding("not a nutspA signing package")
            }
            self = try JSONDecoder().decode(SigningPackage.self, from: data)
            try validate()
        }

        /// Also validates packages constructed or decoded through Codable directly.
        public func validate() throws {
            guard version == SigningPackage.prefix, !spends.isEmpty,
                  Set(spends.map(\.input)).count == spends.count else {
                throw CashuError.tokenDecoding("invalid signing package version, empty spends, or repeated input")
            }
            for spend in spends {
                let (leaf, _) = try verify(spend)
                if let slots = spend.slots {
                    guard slots.count == leaf.keys.count, slots.allSatisfy({ (1...255).contains($0) }) else {
                        throw CashuError.inputError("invalid signing package slot hints")
                    }
                }
                if let E = spend.E { _ = try Crypto.nut20PublicKey(E) }
                guard spend.signatures.allSatisfy({ (try? $0.bytes.count) == 64 }) else {
                    throw CashuError.inputError("malformed signing package signature")
                }
            }
        }

        // MARK: - Transcript view

        /// The input containers of the transcript, in order, with their raw record bytes.
        public struct ParsedInput: Equatable, Sendable {
            public let type: UInt8
            public let amount: UInt64
            /// Proof input: `Y`; mint quote input: the lock key.
            public let point: [UInt8]
            public let record: [UInt8]
        }

        public func inputs() throws -> [ParsedInput] {
            var inputs = [ParsedInput]()
            var lastType: UInt8 = 0
            var hasOutput = false
            for record in try TLV.records(try transcript.bytes) {
                guard record.type >= lastType, !record.value.isEmpty else {
                    throw CashuError.inputError("invalid transcript container order or empty container")
                }
                lastType = record.type
                switch record.type {
                case 0x11, 0x12:
                    var amount: UInt64?
                    var point: [UInt8]?
                    var last: UInt8 = 0
                    for field in try TLV.records(record.value) {
                        guard field.type > last else { throw CashuError.inputError("transcript fields not ascending") }
                        last = field.type
                        switch field.type {
                        case 0x01: amount = try TLV.integer(field.value)
                        case 0x03: point = field.value
                        case 0x04 where record.type == 0x12: _ = try TLV.integer(field.value)
                        default: break
                        }
                    }
                    guard let amount, let point else { throw CashuError.inputError("malformed input container") }
                    inputs.append(ParsedInput(type: record.type, amount: amount, point: point, record: record.raw))
                case 0x21, 0x22:
                    hasOutput = true
                default:
                    throw CashuError.inputError("unknown transcript container")
                }
            }
            guard !inputs.isEmpty, hasOutput else { throw CashuError.inputError("transaction needs inputs and outputs") }
            return inputs
        }

        public func transactionDigest() throws -> [UInt8] {
            TLV.sha256(try transcript.bytes)
        }

        public func inputDigest(_ index: Int) throws -> [UInt8] {
            let parsed = try inputs()
            guard parsed.indices.contains(index) else { throw CashuError.inputError("spend input index out of range") }
            return Transaction.inputDigest(transactionDigest: try transactionDigest(), container: parsed[index].record)
        }

        // MARK: - Signer

        /// Checks `spend` (leaf commits to the secret through control; secret belongs to its
        /// input) and returns its leaf and input digest.
        func verify(_ spend: Spend) throws -> (leaf: Nutroot.Leaf, digest: [UInt8]) {
            let parsed = try inputs()
            guard parsed.indices.contains(spend.input) else { throw CashuError.inputError("spend input index out of range") }
            let input = parsed[spend.input]
            let secretBytes = try Crypto.v3SecretBytes(spend.secret)
            switch input.type {
            case 0x11:
                guard Crypto.BLS.hashToCurveG1(secretBytes).compressedBytes == input.point else {
                    throw CashuError.spendingConditionError("spend secret does not hash to the input's Y")
                }
            default:
                guard secretBytes == input.point else {
                    throw CashuError.spendingConditionError("spend secret is not the quote's lock key")
                }
            }
            let K = try Crypto.nut20PublicKey(spend.control.K)
            let root = try Nutroot.rootFrom(leaf: try spend.leaf.bytes, path: try spend.control.path.map { try $0.bytes })
            let committed = try Nutroot.add(K, tweak: Nutroot.tweak(internalKey: Array(K.dataRepresentation), root: root))
            guard Array(committed.dataRepresentation) == secretBytes else {
                throw CashuError.spendingConditionError("leaf does not commit to the spend secret")
            }
            let leaf = try Nutroot.Leaf.parse(hex: spend.leaf)
            guard leaf.kind != .commit else { throw CashuError.spendingConditionError("commit leaf cannot be spent") }
            return (leaf, Transaction.inputDigest(transactionDigest: try transactionDigest(), container: input.record))
        }

        /// Appends signatures by every `keys` entry (or, for receiver-keyed spends, the slot key it
        /// derives from `E`) that a spend's leaf lists. Returns the updated package.
        public func signed(with keys: [secp256k1.Schnorr.PrivateKey]) throws -> SigningPackage {
            try validate()
            var package = self
            for (i, spend) in spends.enumerated() {
                let (leaf, digest) = try verify(spend)
                let ephemeral = try spend.E.map { try Crypto.nut20PublicKey($0) }
                for key in keys {
                    let candidates = try signingCandidates(for: key, leaf: leaf, ephemeral: ephemeral, slots: spend.slots)
                    for candidate in candidates where leaf.keys.contains(String(bytes: candidate.publicKey.dataRepresentation)) {
                        let signature = try Crypto.schnorrSign(digest: digest, key: candidate)
                        if !package.spends[i].signatures.contains(signature) {
                            package.spends[i].signatures.append(signature)
                        }
                    }
                }
            }
            return package
        }

        private func signingCandidates(for key: secp256k1.Schnorr.PrivateKey,
                                       leaf: Nutroot.Leaf,
                                       ephemeral: Crypto.PublicKey?, slots: [Int]?) throws -> [secp256k1.Schnorr.PrivateKey] {
            var out = [key]
            guard let ephemeral else { return out }
            let staticKey = try Crypto.PrivateKey(dataRepresentation: key.dataRepresentation)
            for (offset, blinded) in leaf.keys.enumerated() {
                let point = try Crypto.nut20PublicKey(blinded)
                // Slot numbers belong to the whole tree, which the co-signer may not have.
                let hint = slots.map { $0[offset] }
                let candidates = hint.map { [$0] } ?? []
                for slot in candidates + (1...255).filter({ $0 != hint }) {
                    if let derived = try Crypto.P2BK.unblind(point, receiverKey: staticKey, ephemeral: ephemeral, slot: UInt8(slot)) {
                        out.append(try secp256k1.Schnorr.PrivateKey(dataRepresentation: derived.dataRepresentation))
                        break
                    }
                }
            }
            return out
        }

        // MARK: - Merge

        /// The script-path witness for `spend`, with `preimage` for a hashlock leaf. Verifies the
        /// collected signatures satisfy the leaf first.
        public func witness(for spendIndex: Int, preimage: String? = nil) throws -> Proof.Witness {
            try validate()
            guard spends.indices.contains(spendIndex) else { throw CashuError.inputError("spend index out of range") }
            let spend = spends[spendIndex]
            let (_, digest) = try verify(spend)
            let witness = Proof.Witness(signatures: spend.signatures,
                                        leaf: spend.leaf,
                                        control: spend.control,
                                        preimage: preimage)
            try Nutroot.verifyScriptPath(witness, secret: spend.secret, inputDigest: digest)
            return witness
        }

        /// Sets the witnesses of this package on `proofs` (the transaction's proof inputs, in
        /// order), after checking the package's transcript is the transaction's.
        public func merge(into proofs: [Proof], transaction: Transaction, preimages: [Int: String] = [:]) throws -> [Proof] {
            try validate()
            guard String(bytes: try transaction.transcript()) == transcript else {
                throw CashuError.spendingConditionError("signing package transcript differs from the transaction")
            }
            var merged = proofs
            let parsed = try inputs()
            let proofRecords = try proofs.map { try Transaction.container(.proof($0)) }
            for (i, spend) in spends.enumerated() {
                guard parsed[spend.input].type == 0x11,
                      let index = proofRecords.firstIndex(of: parsed[spend.input].record) else {
                    throw CashuError.inputError("package input does not match a supplied proof")
                }
                merged[index].witness = try witness(for: i, preimage: preimages[i]).stringJSON()
            }
            return merged
        }
    }
}
