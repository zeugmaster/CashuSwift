import XCTest
import SwiftBLST
@testable import CashuSwift

/// v3 (BLS12-381) BDHKE vectors from NUT-00 / Nutshell PR #999, mirrored from
/// cashu-ts `test/crypto/bls.test.ts`.
final class BLSv3Tests: XCTestCase {

    typealias BLS = CashuSwift.Crypto.BLS

    // Round-trip vector: secret "test_message", r = 3, mint scalar a = 2.
    let secret = "test_message"
    let yHex = "860d58e5aeda1376185436ed96412313424cc079e056d1dab595e6db4c2c9685fec7da052c8db68d88985b75a42388ad"
    let bHex = "8e88c5f6a93f653784a66b033a00e52128499e18b095c2a56f080d1c2a937ffc9ef4600804a48d087bbd1f662f6b068f"
    let kHex = "aa4edef9c1ed7f729f520e47730a124fd70662a904ba1074728114d1031e1572c6c886f6b57ec72a6178288c47c335771638533957d540a9d2370f17cc7ed5863bc0b995b8825e0ee1ea1e1e4d00dbae81f14b0bf3611b78c952aacab827a053"
    let cBlindHex = "8d52d7a6cbe5e99858d5c15c092d11a0c387c78917471211082a6e5afc2a79680dfa188fafe5d4a51c5398ce160e7a16"
    let cHex = "b7a4881059133fd91a8753600d9a5e524c65d6224f6fe2d5aef9e59f1507fdad90b3b4d48ee46da5c8dfaa0b88e28b69"

    // Batch vector: two proofs under K = 2·G2.
    let batchC1Hex = "acebf797506a7031cef3189904715cb22792528f1ea0e6ab25341401d245539438ed97122f00e38ee6185cc20b09ba11"
    let batchC2Hex = "9776497ad47a00f8a56233fb88f939b0572cf174a4c6d2446c0b1060434e305fae6845fd1f68b70376ba53ffe67f0414"
    let batchChallengeHex = "539b5df396e82adab0760459590d38122d2552bc74f6bd860e915ff3b95e550a"

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func scalarHex(_ n: UInt8) -> String { String(repeating: "0", count: 62) + String(format: "%02x", n) }

    func testHashToCurveMatchesVector() {
        XCTAssertEqual(hex(BLS.hashToCurveG1(secret).compressedBytes), yHex)
    }

    func testBlindUnblindVerifyRoundTrip() throws {
        let r = try BLS.scalar(fromHex: scalarHex(3))
        let a = try BLS.scalar(fromHex: scalarHex(2))

        let B_ = BLS.blind(secret: secret, r: r)
        XCTAssertEqual(hex(B_.compressedBytes), bHex)

        let K2 = a.publicKeyG2()
        XCTAssertEqual(hex(K2.compressedBytes), kHex)

        let C_ = B_.multiplied(by: a)            // mint signs
        XCTAssertEqual(hex(C_.compressedBytes), cBlindHex)

        let C = BLS.unblind(C_: C_, r: r)
        XCTAssertEqual(hex(C.compressedBytes), cHex)

        XCTAssertTrue(BLS.verify(C: C, mintKey: K2, secret: secret))
        XCTAssertFalse(BLS.verify(C: C, mintKey: K2, secret: "other"))
    }

    func testUnblindAndVerifyHelper() throws {
        let resultC = try BLS.unblindAndVerify(C_Hex: cBlindHex,
                                               blindingFactorHex: scalarHex(3),
                                               secret: secret,
                                               mintKeyHex: kHex)
        XCTAssertEqual(resultC, cHex)

        // Wrong secret must fail the eager pairing verification.
        XCTAssertThrowsError(try BLS.unblindAndVerify(C_Hex: cBlindHex,
                                                      blindingFactorHex: scalarHex(3),
                                                      secret: "tampered",
                                                      mintKeyHex: kHex))
    }

    func testDeterministicOutputIsReproducible() throws {
        let seed = String(repeating: "00", count: 32)
        let keysetID = "02" + String(repeating: "ab", count: 32)
        let a = try BLS.deterministicOutput(keysetID: keysetID, seed: seed, index: 0)
        let b = try BLS.deterministicOutput(keysetID: keysetID, seed: seed, index: 0)
        XCTAssertEqual(a.B_, b.B_)
        XCTAssertEqual(a.blindingFactor, b.blindingFactor)
        XCTAssertEqual(a.secret, b.secret)

        // Distinct counters diverge; secret is a 64-char hex string; r is a valid Fr scalar.
        let c = try BLS.deterministicOutput(keysetID: keysetID, seed: seed, index: 1)
        XCTAssertNotEqual(a.B_, c.B_)
        XCTAssertEqual(a.secret.count, 64)
        XCTAssertNoThrow(try BLS.scalar(fromHex: a.blindingFactor))
    }

    func testBatchChallengeMatchesVector() throws {
        let K2 = try BLS.g2Point(fromHex: kHex)
        let items: [(C: BLST.G1Point, K2: BLST.G2Point, secret: String)] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, "batch_proof_1"),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, "batch_proof_2"),
        ]
        XCTAssertEqual(hex(BLS.batchChallenge(items)), batchChallengeHex)
    }

    func testBatchVerify() throws {
        let K2 = try BLS.g2Point(fromHex: kHex)
        let valid: [(C: BLST.G1Point, K2: BLST.G2Point, secret: String)] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, "batch_proof_1"),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, "batch_proof_2"),
        ]
        XCTAssertTrue(try BLS.batchVerify(valid))
        XCTAssertTrue(try BLS.batchVerify([]))

        // Swapping a secret breaks the per-proof equality and must be rejected.
        let tampered: [(C: BLST.G1Point, K2: BLST.G2Point, secret: String)] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, "batch_proof_2"),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, "batch_proof_1"),
        ]
        XCTAssertFalse(try BLS.batchVerify(tampered))
    }

    func testPointValidationRejectsIdentity() {
        let g1Identity = "c0" + String(repeating: "00", count: 47)
        let g2Identity = "c0" + String(repeating: "00", count: 95)
        XCTAssertThrowsError(try BLS.g1Point(fromHex: g1Identity))
        XCTAssertThrowsError(try BLS.g2Point(fromHex: g2Identity))
    }

    func testKeysetIDv3DerivationAndValidation() throws {
        // Distinct G2 key per amount (spec requires distinct per-amount keys).
        var keys = [String: String]()
        for (i, amount) in [1, 2, 4, 8].enumerated() {
            let a = try BLS.scalar(fromHex: scalarHex(UInt8(i + 2)))
            keys[String(amount)] = hex(a.publicKeyG2().compressedBytes)
        }
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv2(keyset: keys,
                                                              unit: "sat",
                                                              inputFeePPK: 0,
                                                              finalExpiry: nil,
                                                              versionByte: "02")
        XCTAssertTrue(id.hasPrefix("02"))
        XCTAssertEqual(id.count, 66)
        XCTAssertEqual(CashuSwift.KeysetVersion(keysetID: id), .v3)
    }
}
