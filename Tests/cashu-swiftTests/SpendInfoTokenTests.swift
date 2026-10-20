import XCTest
import secp256k1
@testable import CashuSwift

/// NUT-00 "V4 tokens with spend info" vectors and the witness-stripping rule.
final class SpendInfoTokenTests: XCTestCase {

    let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"
    let C = "84d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d03327"
    let leaf = "00020200010104002102e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd1306000468a3be80"

    struct Vector { let secret: String; let spendInfo: CashuSwift.SpendInfo; let token: String }

    lazy var vectors = [
        Vector(secret: "02e6e7cfa7b82d4b3b449fa6466c893469a727d0214d48db4956a6054b8022a29b",
               spendInfo: .init(k: "47196dc081150ce13fd0e478b8b71831b825be389211c9c56a8062a61af70347"),
               token: "cashuBo2FtcWh0dHBzOi8vbWludC50ZXN0YXVjc2F0YXSBomFpSAK34HfQIPq-YXCBpGFhCGFzeEIwMmU2ZTdjZmE3YjgyZDRiM2I0NDlmYTY0NjZjODkzNDY5YTcyN2QwMjE0ZDQ4ZGI0OTU2YTYwNTRiODAyMmEyOWJhY1gwhNG3KRrlc388hRqjPK_g96_rXMtNoIbEgruFt1JeYVR_G1ptGgGx_tH5YNGp0DMnYnNpoWFrWCBHGW3AgRUM4T_Q5Hi4txgxuCW-OJIRycVqgGKmGvcDRw"),
        Vector(secret: "03a3e12cc077e5605f36441046f50c114fcc883b079a34028bed66732e3a419e51",
               spendInfo: .init(E: "022f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4"),
               token: "cashuBo2FtcWh0dHBzOi8vbWludC50ZXN0YXVjc2F0YXSBomFpSAK34HfQIPq-YXCBpGFhCGFzeEIwM2EzZTEyY2MwNzdlNTYwNWYzNjQ0MTA0NmY1MGMxMTRmY2M4ODNiMDc5YTM0MDI4YmVkNjY3MzJlM2E0MTllNTFhY1gwhNG3KRrlc388hRqjPK_g96_rXMtNoIbEgruFt1JeYVR_G1ptGgGx_tH5YNGp0DMnYnNpoWFlWCECL4veTRoHIJNVtKclClxRKOiLhL3cYZq3y6jVabJA7-Q"),
        Vector(secret: "02d310a4d661e3158e7d360617e739d6bacbf015431b24a43168db0ab99ef8f828",
               spendInfo: .init(E: "022f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4", tree: [leaf]),
               token: "cashuBo2FtcWh0dHBzOi8vbWludC50ZXN0YXVjc2F0YXSBomFpSAK34HfQIPq-YXCBpGFhCGFzeEIwMmQzMTBhNGQ2NjFlMzE1OGU3ZDM2MDYxN2U3MzlkNmJhY2JmMDE1NDMxYjI0YTQzMTY4ZGIwYWI5OWVmOGY4MjhhY1gwhNG3KRrlc388hRqjPK_g96_rXMtNoIbEgruFt1JeYVR_G1ptGgGx_tH5YNGp0DMnYnNpomFlWCECL4veTRoHIJNVtKclClxRKOiLhL3cYZq3y6jVabJA7-RhdIFYMQACAgABAQQAIQLkk9vxwQ2A81geSQSTCxQEzGwTkA7gdYR0-pSr6MTNEwYABGijvoA"),
        Vector(secret: "02d310a4d661e3158e7d360617e739d6bacbf015431b24a43168db0ab99ef8f828",
               spendInfo: .init(K: "03a3e12cc077e5605f36441046f50c114fcc883b079a34028bed66732e3a419e51", tree: [leaf]),
               token: "cashuBo2FtcWh0dHBzOi8vbWludC50ZXN0YXVjc2F0YXSBomFpSAK34HfQIPq-YXCBpGFhCGFzeEIwMmQzMTBhNGQ2NjFlMzE1OGU3ZDM2MDYxN2U3MzlkNmJhY2JmMDE1NDMxYjI0YTQzMTY4ZGIwYWI5OWVmOGY4MjhhY1gwhNG3KRrlc388hRqjPK_g96_rXMtNoIbEgruFt1JeYVR_G1ptGgGx_tH5YNGp0DMnYnNpomFpWCEDo-EswHflYF82RBBG9QwRT8yIOweaNAKL7WZzLjpBnlFhdIFYMQACAgABAQQAIQLkk9vxwQ2A81geSQSTCxQEzGwTkA7gdYR0-pSr6MTNEwYABGijvoA"),
        Vector(secret: "0251a4f35fa38c5edce83e16596de02be4e87ec6a91c5fd80ab577c22668fb6dd5",
               spendInfo: .init(K: "0308ca9ef021bf7ec241dbef7fa31aec8e63b41be200eb7530cd3d67d2a2c7d096", tree: [leaf],
                                u: "4af68649f3230c5589879f0cf33fd6d9f007cd3a54a2e6ed8699a576630fc025"),
               token: "cashuBo2FtcWh0dHBzOi8vbWludC50ZXN0YXVjc2F0YXSBomFpSAK34HfQIPq-YXCBpGFhCGFzeEIwMjUxYTRmMzVmYTM4YzVlZGNlODNlMTY1OTZkZTAyYmU0ZTg3ZWM2YTkxYzVmZDgwYWI1NzdjMjI2NjhmYjZkZDVhY1gwhNG3KRrlc388hRqjPK_g96_rXMtNoIbEgruFt1JeYVR_G1ptGgGx_tH5YNGp0DMnYnNpo2FpWCEDCMqe8CG_fsJB2-9_oxrsjmO0G-IA63UwzT1n0qLH0JZhdVggSvaGSfMjDFWJh58M8z_W2fAHzTpUoubthpmldmMPwCVhdIFYMQACAgABAQQAIQLkk9vxwQ2A81geSQSTCxQEzGwTkA7gdYR0-pSr6MTNEwYABGijvoA"),
    ]

