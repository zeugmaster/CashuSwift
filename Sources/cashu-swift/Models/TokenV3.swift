//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import OSLog

fileprivate var logger = Logger(subsystem: "cashu-swift", category: "Token")

extension CashuSwift {
    
    /// Represents the version of a Cashu token.
    public enum TokenVersion:Codable {
        /// Version 3 token format.
        case V3
        /// Version 4 token format.
        case V4
    }

    /// Represents a Version 3 Cashu token.
    public struct TokenV3: Codable, Equatable {
        public static func == (lhs: TokenV3, rhs: TokenV3) -> Bool {
            lhs.token == rhs.token && lhs.memo == rhs.memo && lhs.unit == rhs.unit
        }
        
        /// Array of proof containers.
        public let token:[ProofContainer]
        
        /// Optional memo for the token.
        public let memo:String?
        
        /// Optional unit string.
        public let unit:String?
        
        /// Creates a new TokenV3 instance.
        /// - Parameters:
        ///   - token: Array of proof containers
        ///   - memo: Optional memo
        ///   - unit: Optional unit string
        public init(token: [ProofContainer],
                    memo: String? = nil,
                    unit:String? = nil) {
            self.token = token
            self.memo = memo
            self.unit = unit
        }
        
        enum CodingKeys:String, CodingKey {
            case token
            case memo
            case unit
        }
        
        init(tokenString: String) throws {
            let noPrefix = String(tokenString.dropFirst(6))
            guard let jsonData = noPrefix.decodeBase64UrlSafe() else {
                throw CashuError.tokenDecoding("Unable to decode base64 url safe string to data.")
            }
            self = try JSONDecoder().decode(TokenV3.self, from: jsonData)
        }
        
        /// Serializes the token to a string.
        /// - Returns: The serialized token string
        /// - Throws: An error if serialization fails
        public func serialize() throws -> String {
            return try encodeV3()
        }
        
        private func encodeV3() throws -> String {
            let jsonData = try JSONEncoder().encode(self)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            let safeString = try jsonString.encodeBase64UrlSafe()
            return "cashuA" + safeString
        }
        
        func prettyJSON() -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            do {
                let data = try encoder.encode(self)
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }
    }

    /// Container for proofs associated with a specific mint.
    public struct ProofContainer: Codable, Equatable {
        /// The mint URL string.
        public let mint:String
        
        /// Array of proofs from this mint.
        public let proofs:[Proof]
        
        /// Creates a new proof container.
        /// - Parameters:
        ///   - mint: The mint URL string
        ///   - proofs: Array of proofs from this mint
        public init(mint: String, proofs: [Proof]) {
            self.mint = mint
            self.proofs = proofs
        }
    }
}

extension Data {
    
    var base64URLsafe:String {
        let string = self.base64EncodedString()
        let urlSafeString = string.replacingOccurrences(of: "+", with: "-")
                                  .replacingOccurrences(of: "/", with: "_")
        return urlSafeString
    }
    
}
