import XCTest
import SwiftBLST
@testable import CashuSwift

/// v3 (BLS12-381) vectors from nuts tests/00 (round trip, batch) and tests/02 (keyset ids).
final class BLSv3Tests: XCTestCase {

    typealias BLS = CashuSwift.Crypto.BLS

    // Round-trip vector: secret "test_message" (raw bytes), r = 3, mint scalar a = 2.
    let secret = Array("test_message".utf8)
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

        let B_ = BLS.blind(secretBytes: secret, r: r)
        XCTAssertEqual(hex(B_.compressedBytes), bHex)

        let K2 = a.publicKeyG2()
        XCTAssertEqual(hex(K2.compressedBytes), kHex)

        let C_ = B_.multiplied(by: a)            // mint signs
        XCTAssertEqual(hex(C_.compressedBytes), cBlindHex)

        let C = BLS.unblind(C_: C_, r: r)
        XCTAssertEqual(hex(C.compressedBytes), cHex)

        XCTAssertTrue(BLS.verify(C: C, mintKey: K2, secretBytes: secret))
        XCTAssertFalse(BLS.verify(C: C, mintKey: K2, secretBytes: Array("other".utf8)))
    }

    func testUnblindAndVerifyHelper() throws {
        let resultC = try BLS.unblindAndVerify(C_Hex: cBlindHex,
                                               blindingFactorHex: scalarHex(3),
                                               secretBytes: secret,
                                               mintKeyHex: kHex)
        XCTAssertEqual(resultC, cHex)

        // Wrong secret must fail the eager pairing verification.
        XCTAssertThrowsError(try BLS.unblindAndVerify(C_Hex: cBlindHex,
                                                      blindingFactorHex: scalarHex(3),
                                                      secretBytes: Array("tampered".utf8),
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

        // Distinct counters diverge; the secret slot is the 32-byte key k; r is a valid Fr scalar.
        let c = try BLS.deterministicOutput(keysetID: keysetID, seed: seed, index: 1)
        XCTAssertNotEqual(a.B_, c.B_)
        XCTAssertEqual(a.secret.count, 64)
        XCTAssertNoThrow(try BLS.scalar(fromHex: a.blindingFactor))
        XCTAssertThrowsError(try BLS.deterministicOutput(keysetID: String(keysetID.prefix(16)), seed: seed, index: 0),
                             "short keyset ids are refused as derivation scope")
    }

    func testBatchChallengeMatchesVector() throws {
        let K2 = try BLS.g2Point(fromHex: kHex)
        let items: [BLS.BatchItem] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, Array("batch_proof_1".utf8)),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, Array("batch_proof_2".utf8)),
        ]
        XCTAssertEqual(hex(BLS.batchChallenge(items)), batchChallengeHex)
    }

    func testBatchVerify() throws {
        let K2 = try BLS.g2Point(fromHex: kHex)
        let valid: [BLS.BatchItem] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, Array("batch_proof_1".utf8)),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, Array("batch_proof_2".utf8)),
        ]
        XCTAssertTrue(try BLS.batchVerify(valid))
        XCTAssertTrue(try BLS.batchVerify([]))

        // Swapping a secret breaks the per-proof equality and must be rejected.
        let tampered: [BLS.BatchItem] = [
            (try BLS.g1Point(fromHex: batchC1Hex), K2, Array("batch_proof_2".utf8)),
            (try BLS.g1Point(fromHex: batchC2Hex), K2, Array("batch_proof_1".utf8)),
        ]
        XCTAssertFalse(try BLS.batchVerify(tampered))
    }

    func testPointValidationRejectsIdentity() {
        let g1Identity = "c0" + String(repeating: "00", count: 47)
        let g2Identity = "c0" + String(repeating: "00", count: 95)
        XCTAssertThrowsError(try BLS.g1Point(fromHex: g1Identity))
        XCTAssertThrowsError(try BLS.g2Point(fromHex: g2Identity))
    }

    // MARK: - NUT-02 v3 keyset id vectors

    static let g2Key1 = "8d0273f6bf31ed37c3b8d68083ec3d8e20b5f2cc170fa24b9b5be35b34ed013f9a921f1cad1644d4bdb14674247234c8049cd1dbb2d2c3581e54c088135fef36505a6823d61b859437bfc79b617030dc8b40e32bad1fa85b9c0f368af6d38d3c"
    static let g2Key2 = "8bf78a97086750eb166986ed8e428ca1d23ae3bbf8b2ee67451d7dd84445311e8bc8ab558b0bc008199f577195fc39b7152110e866f1a6e8c5348f6e005dbd93de671b7d0fbfa04d6614bcdd27a3cb2a70f0deacb3608ba95226268481a0be7c"
    static let g2Key4 = "8c60dae92451206390e30b5daa7151d63624dee496753c87dd54eadc92dc9602081fae02a1a53bac97e984a571923a5d0a29e38da2d42fd4712052800c7c8dd6e94fd9f506e946068aaac799d60b94c2d7515769ffdd32ea95d3910330ec47de"
    static let g2Key8 = "a55dafcdf339360f74e3fd32296d062d5e36db3c2570e13a889b38502c0ff71864b19e324bc9c661c29b07c9cc378b5919c1656979648d7c3ef4bd6501fcc96490a34e47fe25afc8b14d60f1c3772138acaf8a0a5e4f940f57206eba74fdc973"

    func testKeysetIDv3Vector1() throws {
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv3(keyset: ["1": Self.g2Key1, "2": Self.g2Key2],
                                                              unit: "sat", inputFeePPK: nil)
        XCTAssertEqual(id, "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6")
        XCTAssertEqual(CashuSwift.KeysetVersion(keysetID: id), .v3)
    }

    func testKeysetIDv3Vector2IgnoresFinalExpiry() throws {
        let keys = ["1": Self.g2Key1, "2": Self.g2Key2, "4": Self.g2Key4, "8": Self.g2Key8]
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv3(keyset: keys, unit: "sat", inputFeePPK: 100)
        XCTAssertEqual(id, "027f0dcd008156363a8418b88f38ddd5155a38c46a3f27c15c7eb40ec5f04cb4b3")

        // `Keyset.validID` routes v3 ids here and ignores `final_expiry`.
        let json: [String: Any] = ["id": id, "unit": "sat", "active": true, "input_fee_ppk": 100,
                                   "final_expiry": 2000000000, "keys": keys]
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self,
                                              from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(keyset.validID)
    }
}
