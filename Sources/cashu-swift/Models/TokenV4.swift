import Foundation
import SwiftCBOR

extension CashuSwift {
    struct TokenV4 {
        let mint: String          // "m" - mint URL
        let unit: String          // "u" - currency unit
        let memo: String?         // "d" - optional memo
        let tokens: [TokenEntry]  // "t" - array of token entries

        struct TokenEntry {
            let keysetID: Data                    // "i" - keyset ID
            let proofs: [Proof]                   // "p" - array of proofs

            struct Proof {
                let amount: Int                   // "a" - amount
                let secret: String                // "s" - secret
                let signature: Data               // "c" - signature
                let dleqProof: DLEQProof?         // "d" - optional DLEQ proof
                let witness: String?              // "w" - optional witness

                struct DLEQProof {
                    let e: Data   // "e"
                    let s: Data   // "s"
                    let r: Data   // "r"
                }
            }
        }
    }
}

// MARK: - CBOR Extensions

extension CBOR {
    func asMap() -> [CBOR: CBOR]? {
        if case let .map(map) = self {
            return map
        }
        return nil
    }

    func asArray() -> [CBOR]? {
        if case let .array(array) = self {
            return array
        }
        return nil
    }

    func asString() -> String? {
        if case let .utf8String(string) = self {
            return string
        }
        return nil
    }

    func asByteString() -> Data? {
        if case let .byteString(bytes) = self {
            return Data(bytes)
        }
        return nil
    }

    func asUnsignedInt() -> UInt64? {
        if case let .unsignedInt(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - TokenV4 Extensions

extension CashuSwift.TokenV4 {
    init(fromCBOR cbor: CBOR) throws {
        guard let cborMap = cbor.asMap() else {
            throw DecodingError.typeMismatch(
                CBOR.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected CBOR map")
            )
        }

        guard let mint = cborMap[.utf8String("m")]?.asString(),
              let unit = cborMap[.utf8String("u")]?.asString(),
              let tokensArray = cborMap[.utf8String("t")]?.asArray() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing required fields in TokenV4")
            )
        }

        self.mint = mint
        self.unit = unit
        self.memo = cborMap[.utf8String("d")]?.asString()
        self.tokens = try tokensArray.map { try TokenEntry(fromCBOR: $0) }
    }

    func toCBOR() -> CBOR {
        var cborMap: [CBOR: CBOR] = [
            .utf8String("m"): .utf8String(mint),
            .utf8String("u"): .utf8String(unit),
            .utf8String("t"): .array(tokens.map { $0.toCBOR() })
        ]
        if let memo = memo {
            cborMap[.utf8String("d")] = .utf8String(memo)
        }
        return .map(cborMap)
    }
}

extension CashuSwift.TokenV4.TokenEntry {
    init(fromCBOR cbor: CBOR) throws {
        guard let cborMap = cbor.asMap() else {
            throw DecodingError.typeMismatch(
                CBOR.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected CBOR map")
            )
        }

        guard let keysetIDData = cborMap[.utf8String("i")]?.asByteString(),
              let proofsArray = cborMap[.utf8String("p")]?.asArray() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing required fields in TokenEntry")
            )
        }

        self.keysetID = keysetIDData
        self.proofs = try proofsArray.map { try Proof(fromCBOR: $0) }
    }

    func toCBOR() -> CBOR {
        let cborMap: [CBOR: CBOR] = [
            .utf8String("i"): .byteString([UInt8](keysetID)),
            .utf8String("p"): .array(proofs.map { $0.toCBOR() })
        ]
        return .map(cborMap)
    }
}

extension CashuSwift.TokenV4.TokenEntry.Proof {
    init(fromCBOR cbor: CBOR) throws {
        guard let cborMap = cbor.asMap() else {
            throw DecodingError.typeMismatch(
                CBOR.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected CBOR map")
            )
        }

        guard let amountValue = cborMap[.utf8String("a")]?.asUnsignedInt(),
              let secret = cborMap[.utf8String("s")]?.asString(),
              let signatureData = cborMap[.utf8String("c")]?.asByteString() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing required fields in Proof")
            )
        }

        self.amount = Int(amountValue)
        self.secret = secret
        self.signature = signatureData
        self.witness = cborMap[.utf8String("w")]?.asString()

        if let dleqCBOR = cborMap[.utf8String("d")] {
            self.dleqProof = try DLEQProof(fromCBOR: dleqCBOR)
        } else {
            self.dleqProof = nil
        }
    }

    func toCBOR() -> CBOR {
        var cborMap: [CBOR: CBOR] = [
            .utf8String("a"): .unsignedInt(UInt64(amount)),
            .utf8String("s"): .utf8String(secret),
            .utf8String("c"): .byteString([UInt8](signature))
        ]
        if let dleq = dleqProof {
            cborMap[.utf8String("d")] = dleq.toCBOR()
        }
        if let witness = witness {
            cborMap[.utf8String("w")] = .utf8String(witness)
        }
        return .map(cborMap)
    }
}

extension CashuSwift.TokenV4.TokenEntry.Proof.DLEQProof {
    init(fromCBOR cbor: CBOR) throws {
        guard let cborMap = cbor.asMap() else {
            throw DecodingError.typeMismatch(
                CBOR.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected CBOR map")
            )
        }

        guard let eData = cborMap[.utf8String("e")]?.asByteString(),
              let sData = cborMap[.utf8String("s")]?.asByteString(),
              let rData = cborMap[.utf8String("r")]?.asByteString() else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Missing required fields in DLEQProof")
            )
        }

        self.e = eData
        self.s = sData
        self.r = rData
    }

    func toCBOR() -> CBOR {
        let cborMap: [CBOR: CBOR] = [
            .utf8String("e"): .byteString([UInt8](e)),
            .utf8String("s"): .byteString([UInt8](s)),
            .utf8String("r"): .byteString([UInt8](r))
        ]
        return .map(cborMap)
    }
}

// MARK: - Serialization

extension CashuSwift.TokenV4 {
    public func serialize() throws -> String {
        let cborValue = self.toCBOR()
        let cborData = cborValue.encode()
        
        let base64URLSafe = Data(cborData).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")

        return "cashuB\(base64URLSafe)"
    }
    
    init(tokenString: String) throws {
        guard tokenString.hasPrefix("cashuB") else {
            throw CashuError.tokenDecoding("Tried to decode V4 token that does not start with 'cashuB'")
        }
        
        let base64URLSafeString = String(tokenString.dropFirst(6))
        
        guard let cborData = base64URLSafeString.decodeBase64UrlSafe() else {
            throw CashuError.tokenDecoding("Could not turn base64 string into data.")
        }
        
        // Decode CBOR data into a CBOR value
        guard let cborValue = try? CBOR.decode([UInt8](cborData)) else {
            throw CashuError.tokenDecoding("Could not turn data into CBOR")
        }
        
        self = try CashuSwift.TokenV4(fromCBOR: cborValue)
    }
}

// MARK: - Data Extension

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
