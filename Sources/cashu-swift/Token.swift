//
//  File.swift
//  CashuSwift
//
//  Created by zm on 29.11.24.
//

import Foundation


extension CashuSwift {
    
    ///General purpose struct for storing version agnostic token information
    ///that can be transformed into `TokenV3` or `TokenV4` for serialization.
    public struct Token: Codable, Equatable {
        
        ///Unit string like "sat". "eur" or "usd"
        public let unit: String
        
        ///Optional memo for the recipient
        public let memo: String?
        
        ///Dictionary containing the mint URL absolute string as key and a list of `ProofRepresenting` as the proofs for this token.
        public let proofsByMint: Dictionary<String, [any ProofRepresenting]>
        
        public func serialize(to version: CashuSwift.TokenVersion = .V3) throws -> String {
            switch version {
            case .V3:
                return try self.makeV3().serialize()
            case .V4:
                return try self.makeV4().serialize()
            }
        }
        
        init(proofs: [String: [any ProofRepresenting]],
             unit: String,
             memo: String? = nil) {
            self.proofsByMint = proofs
            self.unit = unit
            self.memo = memo
        }
        
        init(token:TokenV3) throws {
            self.memo = token.memo
            self.unit = token.unit ?? "sat" // FIXME: technically not ideal, there might be non-sat V3 tokens
            self.proofsByMint = Dictionary(uniqueKeysWithValues: token.token.map { ($0.mint, $0.proofs) })
        }
        
        init(token:TokenV4) throws {
            self.memo = token.memo
            self.unit = token.unit
            
            var proofsPerMint = [String: [any ProofRepresenting]]()
            var ps = [any ProofRepresenting]()
            
            for entry in token.tokens {
                ps.append(contentsOf: entry.proofs.map({ p in
                    Proof(keysetID: String(bytes: entry.keysetID),
                          amount: p.amount,
                          secret: p.secret,
                          C: String(bytes: p.signature))
                    // TODO: needs to take DLEQ data into account
                }))
            }
            
            proofsPerMint[token.mint] = ps
            
            self.proofsByMint = proofsPerMint
        }
        
        private func makeV3() throws -> TokenV3 {
            
            let proofsContainers = proofsByMint.map { (mintURLString, proofList) in
                ProofContainer(mint: mintURLString,
                               proofs: proofList.map({ p in
                    Proof(keysetID: p.keysetID,
                          amount: p.amount,
                          secret: p.secret,
                          C: p.C)
                }))
            }
            
            return TokenV3(token: proofsContainers,
                           memo: self.memo,
                           unit: self.unit)
            
        }
        
        private func makeV4() throws -> TokenV4 {
            guard proofsByMint.count < 2 else {
                throw CashuError.tokenEncoding
            }
            
            guard let (mintURLstring, proofList) = proofsByMint.first else {
                throw CashuError.tokenEncoding
            }
            
            let byKeysetID = Dictionary(grouping: proofList, by: { $0.keysetID })
            
            let tokenEntries = try byKeysetID.map { (id, ps) in
                TokenV4.TokenEntry(keysetID: Data(try id.bytes),
                                   proofs: try ps.map({ p in
                    TokenV4.TokenEntry.Proof(amount: p.amount,
                                             secret: p.secret,
                                             signature: Data(try p.C.bytes),
                                             dleqProof: nil,
                                             witness: nil)
                }))
            }
            
            return TokenV4(mint: mintURLstring,
                           unit: self.unit,
                           memo: self.memo,
                           tokens: tokenEntries)
        }
    }
}

extension CashuSwift.Token {
    private enum CodingKeys: String, CodingKey {
        case unit
        case memo
        case proofsByMint
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.unit = try container.decode(String.self, forKey: .unit)
        self.memo = try container.decodeIfPresent(String.self, forKey: .memo)
        
        // Decode as concrete Proof type, which conforms to ProofRepresenting
        let proofs = try container.decode([String: [CashuSwift.Proof]].self, forKey: .proofsByMint)
        self.proofsByMint = proofs.mapValues { $0 } // Type erasure happens here
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(unit, forKey: .unit)
        try container.encodeIfPresent(memo, forKey: .memo)
        
        // Cast dictionary values to concrete Proof type for encoding
        let concreteProofs = proofsByMint.mapValues { proofs in
            proofs.compactMap { $0 as? CashuSwift.Proof }
        }
        try container.encode(concreteProofs, forKey: .proofsByMint)
    }
}

extension CashuSwift.Token {
    public static func == (lhs: CashuSwift.Token, rhs: CashuSwift.Token) -> Bool {
        guard lhs.unit == rhs.unit,
              lhs.memo == rhs.memo,
              lhs.proofsByMint.keys == rhs.proofsByMint.keys else {
            return false
        }
        
        for (mint, lhsProofs) in lhs.proofsByMint {
            guard let rhsProofs = rhs.proofsByMint[mint],
                  lhsProofs.count == rhsProofs.count else {
                return false
            }
            
            for (lp, rp) in zip(lhsProofs, rhsProofs) {
                guard lp.keysetID == rp.keysetID,
                      lp.amount == rp.amount,
                      lp.secret == rp.secret,
                      lp.C == rp.C else {
                    return false
                }
            }
        }
        
        return true
    }
}

extension String {
    
    public func deserializeToken() throws -> CashuSwift.Token {
        
        if self.hasPrefix("cashuA") {
            return try CashuSwift.Token(token: CashuSwift.TokenV3(tokenString: self))
            
        } else if self.hasPrefix("cashuB") {
            return try CashuSwift.Token(token: CashuSwift.TokenV4(tokenString: self))
            
        } else {
            throw CashuError.tokenDecoding("Token string does not start with 'cashuA' or 'cashuB'")
        }
    }
    
}
