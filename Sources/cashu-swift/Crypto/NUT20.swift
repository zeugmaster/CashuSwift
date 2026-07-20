//
//  NUT20.swift
//  CashuSwift
//
//  NUT-20: Signature on Mint Quote. Message aggregation, BIP340 signing and
//  deterministic quote-locking key derivation.
//

import Foundation
import secp256k1

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

    /// BIP340 Schnorr signature on SHA-256 of the NUT-20 message, hex-encoded.
    static func nut20Signature(quoteID: String,
                               outputs: [CashuSwift.Output],
                               privateKey: Data) throws -> String {
        let key = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKey)
        let message = try nut20MessageToSign(quoteID: quoteID, outputs: outputs)
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
