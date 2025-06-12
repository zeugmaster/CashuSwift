//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

extension CashuSwift {
    public struct Proof: Codable, Equatable, CustomStringConvertible, Identifiable, ProofRepresenting, Sendable {
        
        public var id:String { get { C } }
        
        public static func == (lhs: Proof, rhs: Proof) -> Bool {
            lhs.C == rhs.C &&
            lhs.keysetID == rhs.keysetID &&
            lhs.amount == rhs.amount
        }
        
        public enum CodingKeys: String, CodingKey {
            case keysetID = "id", amount, secret, C, dleq, witness
        }
        
        public let keysetID: String
        public let amount: Int
        public let secret: String
        public let C: String
        public let dleq: DLEQ?
        
        public var witness: String?
        
        public var description: String {
            return "C: ...\(C.suffix(6)), amount: \(amount)"
        }
        
        public init(_ proofRepresentation:ProofRepresenting) {
            self.keysetID = proofRepresentation.keysetID
            self.C = proofRepresentation.C
            self.amount = proofRepresentation.amount
            self.secret = proofRepresentation.secret
            self.dleq = proofRepresentation.dleq
            
            self.witness = nil
        }
        
        // TODO: remove default for dleq
        public init(keysetID:String, amount:Int, secret:String, C:String, dleq: DLEQ? = nil, witness: String? = nil) {
            self.keysetID = keysetID
            self.amount = amount
            self.secret = secret
            self.C = C
            self.dleq = dleq
            self.witness = witness
        }
        
        // MARK: - Additional nested types
        public enum ProofState: String, Codable, Sendable {
            case unspent = "UNSPENT"
            case pending = "PENDING"
            case spent = "SPENT"
        }
        
        struct ProofStateListEntry: Codable {
            let Y: String
            let state: ProofState
            let witness: String?
        }
        
        struct StateCheckRequest: Codable {
            let Ys: [String]
        }
        
        public struct StateCheckResponse: Codable {
            let states: [ProofStateListEntry]
        }
        
        public struct Witness: Codable, Sendable {
            let signatures: [String]
            
            func stringJSON() throws -> String {
                let data = try JSONEncoder().encode(self)
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
    }
}


