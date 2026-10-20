import XCTest
import secp256k1
@testable import CashuSwift

/// NUT-28 slot-map vectors (tests/28) and NUT-18 nutroot locking vectors (tests/18).
final class NutrootLockingTests: XCTestCase {

    typealias Nutroot = CashuSwift.Nutroot
    typealias P2BK = CashuSwift.Crypto.P2BK

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func scalar(_ n: UInt8) -> String { String(repeating: "0", count: 62) + String(format: "%02x", n) }
    private func priv(_ n: UInt8) throws -> secp256k1.Signing.PrivateKey { try .init(dataRepresentation: try scalar(n).bytes) }

    let key3 = "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
    let key4 = "02e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"
    let key5 = "022f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4"
    let afterLeaf = "00020200010104002102e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd1306000468a3be80"
    let blindedLeaf = "000202000101040021039ca57991c48db95252bff61e02c31cf9b1e9ec2ef27d9dee33db6f0324e6ca8106000468a3be80"
    let slot0Blinded = "03a3e12cc077e5605f36441046f50c114fcc883b079a34028bed66732e3a419e51"
    let slot1Blinded = "039ca57991c48db95252bff61e02c31cf9b1e9ec2ef27d9dee33db6f0324e6ca81"
    let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"

    func testSlotMapVectors() throws {
        let e = try priv(5)
        let sharedX = try P2BK.sharedX(scalar: e, point: try CashuSwift.Crypto.nut20PublicKey(key3))
        XCTAssertEqual(hex(Array(try P2BK.blindingScalar(sharedX: sharedX, slot: 0).dataRepresentation)),
                       "7dfb649b0edda814f7cf0feb889e5657eb2083a528aa60a3a943fe0cea066181")
        XCTAssertEqual(hex(Array(try P2BK.blind(try CashuSwift.Crypto.nut20PublicKey(key3), ephemeral: e, slot: 0).dataRepresentation)), slot0Blinded)
        XCTAssertEqual(hex(Array(try P2BK.blind(try CashuSwift.Crypto.nut20PublicKey(key4), ephemeral: e, slot: 1).dataRepresentation)), slot1Blinded)
        let leaf = try Nutroot.Leaf.parse(hex: afterLeaf)
        XCTAssertEqual(try Nutroot.Leaf(kind: leaf.kind, n: leaf.n, keys: [slot1Blinded], time: leaf.time).serializedHex(), blindedLeaf)

        // The owner of key 4 recovers its slot-1 key by value; key 3 is not at slot 1.
        let E = e.publicKey
        let owner4 = try XCTUnwrap(try P2BK.unblind(try CashuSwift.Crypto.nut20PublicKey(slot1Blinded), receiverKey: try priv(4), ephemeral: E, slot: 1))
        XCTAssertEqual(hex(Array(owner4.publicKey.dataRepresentation)), slot1Blinded)
        XCTAssertNil(try P2BK.unblind(try CashuSwift.Crypto.nut20PublicKey(slot1Blinded), receiverKey: try priv(3), ephemeral: E, slot: 1))
        XCTAssertNil(try P2BK.unblind(try CashuSwift.Crypto.nut20PublicKey(slot1Blinded), receiverKey: try priv(4), ephemeral: E, slot: 2))
    }

    func testNutrootRequestDecodesAndRoundTrips() throws {
        let encoded = "creqAo2FhCGF1Y3NhdGdudXRyb290o2FreEIwMjUwOTI5Yjc0YzFhMDQ5NTRiNzhiNGI2MDM1ZTk3YTVlMDc4YTVhMGYyOGVjOTZkNTQ3YmZlZTlhY2U4MDNhYzBhbIF4YjAwMDIwMjAwMDEwMTA0MDAyMTAyZTQ5M2RiZjFjMTBkODBmMzU4MWU0OTA0OTMwYjE0MDRjYzZjMTM5MDBlZTA3NTg0NzRmYTk0YWJlOGM0Y2QxMzA2MDAwNDY4YTNiZTgwYWKBeEIwMmU0OTNkYmYxYzEwZDgwZjM1ODFlNDkwNDkzMGIxNDA0Y2M2YzEzOTAwZWUwNzU4NDc0ZmE5NGFiZThjNGNkMTM="
        let request = try CashuSwift.PaymentRequest(encodedRequest: encoded)
        XCTAssertEqual(request.amount, 8)
        XCTAssertEqual(request.unit, "sat")
        XCTAssertEqual(request.nutroot, .init(k: Nutroot.numsPoint, l: [afterLeaf], b: [key4]))
        let again = try CashuSwift.PaymentRequest(encodedRequest: try request.serialize())
        XCTAssertEqual(again, request)

        let json = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(CashuSwift.PaymentRequest.self, from: json), request)
        XCTAssertTrue(String(data: json, encoding: .utf8)!.contains("\"nutroot\""))

