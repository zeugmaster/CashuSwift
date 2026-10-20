//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

extension CashuSwift {
    /// Represents a Cashu proof (ecash token).
    public struct Proof: Codable, Equatable, CustomStringConvertible, Identifiable, ProofRepresenting, Sendable {
        
        /// Unique identifier derived from the C value.
        public var id:String { get { C } }
        
        public static func == (lhs: Proof, rhs: Proof) -> Bool {
            lhs.C == rhs.C &&
            lhs.keysetID == rhs.keysetID &&
            lhs.amount == rhs.amount
        }
        
        public enum CodingKeys: String, CodingKey {
            case keysetID = "id", amount, secret, C, dleq, witness
            case spendInfo = "spend_info"
        }
        
        /// The keyset ID this proof belongs to.
        public let keysetID: String
        
        /// The amount value of this proof.
        public let amount: Int
        
        /// The secret used to generate this proof.
        public let secret: String
        
        /// The blinded signature from the mint.
        public let C: String
        
        /// Optional DLEQ proof for signature verification.
        public let dleq: DLEQ?
        
        /// Optional witness data for spending conditions.
        public var witness: String?
        
        /// NUT-00 spend info of a v3 proof (bearer key, ephemeral, internal key, tree, NUMS offset).
        public var spendInfo: SpendInfo?
        
        public var description: String {
            return "C: ...\(C.suffix(6)), amount: \(amount)"
        }
        
        /// Creates a proof from a ProofRepresenting protocol conformer.
        /// - Parameter proofRepresentation: The proof representation to copy from
        public init(_ proofRepresentation:ProofRepresenting) {
            self.keysetID = proofRepresentation.keysetID
            self.C = proofRepresentation.C
            self.amount = proofRepresentation.amount
            self.secret = proofRepresentation.secret
            self.dleq = proofRepresentation.dleq
            self.spendInfo = proofRepresentation.spendInfo
            
            self.witness = nil
        }
        
        /// Creates a new proof instance.
        /// - Parameters:
        ///   - keysetID: The keyset ID this proof belongs to
        ///   - amount: The amount value of this proof
        ///   - secret: The secret used to generate this proof
        ///   - C: The blinded signature from the mint
        ///   - dleq: Optional DLEQ proof for signature verification
        ///   - witness: Optional witness data for spending conditions
        ///   - spendInfo: Optional NUT-00 spend info (v3 proofs)
        public init(keysetID:String,
                    amount:Int,
                    secret:String,
                    C:String,
                    dleq: DLEQ? = nil,
                    witness: String? = nil,
                    spendInfo: SpendInfo? = nil) {
            self.keysetID = keysetID
            self.amount = amount
            self.secret = secret
            self.C = C
            self.dleq = dleq
            self.witness = witness
            self.spendInfo = spendInfo
        }
        
        // MARK: - Additional nested types
        /// Represents the state of a proof on the mint.
        public enum ProofState: String, Codable, Sendable {
            /// The proof has not been spent.
            case unspent = "UNSPENT"
            /// The proof is pending (in-flight).
            case pending = "PENDING"
            /// The proof has been spent.
            case spent = "SPENT"
        }
        
        struct ProofStateListEntry: Codable {
            let Y: String
            let state: ProofState
            let witness: String?
            /// NUT-07: the input digest a v3 witness signs, present with the witness.
            let inputDigest: String?

            enum CodingKeys: String, CodingKey {
                case Y, state, witness
                case inputDigest = "input_digest"
            }
        }
        
        struct StateCheckRequest: Codable {
            let Ys: [String]
        }
        
        /// Response from checking proof states.
        public struct StateCheckResponse: Codable {
            let states: [ProofStateListEntry]
        }
        
        /// Witness data: NUT-11 signatures, a v3 key-path signature, or a NUT-10 script-path
        /// reveal (`leaf`, `control`, `signatures`, optional `preimage`).
        public struct Witness: Codable, Sendable, Equatable {
            public var signatures: [String]
            public var leaf: String?
            public var control: Control?
            public var preimage: String?

            public struct Control: Codable, Sendable, Equatable {
                public let K: String
                public let path: [String]
                public init(K: String, path: [String]) {
                    self.K = K
                    self.path = path
                }
            }

            public init(signatures: [String], leaf: String? = nil, control: Control? = nil, preimage: String? = nil) {
                self.signatures = signatures
                self.leaf = leaf
                self.control = control
                self.preimage = preimage
            }

            /// Parses a serialized witness JSON string.
            public init(json: String) throws {
                self = try JSONDecoder().decode(Witness.self, from: Data(json.utf8))
            }
            
            func stringJSON() throws -> String {
                let data = try JSONEncoder().encode(self)
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
    }
}


