//
//  Nut20Tests.swift
//  CashuSwiftTests
//
//  NUT-20: message aggregation, quote-locking key derivation and signing.
//

import XCTest
@testable import CashuSwift

final class Nut20Tests: XCTestCase {

    func testNut20MessageAggregation() throws {
        let outputs = [
            CashuSwift.Output(amount: 1, B_: "02aabb", id: "005b109edf5a8bd6"),
            CashuSwift.Output(amount: 256, B_: "ccdd", id: "005b109edf5a8bd6"),
        ]
        let msg = try CashuSwift.Crypto.nut20MessageToSign(quoteID: "q1", outputs: outputs)

        var expected = [UInt8]("Cashu_MintQuoteSig_v1".utf8)
        expected += [0, 0, 0, 2] + [UInt8]("q1".utf8)          // len32("q1") || "q1"
        expected += [0, 0, 0, 1, 0x01]                          // amount 1 -> 0x01
        expected += [0, 0, 0, 3, 0x02, 0xAA, 0xBB]              // B_ raw bytes
        expected += [0, 0, 0, 2, 0x01, 0x00]                    // amount 256 -> 0x0100
        expected += [0, 0, 0, 2, 0xCC, 0xDD]
        XCTAssertEqual([UInt8](msg), expected)
    }

    func testNut20LegacyMessageAggregation() {
        let outputs = [
            CashuSwift.Output(amount: 1, B_: "02AABB", id: "005b109edf5a8bd6"),
            CashuSwift.Output(amount: 256, B_: "ccdd", id: "005b109edf5a8bd6"),
        ]
        let msg = CashuSwift.Crypto.nut20LegacyMessageToSign(quoteID: "q1", outputs: outputs)
        XCTAssertEqual(msg, Data("q102aabbccdd".utf8))
    }

    func testNut20KeyDerivationAndSignature() throws {
        let seed = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

        let key0 = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 0)
        let key0Again = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 0)
        let key1 = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 1)

        // deterministic and counter-separated
        XCTAssertEqual(key0.privateKey, key0Again.privateKey)
        XCTAssertEqual(key0.publicKey, key0Again.publicKey)
        XCTAssertNotEqual(key0.privateKey, key1.privateKey)

        // compressed secp256k1 pubkey, hex-encoded
        XCTAssertEqual(key0.publicKey.count, 66)
        XCTAssertTrue(key0.publicKey.hasPrefix("02") || key0.publicKey.hasPrefix("03"))

        let outputs = [CashuSwift.Output(amount: 8, B_: "02aabb", id: "005b109edf5a8bd6")]
        let signature = try CashuSwift.Crypto.nut20Signature(
            quoteID: "9d745270-1405-46de-b5c5-e2762b4f5e00",
            outputs: outputs,
            privateKey: key0.privateKey
        )
        // 64-byte BIP340 Schnorr signature, hex-encoded
        XCTAssertEqual(signature.count, 128)
    }
}
