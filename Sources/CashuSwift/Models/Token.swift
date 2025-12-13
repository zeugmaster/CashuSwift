//
//  File.swift
//  CashuSwift
//
//  Created by zm on 29.11.24.
//

import Foundation
import secp256k1


extension CashuSwift {
    
    /// General purpose struct for storing version agnostic token information.
    ///
    /// This struct can be transformed into `TokenV3` or `TokenV4` for serialization.
    public struct Token: Codable, Equatable, Sendable {
        
        /// Unit string like "sat", "eur" or "usd".
        public let unit: String
        
        /// Optional memo for the recipient.
        public let memo: String?
        
        /// Dictionary containing the mint URL absolute string as key and a list of `Proof` as the proofs for this token.
        public let proofsByMint: Dictionary<String, [Proof]>
        
        /// Returns true if any of the token's proofs contain a P2PK spending condition.
        public var isP2PKLocked: Bool {
            for proofs in proofsByMint.values {
                for proof in proofs {
                    if let spendingCondition = SpendingCondition.deserialize(from: proof.secret),
                       spendingCondition.kind == .P2PK {
                        return true
                    }
                }
            }
            return false
        }
        
        /// Returns an array of public keys (as hex strings) that the token is locked to, or nil if not P2PK locked.
        public var p2pkLockedPublicKeys: [String]? {
            var publicKeys = [String]()
            
            for proofs in proofsByMint.values {
                for proof in proofs {
                    if let spendingCondition = SpendingCondition.deserialize(from: proof.secret),
                       spendingCondition.kind == .P2PK {
                        // Add the main public key from payload data
                        publicKeys.append(spendingCondition.payload.data)
                        
                        // Add any additional public keys from tags
                        if let tags = spendingCondition.payload.tags {
                            for tag in tags {
                                if case .pubkeys(let keys) = tag {
                                    publicKeys.append(contentsOf: keys)
                                }
                            }
                        }
                    }
                }
            }
            
            return publicKeys.isEmpty ? nil : Array(Set(publicKeys))
        }
        
        /// Serializes the token to a string representation.
        /// - Parameter version: The token version to use for serialization
        /// - Returns: The serialized token string
        /// - Throws: An error if serialization fails
        public func serialize(to version: CashuSwift.TokenVersion = .V3) throws -> String {
            switch version {
            case .V3:
                return try self.makeV3().serialize()
            case .V4:
                return try self.makeV4().serialize()
            }
        }
        
