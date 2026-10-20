import XCTest
import secp256k1
@testable import CashuSwift

/// NUT-00 "Transaction transcripts" vectors: transcript bytes, digests, input digests and the
/// key-path signatures over them (BIP-340 with zero auxiliary randomness).
final class TranscriptTests: XCTestCase {

    typealias Transaction = CashuSwift.Transaction

    let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"
    let C = "84d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d03327"
    let B_ = "b42a0bcc39598db1dca617aeea6bc367f2566636826dc961a54faae15b3b8d10afc1cb0206e70ab3b0e12c2b9478cd55"
    let secret0 = "02e6e7cfa7b82d4b3b449fa6466c893469a727d0214d48db4956a6054b8022a29b"
    let k0 = "47196dc081150ce13fd0e478b8b71831b825be389211c9c56a8062a61af70347"
    let secret1 = "03a882e17eb79f4f87313b299e208f9109734d0211a8df307b1570dbad2cdf74bf"
    let k1 = "659a545656334a47e08de62377e2f3128c72cd27e576908842e1ab359d395247"
    let quoteKey0 = "8140af6b627ddf38f9148c7266dca12d396de9266859648df699727c5b205a99"
    let lock0 = "0292905560a6a511a13e383ee27e220aeffc85b7a7bc293e6935b1d3678d209812"
    let quoteKey1 = "5980da641d9391abed79f528dbea0b85a61cff419bc93bce744d105779413b7a"
    let lock1 = "02b357c1ec7bdd73e4ede25d68619ee607c632409e89bcc518a82370b3f499615d"

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func proof(_ amount: Int, _ secret: String, k: String) -> CashuSwift.Proof {
        CashuSwift.Proof(keysetID: keysetID, amount: amount, secret: secret, C: C, spendInfo: .init(k: k))
    }
    private func output(_ amount: Int) -> Transaction.Output { .blinded(.init(amount: amount, B_: B_, id: keysetID)) }
    private func key(_ hex: String) throws -> secp256k1.Schnorr.PrivateKey {
        try secp256k1.Schnorr.PrivateKey(dataRepresentation: try hex.bytes)
    }

