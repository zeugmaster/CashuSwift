//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation

extension CashuSwift {
    open class Proof: Codable, Equatable, CustomStringConvertible, Identifiable, ProofRepresenting {        
        
        public var id:String { get { C } }
        
        public static func == (lhs: Proof, rhs: Proof) -> Bool {
            lhs.C == rhs.C &&
            lhs.keysetID == rhs.keysetID &&
            lhs.amount == rhs.amount
        }
        
        public enum CodingKeys: String, CodingKey {
            case keysetID = "id", amount, secret, C
        }
        
        public let keysetID: String
        public let amount: Int
        public let secret: String
        public let C: String
        
        public var description: String {
            return "C: ...\(C.suffix(6)), amount: \(amount)"
        }
        
        public init(_ proofRepresentation:ProofRepresenting) {
            self.keysetID = proofRepresentation.keysetID
            self.C = proofRepresentation.C
            self.amount = proofRepresentation.amount
            self.secret = proofRepresentation.secret
        }
        
        // MARK: - Codable Implementation
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(keysetID, forKey: .keysetID)
            try container.encode(amount, forKey: .amount)
            try container.encode(secret, forKey: .secret)
            try container.encode(C, forKey: .C)
        }
        
        required public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            keysetID = try container.decode(String.self, forKey: .keysetID)
            amount = try container.decode(Int.self, forKey: .amount)
            secret = try container.decode(String.self, forKey: .secret)
            C = try container.decode(String.self, forKey: .C)
        }
        
        init(keysetID:String, amount:Int, secret:String, C:String) {
            self.keysetID = keysetID
            self.amount = amount
            self.secret = secret
            self.C = C
        }
        
        // MARK: - Additional nested types
        
        public enum ProofState: String, Codable {
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
    }

}