        /// Creates a new token instance.
        /// - Parameters:
        ///   - proofs: Dictionary mapping mint URLs to proof arrays
        ///   - unit: The unit of the token (e.g., "sat", "eur", "usd")
        ///   - memo: Optional memo for the recipient
        public init(proofs: [String: [any ProofRepresenting]],
                    unit: String,
                    memo: String? = nil) {
            self.proofsByMint = proofs.mapValues { proofArray in
                proofArray.map { proofRepresenting in
                    Proof(proofRepresenting)
                }
            }
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
            
            var proofsPerMint = [String: [Proof]]()
            var ps = [Proof]()
            
            for entry in token.tokens {
                
                ps.append(contentsOf: entry.proofs.map({ p in
                    
                    let dleq: CashuSwift.DLEQ?
                    if let dleqFields = p.dleqProof {
                        dleq = CashuSwift.DLEQ(e: String(bytes: dleqFields.e),
                                               s: String(bytes: dleqFields.s),
                                               r: String(bytes: dleqFields.r))
                    } else {
                        dleq = nil
                    }
                    
                    return Proof(keysetID: String(bytes: entry.keysetID),
                                 amount: p.amount,
                                 secret: p.secret,
                                 C: String(bytes: p.signature),
                                 dleq: dleq)
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
                throw CashuError.tokenEncoding("Token object contains proofs from more than one mint which can not be encoded into a V4 token.")
            }
            
            guard let (mintURLstring, proofList) = proofsByMint.first else {
                throw CashuError.tokenEncoding("Token object seems to contain no proofs. This is not valid for encoding.")
            }
            
            let byKeysetID = Dictionary(grouping: proofList, by: { $0.keysetID })
            
            guard !byKeysetID.keys.contains(where: { keysetID in
                keysetID.count == 12
            }) else {
                throw CashuError.tokenEncoding("Token data seems to contain a non-hex keyset ID, which is not suported in Token V4 CBOR encoding.")
            }
            
            let tokenEntries = try byKeysetID.map { (id, ps) in
                TokenV4.TokenEntry(keysetID: Data(try id.bytes),
                                   proofs: try ps.map({ p in
                    
                    let dleq: TokenV4.TokenEntry.Proof.DLEQProof?
                    if let data = p.dleq,
                       let r = data.r,
                       let eBytes = try? data.e.bytes,
                       let sBytes = try? data.s.bytes,
                       let rBytes = try? r.bytes {
                        dleq = TokenV4.TokenEntry.Proof.DLEQProof(e: Data(eBytes),
                                                                  s: Data(sBytes),
                                                                  r: Data(rBytes))
                    } else {
                        dleq = nil
                    }
                    
                    return TokenV4.TokenEntry.Proof(amount: p.amount,
                                                    secret: p.secret,
                                                    signature: Data(try p.C.bytes),
                                                    dleqProof: dleq,
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
            proofs.compactMap { $0 }
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

// MARK: - NUT-18 Payment Request Support

extension CashuSwift.Token {
    /// Checks if this token satisfies a payment request.
    /// - Parameter request: The payment request to check against
    /// - Returns: True if the token satisfies all requirements of the payment request
    public func satisfies(_ request: CashuSwift.PaymentRequest) -> Bool {
        // Check unit
        if let requestUnit = request.unit, requestUnit != self.unit {
            return false
        }
        
        // Check amount
        if let requestAmount = request.amount {
            let totalAmount = proofsByMint.values.flatMap { $0 }.reduce(0) { $0 + $1.amount }
            if totalAmount != requestAmount {
                return false
            }
        }
        
        // Check mint (token must be from a single mint, and it must be accepted)
        guard proofsByMint.count == 1 else { return false }
        guard let mintURL = proofsByMint.keys.first else { return false }
        
        if let acceptedMints = request.mints, !acceptedMints.contains(mintURL) {
            return false
        }
        
        // Check locking conditions
        if let lockingCondition = request.lockingCondition {
            guard let proofs = proofsByMint.first?.value else { return false }
            
            for proof in proofs {
                guard let spendingCondition = CashuSwift.SpendingCondition.deserialize(from: proof.secret) else {
                    return false
                }
                
                // Check kind and data match
                if spendingCondition.kind.rawValue != lockingCondition.kind || spendingCondition.payload.data != lockingCondition.data {
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Calculates the total amount of all proofs in the token.
    /// - Returns: The sum of all proof amounts
    public func totalAmount() -> Int {
        return proofsByMint.values.flatMap { $0 }.reduce(0) { $0 + $1.amount }
    }
}

extension String {
    
    var urlSafe: String {
        get {
            self.replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
    }

    func encodeBase64UrlSafe(removePadding: Bool = false) throws -> String {
        guard let base64Encoded = self.data(using: .ascii)?.base64EncodedString() else {
            throw CashuError.tokenEncoding(".encodeBase64UrlSafe failed for string: \(self)")
        }
        
        var urlSafeBase64 = base64Encoded.urlSafe

        if removePadding {
            urlSafeBase64 = urlSafeBase64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }

        return urlSafeBase64
    }
    
    func decodeBase64UrlSafe() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let stripped = base64.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                             .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let remainder = stripped.count % 4
        let paddingLength = remainder == 0 ? 0 : 4 - remainder
        base64 = stripped + String(repeating: "=", count: paddingLength)
        
        
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
    
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
