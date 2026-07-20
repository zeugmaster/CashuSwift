//
//  NUT20.swift
//  CashuSwift
//
//  NUT-20: Signature on Mint Quote. Message aggregation, BIP340 signing and
//  deterministic quote-locking key derivation.
//

import Foundation
import secp256k1

extension CashuSwift {
    /// Which NUT-20 `msg_to_sign` construction to use.
    ///
    /// The spec was revised to a domain-tagged, length-framed format, but deployed
    /// mints (e.g. cdk <= rev 6132607) still verify the original plain
    /// concatenation `quote_id || hex(B_0) || ... || hex(B_n)` as UTF-8 bytes.
    /// Callers targeting such mints must pass `.legacyConcat` until the mint
    /// implementation catches up.
    public enum Nut20SignatureFormat: Sendable {
        case current
        case legacyConcat
    }
}

extension CashuSwift.Crypto {

    /// Builds the NUT-20 `msg_to_sign` over raw bytes:
    /// `b"Cashu_MintQuoteSig_v1" || len32(quote) || quote || per output: len32(amount)||amount || len32(B_)||B_`
    /// where amounts are canonical minimal big-endian bytes and `B_` is the raw
    /// (hex-decoded) blinded message.
    static func nut20MessageToSign(quoteID: String, outputs: [CashuSwift.Output]) throws -> Data {
        func len32(_ n: Int) -> [UInt8] {
            withUnsafeBytes(of: UInt32(n).bigEndian, Array.init)
        }
        func minimalBigEndian(_ value: Int) -> [UInt8] {
            var v = UInt64(value)
            var out = [UInt8]()
            while v > 0 {
                out.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
            return out
        }

        var msg = [UInt8]("Cashu_MintQuoteSig_v1".utf8)
        let quoteBytes = [UInt8](quoteID.utf8)
        msg += len32(quoteBytes.count)
        msg += quoteBytes
        for output in outputs {
            let amountBytes = minimalBigEndian(output.amount)
            msg += len32(amountBytes.count)
            msg += amountBytes
            let bBytes = try output.B_.bytes
            msg += len32(bBytes.count)
            msg += bBytes
        }
        return Data(msg)
    }

    /// Builds the pre-revision NUT-20 message: `quote_id || hex(B_0) || ... || hex(B_n)`
    /// concatenated as UTF-8 bytes.
    static func nut20LegacyMessageToSign(quoteID: String, outputs: [CashuSwift.Output]) -> Data {
        var msg = quoteID
        for output in outputs {
            msg += output.B_.lowercased()
        }
        return Data(msg.utf8)
    }

    /// BIP340 Schnorr signature on SHA-256 of the NUT-20 message, hex-encoded.
    static func nut20Signature(quoteID: String,
                               outputs: [CashuSwift.Output],
                               privateKey: Data,
                               format: CashuSwift.Nut20SignatureFormat = .current) throws -> String {
        let key = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey)
        let message: Data
        switch format {
        case .current:
            message = try nut20MessageToSign(quoteID: quoteID, outputs: outputs)
        case .legacyConcat:
            message = nut20LegacyMessageToSign(quoteID: quoteID, outputs: outputs)
        }
        let signature = try key.signature(for: message)
        return String(bytes: signature.bytes)
    }

    /// Derives the deterministic NUT-20 quote-locking key `m/129373'/20'/0'/0'/{counter}`
    /// from the wallet seed. Returns the raw private key and the compressed public key hex.
    static func nut20QuoteLockingKey(seed: String, counter: UInt32) throws -> (privateKey: Data, publicKey: String) {
        let path = "m/129373'/20'/0'/0'/\(counter)"
        let key = try childPrivateKeyForDerivationPath(seed: seed, derivationPath: path)
        return (key.dataRepresentation, String(bytes: key.publicKey.dataRepresentation))
    }
}
