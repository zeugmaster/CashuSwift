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
    
    public enum TokenVersion:Codable {
        case V3
        case V4
    }

    public struct TokenV3: Codable, Equatable {
        public static func == (lhs: TokenV3, rhs: TokenV3) -> Bool {
            lhs.token == rhs.token && lhs.memo == rhs.memo && lhs.unit == rhs.unit
        }
        
        public let token:[ProofContainer]
        public let memo:String?
        public let unit:String?
        
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

    public struct ProofContainer: Codable, Equatable {
        public let mint:String
        public let proofs:[Proof]
        
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
