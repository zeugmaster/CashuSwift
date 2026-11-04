import XCTest
import SwiftBLST
import secp256k1
@testable import CashuSwift

/// NUT-13 v3 derivation vectors (nuts tests/13 "Version 3").
final class Nut13v3Tests: XCTestCase {

    let seed = "6e757431332076332074657374207365656400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    struct Vector { let counter: UInt64; let secretKey: String; let secret: String; let blindingFactor: String; let numsOffset: String }

    let vectors = [
        Vector(counter: 0,
               secretKey: "47196dc081150ce13fd0e478b8b71831b825be389211c9c56a8062a61af70347",
               secret: "02e6e7cfa7b82d4b3b449fa6466c893469a727d0214d48db4956a6054b8022a29b",
               blindingFactor: "156857a0bce1b2788895f1885a21c56cf000df0de1e855608c7ccb6d9e2d7728",
               numsOffset: "4af68649f3230c5589879f0cf33fd6d9f007cd3a54a2e6ed8699a576630fc025"),
        Vector(counter: 1,
               secretKey: "659a545656334a47e08de62377e2f3128c72cd27e576908842e1ab359d395247",
               secret: "03a882e17eb79f4f87313b299e208f9109734d0211a8df307b1570dbad2cdf74bf",
               blindingFactor: "6de008e7a6c418b76a94e48c4b71a11078173de70abb3eaeb7cc1273a6dccede",
               numsOffset: "d78b39a2ba263f92ea3ea2f721705c545d949349767e55bbdc41884cbb9a8b18"),
        Vector(counter: 2,
               secretKey: "cee0df42cdaee25b228300b460edcbfab94be650ce2676abd77ef0697311e5e2",
               secret: "02da107b7bfa3afedc0b49c62de58cb5429e1ad42b45c14a3e6da20156222ea41b",
               blindingFactor: "35f56bb2016802a96a2846de8635712281d68182788410735b9826a211499fd4",
               numsOffset: "d01054af49de60a8a62c592c4bea44f02782f7c6371136d985dfd9d690de5a15"),
        Vector(counter: 3,
               secretKey: "46c2c20d79496e1ebe19805ba4df33535474800eefefc252140e1f20d0284ffe",
               secret: "03189b6c67a0046084bbd2d810b5c6086c117082fe569cb56107d70f4acf8ddb5c",
               blindingFactor: "65724fcdbc4ccfbb2a610b1bddd14238492b81d3761584b6492fcbadfeb9355f",
               numsOffset: "54d0371fad402c83b0f3854fd9b7c876da857e7f276614d7e19dfb6680356f09"),
    ]

    func testProofKeysCounters0To3() throws {
        for v in vectors {
            let keys = try CashuSwift.Crypto.v3ProofKeys(seed: seed, keysetID: keysetID, counter: v.counter)
            XCTAssertEqual(hex(Array(keys.k.dataRepresentation)), v.secretKey, "counter \(v.counter)")
            XCTAssertEqual(hex(Array(keys.k.publicKey.dataRepresentation)), v.secret, "counter \(v.counter)")
            XCTAssertEqual(hex(keys.r.bytes), v.blindingFactor, "counter \(v.counter)")
            let u = try CashuSwift.Crypto.v3NumsOffset(seed: seed, keysetID: keysetID, counter: v.counter)
            XCTAssertEqual(hex(Array(u.dataRepresentation)), v.numsOffset, "counter \(v.counter)")

            // The output-generation path returns k in the secrets slot and derives the same B_.
            let out = try CashuSwift.Crypto.BLS.deterministicOutput(keysetID: keysetID, seed: seed, index: Int(v.counter))
            XCTAssertEqual(out.secret, v.secretKey)
            XCTAssertEqual(out.blindingFactor, v.blindingFactor)
        }
    }

    func testBlindingFactorRejectionLoopAcceptsAtAttempt7() throws {
        // Counter 0's 0x01 branch rejects attempts 0–6 (x >= BLS_FR_ORDER) and accepts at 7.
        for attempt in 0..<UInt32(7) {
            let digest = CashuSwift.Crypto.hmacSHA256(key: try seed.bytes,
                                                      message: try CashuSwift.Crypto.v3Message(scope: try keysetID.bytes, counter: 0,
                                                                                               type: .blindingFactor, attempt: attempt))
            XCTAssertThrowsError(try BLST.Scalar(bytes: digest), "attempt \(attempt) must be rejected")
        }
        let accepted = CashuSwift.Crypto.hmacSHA256(key: try seed.bytes,
                                                    message: try CashuSwift.Crypto.v3Message(scope: try keysetID.bytes, counter: 0,
                                                                                             type: .blindingFactor, attempt: 7))
        XCTAssertEqual(hex(accepted), vectors[0].blindingFactor)
    }

    func testYOverDecodedSecretBytes() throws {
        let proof = CashuSwift.Proof(keysetID: keysetID, amount: 1, secret: vectors[0].secret, C: "")
        XCTAssertEqual(try CashuSwift.stateCheckY(for: proof),
                       "a0acf939f033e3d0ae9b5f784341fada38367eec190edfb34e1f0cce9050c80672dbee77a7512b7243544c85ae290a73")
    }

    func testLeafKeys() throws {
        let expected = [
            ("8aac8b31fe4babb8097f416ef8f8508fdba63589087f4d10bf6f96bddba23788", "033c1828d880aebfd316781d3dffe1c45953087917e6f734032666c1ed80f0653c"),
            ("c77d6d9440bde035b140fe622e96dea2ffb2227179c3241df6e2994811984656", "0210b63f8016248a6f4c372366eb521784002ab182acbeba94e00ec4898f629d81"),
            ("ba7a8fc52b8c77b7412e5edaae211d92f2c79980788e3e3a480eb0dccac0b33e", "020e35e2edc190c2c34e46e586233a4f357e35fa428ae6f53636bb93f201792096"),
        ]
        for (i, (priv, pub)) in expected.enumerated() {
            let key = try CashuSwift.Crypto.v3LeafKey(seed: seed, keysetID: keysetID, counter: 0, index: UInt32(i))
            XCTAssertEqual(hex(Array(key.dataRepresentation)), priv)
            XCTAssertEqual(hex(Array(key.publicKey.dataRepresentation)), pub)
        }
    }

    func testQuoteLockKeys() throws {
        let mintPubkey = "0338596797cef0627f653cd6568387361b00314add55d9f1ea9c94f46ae421e3da"
        let expected = [
            ("8140af6b627ddf38f9148c7266dca12d396de9266859648df699727c5b205a99", "0292905560a6a511a13e383ee27e220aeffc85b7a7bc293e6935b1d3678d209812"),
            ("5980da641d9391abed79f528dbea0b85a61cff419bc93bce744d105779413b7a", "02b357c1ec7bdd73e4ede25d68619ee607c632409e89bcc518a82370b3f499615d"),
        ]
        for (counter, (priv, pub)) in expected.enumerated() {
            let key = try CashuSwift.Crypto.v3QuoteLockKey(seed: seed, mintPubkey: mintPubkey, counter: UInt64(counter))
            XCTAssertEqual(hex(Array(key.privateKey)), priv)
            XCTAssertEqual(key.publicKey, pub)
        }
    }
}
