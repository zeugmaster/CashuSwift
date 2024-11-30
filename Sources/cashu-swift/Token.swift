//
//  File.swift
//  CashuSwift
//
//  Created by zm on 29.11.24.
//

import Foundation


extension CashuSwift {
    
    ///General purpose struct for storing version agnostic token information that can be transformed into `TokenV3` or `TokenV4` for serialization.
    public struct Token {
        ///Unit string like "sat". "eur" or "usd"
        public let unit: String
        
        ///Optional memo for the recipient
        public let memo: String?
        
        ///Dictionary containing the mint URL absolute string as key and a list of `ProofRepresenting` as the proofs for this token.
        public let proofs: Dictionary<String, [ProofRepresenting]>
        
        public func serialize(to version: CashuSwift.TokenVersion = .V3) throws -> String {
            switch version {
            case .V3:
                return try self.makeV3().serialize()
            case .V4:
                return try self.makeV4().serialize()
            }
        }
        
        init(proofs: [String: [ProofRepresenting]],
             unit: String,
             memo: String? = nil) {
            self.proofs = proofs
            self.unit = unit
            self.memo = memo
        }
        
        init(token:TokenV3) throws {
            self.memo = token.memo
            self.unit = token.unit ?? "sat" // technically not ideal, there might be non-sat V3 tokens
            self.proofs = Dictionary(uniqueKeysWithValues: token.token.map { ($0.mint, $0.proofs) })
        }
        
        init(token:TokenV4) throws {
            self.memo = token.memo
            self.unit = token.unit
            
            var proofsPerMint = [String: [ProofRepresenting]]()
            var ps = [ProofRepresenting]()
            
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
            
            self.proofs = proofsPerMint
        }
        
        private func makeV3() throws -> TokenV3 {
            
            let proofsContainers = proofs.map { (mintURLString, proofList) in
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
            guard proofs.count < 2 else {
                throw CashuError.tokenEncoding
            }
            
            guard let (mintURLstring, proofList) = proofs.first else {
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
