//
//  File.swift
//  
//
//  Created by zm on 07.05.24.
//

import Foundation
import OSLog

fileprivate var logger = Logger(subsystem: "cashu-swift", category: "Token")

enum CashuError:Error {
    case InvalidTokenError
    case TokenEncodingError
}

enum TokenVersion:Codable {
    case V3
    case V4
}

class Token:Codable, Equatable {
    static func == (lhs: Token, rhs: Token) -> Bool {
        lhs.token == rhs.token && lhs.memo == rhs.memo && lhs.unit == rhs.unit
    }
    
    let token:[ProofContainer]
    let memo:String?
    var unit:String?
    
    init(token: [ProofContainer], 
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
    
    func serialize(_ toVersion:TokenVersion = .V4) throws -> String {
        switch toVersion {
        case .V3:
            try encodeV3(token: self)
        case .V4:
            fatalError()
        }
    }
    
    private func encodeV3(token:Token) throws -> String {
        let jsonData = try JSONEncoder().encode(self)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let safeString = try jsonString.encodeBase64UrlSafe()
        return "cashuA" + safeString
    }
    
    private func encodeV4cbor(token:Token) throws -> String {
        fatalError("V4 encoding has not been implemented yet")
    }
    
    static func decodeV3(tokenString:String) throws -> Token {
        let noPrefix = String(tokenString.dropFirst(6))
        guard let jsonString = noPrefix.decodeBase64UrlSafe() else {
            throw CashuError.InvalidTokenError
        }
        let jsonData = jsonString.data(using: .utf8)!
        do {
            let token:Token = try JSONDecoder().decode(Token.self, from: jsonData)
            return token
        } catch {
            logger.warning("Could not deserialize token. error: \(String(describing: error))")
            throw CashuError.InvalidTokenError
        }
    }
    
    static func decodeV4(tokenString:String) throws -> Token {
        fatalError("V4 decoding has not been implemented yet")
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

extension String {
    func deserializeToken() throws -> Token {
        var noPrefix = self
        // needs to be in the right order to avoid only stripping cashu: and leaving //
        if self.hasPrefix("cashu://") {
            noPrefix = String(self.dropFirst("cashu://".count))
        }
        if self.hasPrefix("cashu:") {
            noPrefix = String(self.dropFirst("cashu:".count))
        }
        
        if noPrefix.hasPrefix("cashuA") {
            return try Token.decodeV3(tokenString: noPrefix)
        } else if noPrefix.hasPrefix("cashuB") {
            return try Token.decodeV4(tokenString: noPrefix)
        } else {
            throw CashuError.InvalidTokenError
        }
    }
    
    func decodeBase64UrlSafe() -> String? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Check if padding is needed
        let mod4 = base64.count % 4
        if mod4 != 0 {
            base64 += String(repeating: "=", count: 4 - mod4)
        }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let string = String(data: data, encoding: .ascii)
        return string
    }

    func encodeBase64UrlSafe(removePadding: Bool = false) throws -> String {
        guard let base64Encoded = self.data(using: .ascii)?.base64EncodedString() else {
            throw CashuError.TokenEncodingError
        }
        var urlSafeBase64 = base64Encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        if removePadding {
            urlSafeBase64 = urlSafeBase64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }

        return urlSafeBase64
    }
    
    func makeURLSafe() -> String {
        return self
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct ProofContainer:Codable, Equatable {
    let mint:String
    let proofs:[Proof]
}