    /// Signs with `k` and checks both the exact vector signature and verification.
    private func assertSignature(_ expected: String, digest: [UInt8], k: String, pubkey: String,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try CashuSwift.Crypto.schnorrSign(digest: digest, key: try key(k)), expected, file: file, line: line)
        XCTAssertTrue(CashuSwift.Crypto.schnorrVerify(digest: digest, signatureHex: expected, publicKey: try pubkey.bytes), file: file, line: line)
    }

    func testTaggedHashConstant() {
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(Array("Cashu_TransactionInput".utf8))),
                       "4996fee585f625e6a33865ce975efc32c42d2b1b95328385ce45f5209a16e9ec")
    }

    func testSwap() throws {
        let tx = Transaction(inputs: [.proof(proof(8, secret0, k: k0))], outputs: [output(4), output(4)])
        XCTAssertEqual(hex(try tx.transcript()),
                       "11008e0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030030a0acf939f033e3d0ae9b5f784341fada38367eec190edfb34e1f0cce9050c80672dbee77a7512b7243544c85ae290a7304003084d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d0332721004b0100010402002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee21004b0100010402002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee")
        XCTAssertEqual(hex(try tx.digest()), "b5a50082d44bdb0d9f9e91896fbe0f8f9052baf0ca7c8930c8987790164f277c")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(try Transaction.container(tx.inputs[0]))),
                       "900fb575d55eed27f7f52db079a2bf4843e674c461726eca70b90943cb3c7d07")
        let digest = try tx.inputDigest(0)
        XCTAssertEqual(hex(digest), "eca67b680015d42ffb9339b8c0475a90d162d189bd36a15d8b6910de48927edd")
        try assertSignature("5b4b2cbdb5ea75dd2a6451bf2f348e8b837438375dd5e78ba5cb2f3c549258df8ff274e8de9987e7dab88c221f0de820546e42907cec816e2b290af814030a94",
                            digest: digest, k: k0, pubkey: secret0)

        // The signing rule produces exactly this witness from the proof's spend info.
        let signed = try CashuSwift.signV3Inputs([proof(8, secret0, k: k0)], outputs: tx.outputs)
        XCTAssertEqual(try CashuSwift.Proof.Witness(json: try XCTUnwrap(signed[0].witness)),
                       .init(signatures: ["5b4b2cbdb5ea75dd2a6451bf2f348e8b837438375dd5e78ba5cb2f3c549258df8ff274e8de9987e7dab88c221f0de820546e42907cec816e2b290af814030a94"]))
    }

    func testMultipleProofInputs() throws {
        let tx = Transaction(inputs: [.proof(proof(8, secret0, k: k0)), .proof(proof(4, secret1, k: k1))],
                             outputs: [output(8), output(4)])
        XCTAssertEqual(hex(try tx.digest()), "638facdb740dcd6909c5934208a421dafa1b3756aa5fc4a0e5d1bd341f28fbc6")
        let d0 = try tx.inputDigest(0), d1 = try tx.inputDigest(1)
        XCTAssertEqual(hex(d0), "d8fcb88ff0252fc13519cf28a23e7b65278db09a4d8c1e82b27f692ea53bb5a7")
        XCTAssertEqual(hex(d1), "28e4afd844e0fb8a3c3e71fdb82abdecf263d25b4de1cfd96d0d5c620c69c1d1")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(try Transaction.container(tx.inputs[1]))),
                       "0182252f564bf76e42e45514955b50c6bd6381b6c4971c8027cd5a6a90817c4b")
        let sig0 = "11f5af9cf93204f816b4328f47de2b6368eaa26d584c4a5f0eca9268ed94aa39093faad5e6d4fce3674851e3c506cd0af35c0a58f913d7853e51b80e39976499"
        let sig1 = "35482c41545a8a1dd1343678952085390c2ac0a056f28bb36c1623ceadece35181d0526386bc8feb5ab15ba71a608a1a51f4f302ca1e11c903d1255e9d039d0a"
        try assertSignature(sig0, digest: d0, k: k0, pubkey: secret0)
        try assertSignature(sig1, digest: d1, k: k1, pubkey: secret1)
        // Each signature verifies only against its own input digest, never the shared digest.
        XCTAssertFalse(CashuSwift.Crypto.schnorrVerify(digest: d1, signatureHex: sig0, publicKey: try secret0.bytes))
        XCTAssertFalse(CashuSwift.Crypto.schnorrVerify(digest: try tx.digest(), signatureHex: sig0, publicKey: try secret0.bytes))
    }

    func testMixedKeysets() throws {
        let legacy = CashuSwift.Proof(keysetID: "00456a94ab4e1c46", amount: 2,
                                      secret: "d341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6",
                                      C: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2")
        let tx = Transaction(inputs: [.proof(proof(8, secret0, k: k0)), .proof(legacy)], outputs: [output(8), output(2)])
        XCTAssertEqual(try CashuSwift.stateCheckY(for: legacy), "029ef117210f475254efd911de93a9d22d471e356f5b1e3f00df8c24bbb37bd3ae")
        XCTAssertEqual(hex(try Transaction.container(tx.inputs[1])),
                       "1100570100010202000800456a94ab4e1c46030021029ef117210f475254efd911de93a9d22d471e356f5b1e3f00df8c24bbb37bd3ae04002102a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(try Transaction.container(tx.inputs[1]))),
                       "efbdd5d14874cb021fc962d93a9848553ca65ae101e9b57f6678aa37ffe1ebd9")
        XCTAssertEqual(hex(try tx.transcript()),
                       "11008e0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030030a0acf939f033e3d0ae9b5f784341fada38367eec190edfb34e1f0cce9050c80672dbee77a7512b7243544c85ae290a7304003084d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d033271100570100010202000800456a94ab4e1c46030021029ef117210f475254efd911de93a9d22d471e356f5b1e3f00df8c24bbb37bd3ae04002102a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba221004b0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee21004b0100010202002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee")
        XCTAssertEqual(hex(try tx.digest()), "74e13e494841037a8578176a18a25e412ef5b86e35e2de6f0bff5f30f79405b4")
        let d0 = try tx.inputDigest(0)
        XCTAssertEqual(hex(d0), "764a2f46843cdefb389d2cf45807b569d646e51780265e1c28e0ac42cdb067e6")
        try assertSignature("affda39eba371dc7fe506e50ea9e97bea55d24bca91039f399dcbbcc00528c648fb4ba1dcb257851c4bb28e3bb869f2da13232ba539cfc67336276113adad289",
                            digest: d0, k: k0, pubkey: secret0)

        // Only the v3 input gets a witness; the pre-v3 input keeps its own rules.
        let signed = try CashuSwift.signV3Inputs(tx.inputs.compactMap { if case .proof(let p) = $0 { p } else { nil } },
                                                 outputs: tx.outputs)
        XCTAssertNotNil(signed[0].witness)
        XCTAssertNil(signed[1].witness)
    }

    func testMint() throws {
        let tx = Transaction(inputs: [.mintQuote(id: "quote-mint-0001", amount: 8, lockKey: lock0, issued: 0)],
                             outputs: [output(8)])
        XCTAssertEqual(hex(try tx.transcript()),
                       "12003d0100010802000f71756f74652d6d696e742d303030310300210292905560a6a511a13e383ee27e220aeffc85b7a7bc293e6935b1d3678d20981204000021004b0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee")
        XCTAssertEqual(hex(try tx.digest()), "3f2ed71b538ba1cdb59b7d176dae4709c5db6b30d2c364fc231bfd2985d9f845")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(try Transaction.container(tx.inputs[0]))),
                       "d294012dd54976b05eb3e36eb218b9a6d66b19d79ec122944a35b99b8ddd8839")
        XCTAssertEqual(hex(try tx.inputDigest(0)), "cd149490f31c836c3f4bab5e401242100a1522e7e5e0af2db4da4020bb894af1")
    }

    func testPartialMint() throws {
        let tx = Transaction(inputs: [.mintQuote(id: "quote-mint-0004", amount: 4, lockKey: lock0, issued: 3)],
                             outputs: [output(4)])
        XCTAssertEqual(hex(try tx.transcript()),
                       "12003e0100010402000f71756f74652d6d696e742d303030340300210292905560a6a511a13e383ee27e220aeffc85b7a7bc293e6935b1d3678d2098120400010321004b0100010402002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee")
        XCTAssertEqual(hex(try tx.digest()), "93379041ba7dd1166d7dc1b028305a22470c461f62907982565a2343148cb64b")
        let digest = try tx.inputDigest(0)
        XCTAssertEqual(hex(digest), "3e22290842db64b0c8417b72e16bf0965d5ee304815978d3b8c2d53574a60ebb")
        let sig = "5055a075e7534502457e914c81768d29bae3d0be046d106a8a6529507c3bdc851cbecd9654454d22efe88658803d4a96d8c2ba53716b9846da08411fbabf71de"
        try assertSignature(sig, digest: digest, k: quoteKey0, pubkey: lock0)
        // The signature MUST NOT verify over a transcript committing amount 8 or issued 0.
        let other = Transaction(inputs: [.mintQuote(id: "quote-mint-0004", amount: 8, lockKey: lock0, issued: 0)],
                                outputs: [output(4)])
        XCTAssertFalse(CashuSwift.Crypto.schnorrVerify(digest: try other.inputDigest(0), signatureHex: sig, publicKey: try lock0.bytes))
    }

    func testBatchedMint() throws {
        let tx = Transaction(inputs: [.mintQuote(id: "quote-mint-0002", amount: 5, lockKey: lock0, issued: 0),
                                      .mintQuote(id: "quote-mint-0003", amount: 3, lockKey: lock1, issued: 0)],
                             outputs: [output(8)])
        XCTAssertEqual(hex(try tx.transcript()),
                       "12003d0100010502000f71756f74652d6d696e742d303030320300210292905560a6a511a13e383ee27e220aeffc85b7a7bc293e6935b1d3678d20981204000012003d0100010302000f71756f74652d6d696e742d3030303303002102b357c1ec7bdd73e4ede25d68619ee607c632409e89bcc518a82370b3f499615d04000021004b0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee")
        XCTAssertEqual(hex(try tx.digest()), "bf866b675bf6730b94f556095a22f4ac094fb3fe5d65d777dd05a41ebfb6f4ed")
        let d0 = try tx.inputDigest(0), d1 = try tx.inputDigest(1)
        XCTAssertEqual(hex(d0), "dbc45733112ba2e7fad938d62de00c13c085309c9330d082cadee0c6dfeca85f")
        XCTAssertEqual(hex(d1), "f14225ec0ff74cae090865a5d852b9cd8b06827d3f459ad2d6a5ce4cc1e91dac")
        try assertSignature("e0520f39e881481c7f6f12f987d09483c14b4bb3fbeea8f35d238f53bf0448be53db93f3a61ab882e50c8a96d26a87f48ded963ff5a585e404834f8c13b00e20",
                            digest: d0, k: quoteKey0, pubkey: lock0)
        try assertSignature("e726ee0cef6b2431850f4f5f7b5745d8810ead54888db3aae12c30d151049810c72dbe9f3d07812719fd1e2c8d55df91cec1e9a81e8cfe557485cefcb4e6447f",
                            digest: d1, k: quoteKey1, pubkey: lock1)
    }

    func testMeltAndMeltWithChange() throws {
        let melt = Transaction(inputs: [.proof(proof(8, secret0, k: k0))],
                               outputs: [.meltQuote(id: "quote-melt-0001", amount: 8)])
        XCTAssertEqual(hex(try melt.transcript()),
                       "11008e0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030030a0acf939f033e3d0ae9b5f784341fada38367eec190edfb34e1f0cce9050c80672dbee77a7512b7243544c85ae290a7304003084d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d033272200160100010802000f71756f74652d6d656c742d30303031")
        XCTAssertEqual(hex(try melt.digest()), "1b9e4e88ad05d873bee5b00a3d621e9a6565bb611a27174dfc17d268dffd38c2")
        XCTAssertEqual(hex(try melt.inputDigest(0)), "5319b114091bd127f42fd209b4b363d13a145da174c534fb8fa4c584a8405c0f")

        // Blank outputs (amount 0 encodes as `010000`) precede the melt quote even when listed after it.
        let withChange = Transaction(inputs: [.proof(proof(8, secret0, k: k0))],
                                     outputs: [.meltQuote(id: "quote-melt-0001", amount: 8), output(0), output(0)])
        XCTAssertEqual(hex(try withChange.transcript()),
                       "11008e0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030030a0acf939f033e3d0ae9b5f784341fada38367eec190edfb34e1f0cce9050c80672dbee77a7512b7243544c85ae290a7304003084d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d0332721004a01000002002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee21004a01000002002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee2200160100010802000f71756f74652d6d656c742d30303031")
        XCTAssertEqual(hex(try withChange.digest()), "adac16b768b73d5137096faf62a1b3b035cb8fd27e2a22c3159d99d1f2415c60")
        XCTAssertEqual(hex(try withChange.inputDigest(0)), "c5692db35c58c47c70aa4dab49d2ede41adec95f00a231bf40cc8af5ddee030f")

        // The melt shares the swap's input_id but not its input_digest: neither witness crosses over.
        let swap = Transaction(inputs: [.proof(proof(8, secret0, k: k0))], outputs: [output(4), output(4)])
        let swapSig = try CashuSwift.Crypto.schnorrSign(digest: try swap.inputDigest(0), key: try key(k0))
        XCTAssertFalse(CashuSwift.Crypto.schnorrVerify(digest: try melt.inputDigest(0), signatureHex: swapSig, publicKey: try secret0.bytes))
    }

    func testTLVIntegerRules() throws {
        XCTAssertEqual(CashuSwift.TLV.minimalBE(0), [])
        XCTAssertEqual(CashuSwift.TLV.minimalBE(256), [0x01, 0x00])
        XCTAssertEqual(try CashuSwift.TLV.integer([]), 0)
        XCTAssertThrowsError(try CashuSwift.TLV.integer([0x00, 0x01]), "leading zero is non-canonical")
        XCTAssertEqual(CashuSwift.TLV.keysetIDBytes("00456a94ab4e1c46"), try "00456a94ab4e1c46".bytes)
        XCTAssertEqual(CashuSwift.TLV.keysetIDBytes("abc"), Array("abc".utf8))
        XCTAssertEqual(CashuSwift.TLV.keysetIDBytes("ABCD"), Array("ABCD".utf8), "uppercase is not hex here")
        XCTAssertThrowsError(try Transaction(inputs: [], outputs: [output(1)]).transcript())
    }
}