        XCTAssertThrowsError(try CashuSwift.NutrootOption(k: key3, l: [afterLeaf], b: [key3]).validate(), "blind-me key not in any leaf")
        XCTAssertThrowsError(try CashuSwift.NutrootOption(k: "00", l: nil, b: nil).validate(), "k must be a point")
    }

    func testNumsRequestVectors() throws {
        // Paying with ephemeral 5 and u = 7 blinds the leaf key at slot 1.
        let e = try priv(5)
        let K7 = try Nutroot.numsInternalKey(offset: try priv(7))
        XCTAssertEqual(hex(Array(K7.dataRepresentation)), "028edfebd6fdea3e1d89359af20868a2e76315b36cdb1a79de497a1757ca7bd407")
        let leaf = try Nutroot.Leaf.parse(hex: afterLeaf)
        let blinded = try Nutroot.Leaf(kind: leaf.kind, n: leaf.n,
                                       keys: [hex(Array(try P2BK.blind(try CashuSwift.Crypto.nut20PublicKey(key4), ephemeral: e, slot: 1).dataRepresentation))],
                                       time: leaf.time).serializedHex()
        XCTAssertEqual(blinded, blindedLeaf)
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K7, leaves: [try blindedLeaf.bytes]).dataRepresentation)),
                       "02fb23814e330739413a6e3982a21916002962002bc101ac105a28e0cf3bcb46d1")
        let proof7 = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: "02fb23814e330739413a6e3982a21916002962002bc101ac105a28e0cf3bcb46d1", C: "",
                                      spendInfo: .init(E: key5, K: "028edfebd6fdea3e1d89359af20868a2e76315b36cdb1a79de497a1757ca7bd407",
                                                       tree: [blindedLeaf], u: scalar(7)))
        XCTAssertNil(try Nutroot.resolve(proof7).keyPathKey, "script-only")

        // Without `b` nothing is blinded: no ephemeral, leaf verbatim, u = 9.
        let K9 = try Nutroot.numsInternalKey(offset: try priv(9))
        XCTAssertEqual(hex(Array(K9.dataRepresentation)), "03b948fab26606a34380c4515ece4c27d25fcf53eb95d1041630ab44f2be4f7331")
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K9, leaves: [try afterLeaf.bytes]).dataRepresentation)),
                       "030b5dc180dd2ef76be0f0319fc5c254511fede8c8563a823d3b0fcd6f9012a0b2")
        let proof9 = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: "030b5dc180dd2ef76be0f0319fc5c254511fede8c8563a823d3b0fcd6f9012a0b2", C: "",
                                      spendInfo: .init(K: "03b948fab26606a34380c4515ece4c27d25fcf53eb95d1041630ab44f2be4f7331", tree: [afterLeaf], u: scalar(9)))
        XCTAssertNil(try Nutroot.resolve(proof9).keyPathKey)

        // Payload validation: the disclosed tree must be the requested one and E presence must agree.
        let withB = CashuSwift.PaymentRequest(paymentId: nil, amount: 8, unit: "sat", singleUse: nil, mints: nil, description: nil,
                                              transports: nil, lockingCondition: nil,
                                              nutroot: .init(k: Nutroot.numsPoint, l: [afterLeaf], b: [key4]))
        let withoutB = CashuSwift.PaymentRequest(paymentId: nil, amount: 8, unit: "sat", singleUse: nil, mints: nil, description: nil,
                                                 transports: nil, lockingCondition: nil,
                                                 nutroot: .init(k: Nutroot.numsPoint, l: [afterLeaf]))
        let payload7 = CashuSwift.PaymentRequestPayload(id: nil, memo: nil, mint: "https://mint.test", unit: "sat", proofs: [proof7])
        let payload9 = CashuSwift.PaymentRequestPayload(id: nil, memo: nil, mint: "https://mint.test", unit: "sat", proofs: [proof9])
        XCTAssertNoThrow(try payload7.validates(against: withB))
        XCTAssertNoThrow(try payload9.validates(against: withoutB))
        XCTAssertThrowsError(try payload7.validates(against: withoutB), "E must be absent when nothing is blinded")
        XCTAssertThrowsError(try payload9.validates(against: withB), "E must be present when a key is blinded")
    }

    func testReceiverKeyedOutputsFollowTheRequest() throws {
        let option = CashuSwift.NutrootOption(k: key3, l: [afterLeaf], b: [key4])
        let outputs = try Nutroot.receiverKeyedOutputs(amounts: [4, 2], keysetID: keysetID, option: option)
        XCTAssertEqual(outputs.count, 2)
        XCTAssertNotEqual(outputs[0].secret, outputs[1].secret, "fresh ephemeral per output")
        for o in outputs {
            XCTAssertEqual(o.output.B_.count, 96)
            XCTAssertEqual(o.spendInfo.tree?.count, 1)
            XCTAssertNotEqual(o.spendInfo.tree?.first, afterLeaf, "slot 1 is blinded in place")
            XCTAssertNotNil(o.spendInfo.E)
            XCTAssertNil(o.spendInfo.u)
            let proof = CashuSwift.Proof(keysetID: keysetID, amount: o.output.amount, secret: o.secret, C: "", spendInfo: o.spendInfo)
            // Carol (key 3) resolves the key path; Alice (key 4) finds her blinded leaf key by value.
            XCTAssertNotNil(try Nutroot.resolve(proof, receiverKey: try priv(3)).keyPathKey)
            XCTAssertThrowsError(try Nutroot.resolve(proof, receiverKey: try priv(4)))
            let leaf = try Nutroot.Leaf.parse(hex: try XCTUnwrap(o.spendInfo.tree?.first))
            let E = try CashuSwift.Crypto.nut20PublicKey(try XCTUnwrap(o.spendInfo.E))
            XCTAssertNotNil(try P2BK.unblind(try CashuSwift.Crypto.nut20PublicKey(leaf.keys[0]), receiverKey: try priv(4), ephemeral: E, slot: 1))
            let payload = CashuSwift.PaymentRequestPayload(id: nil, memo: nil, mint: "https://mint.test", unit: "sat", proofs: [proof])
            let request = CashuSwift.PaymentRequest(paymentId: nil, amount: nil, unit: "sat", singleUse: nil, mints: nil, description: nil,
                                                    transports: nil, lockingCondition: nil, nutroot: option)
            XCTAssertNoThrow(try payload.validates(against: request))
        }

        // Plain derived outputs (no leaves) carry only E, and a NUMS request needs leaves.
        let plain = try Nutroot.receiverKeyedOutputs(amounts: [1], keysetID: keysetID, option: .init(k: key3))
        XCTAssertEqual(plain[0].spendInfo, .init(E: plain[0].spendInfo.E))
        XCTAssertThrowsError(try Nutroot.receiverKeyedOutputs(amounts: [1], keysetID: keysetID, option: .init(k: Nutroot.numsPoint)))
        let nums = try Nutroot.receiverKeyedOutputs(amounts: [1], keysetID: keysetID, option: .init(k: Nutroot.numsPoint, l: [afterLeaf]))
        XCTAssertNil(nums[0].spendInfo.E)
        XCTAssertNotNil(nums[0].spendInfo.u)
        XCTAssertEqual(nums[0].spendInfo.tree, [afterLeaf])
    }
}