    func testV4SpendInfoVectorsDecodeAndRoundTrip() throws {
        for (i, v) in vectors.enumerated() {
            let token = try (v.token).deserializeToken()
            let proof = try XCTUnwrap(token.proofsByMint["https://mint.test"]?.first, "vector \(i)")
            XCTAssertEqual(token.unit, "sat")
            XCTAssertEqual(proof.amount, 8)
            XCTAssertEqual(proof.keysetID, String(keysetID.prefix(16)))
            XCTAssertEqual(proof.secret, v.secret, "vector \(i)")
            XCTAssertEqual(proof.C, C)
            XCTAssertEqual(proof.spendInfo, v.spendInfo, "vector \(i)")
            XCTAssertNoThrow(try proof.spendInfo?.validateShape())

            // shortcut: CBOR map key order is not canonical in SwiftCBOR, so compare decoded
            // values instead of bytes; upgrade to byte-identical once encoding is ordered.
            let again = try (try token.serialize(to: .V4)).deserializeToken()
            XCTAssertEqual(again, token, "vector \(i) V4 round trip")
            XCTAssertEqual(again.proofsByMint["https://mint.test"]?.first?.spendInfo, v.spendInfo, "vector \(i) V4 round trip")
            let viaV3 = try (try token.serialize(to: .V3)).deserializeToken()
            XCTAssertEqual(viaV3.proofsByMint["https://mint.test"]?.first?.spendInfo, v.spendInfo, "vector \(i) V3 round trip")
        }
    }

    func testSpendInfoShapeRules() {
        XCTAssertThrowsError(try CashuSwift.SpendInfo(k: "00", E: "00").validateShape())
        XCTAssertThrowsError(try CashuSwift.SpendInfo(k: "00", tree: []).validateShape())
        XCTAssertThrowsError(try CashuSwift.SpendInfo(tree: [leaf]).validateShape(), "a tree needs a key source")
        XCTAssertThrowsError(try CashuSwift.SpendInfo(K: "00", u: "00").validateShape(), "u needs a tree")
        XCTAssertNoThrow(try CashuSwift.SpendInfo(K: "00", tree: [leaf], u: "00").validateShape())
    }

    func testWitnessIsDroppedFromTokens() throws {
        let proof = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: vectors[0].secret, C: C,
                                     witness: #"{"signatures":["00"]}"#, spendInfo: vectors[0].spendInfo)
        let token = CashuSwift.Token(proofs: ["https://mint.test": [proof]], unit: "sat")
        for version in [CashuSwift.TokenVersion.V3, .V4] {
            let decoded = try (try token.serialize(to: version)).deserializeToken()
            let p = try XCTUnwrap(decoded.proofsByMint["https://mint.test"]?.first)
            XCTAssertNil(p.witness)
            XCTAssertEqual(p.spendInfo, vectors[0].spendInfo)
        }
        // A hand-made V3 token string carrying a witness loses it on decode too.
        let json = #"{"token":[{"mint":"https://mint.test","proofs":[{"id":"\#(keysetID)","amount":8,"secret":"\#(vectors[0].secret)","C":"\#(C)","witness":"{\"signatures\":[\"00\"]}","spend_info":{"k":"47196dc081150ce13fd0e478b8b71831b825be389211c9c56a8062a61af70347"}}]}],"unit":"sat"}"#
        let decoded = try ("cashuA" + Data(json.utf8).base64URLsafe).deserializeToken()
        let p = try XCTUnwrap(decoded.proofsByMint["https://mint.test"]?.first)
        XCTAssertNil(p.witness)
        XCTAssertEqual(p.spendInfo?.k, "47196dc081150ce13fd0e478b8b71831b825be389211c9c56a8062a61af70347")
    }

    func testWireProofsCarryNoSpendInfo() throws {
        let proof = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: vectors[0].secret, C: C,
                                     witness: "w", spendInfo: vectors[0].spendInfo)
        let wire = CashuSwift.stripDLEQ([proof])[0]
        XCTAssertNil(wire.spendInfo)
        XCTAssertEqual(wire.witness, "w")
        let json = String(data: try JSONEncoder().encode(wire), encoding: .utf8)!
        XCTAssertFalse(json.contains("spend_info"))
    }
}
