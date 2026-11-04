import XCTest
import secp256k1
@testable import CashuSwift

/// NUT-10 nutroot vectors (nuts tests/10): leaves, the tree fold, tweaks, key-path and
/// script-path witnesses, rejection vectors and the empty tweak.
final class NutrootTests: XCTestCase {

    typealias Nutroot = CashuSwift.Nutroot
    typealias Leaf = CashuSwift.Nutroot.Leaf

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func scalar(_ n: UInt8) -> String { String(repeating: "0", count: 62) + String(format: "%02x", n) }
    private func priv(_ n: UInt8) throws -> secp256k1.Signing.PrivateKey { try .init(dataRepresentation: try scalar(n).bytes) }
    private func schnorr(_ hex: String) throws -> secp256k1.Schnorr.PrivateKey { try .init(dataRepresentation: try hex.bytes) }

    let key3 = "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
    let key4 = "02e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"
    let key5 = "022f8bde4d1a07209355b4a7250a5c5128e88b84bddc619ab7cba8d569b240efe4"
    let key6 = "03fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a1460297556"
    let key7 = "025cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39ce92bddedcac4f9bc"

    let threshold1of1Key3 = "00010200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
    let threshold2of2Keys34 = "00010200010204004202f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f902e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"
    let hashlockHash = "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
    let hashlock1of1Key3 = "00030200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9080020a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
    let after1of1Key4 = "00020200010104002102e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd1306000468a3be80"
    let illustrativeDigest = "e1d7170b89a2b6eedec90453e32b6c320dfadd590e6a6454bddec95a0e3834cd"

    func testTagHashes() {
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(Array("Cashu_NutrootLeaf".utf8))), "e19ba80c5d6798399efd68b1d3b0e7ad57e79a2777310a9e6334934ee7a0b52b")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(Array("Cashu_NutrootBranch".utf8))), "f54194fd19dabbcca1474f329fe5ec065fc54d94063d14ae820788ba5bd8e55e")
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(Array("Cashu_NutrootTweak".utf8))), "cc14d6872e6d0bc79a3dadb4c43f9362916bb6df512126dda139e65b812facd1")
    }

    func testSerializedLeaves() throws {
        XCTAssertEqual(try Leaf.threshold(n: 1, keys: [key3]).serializedHex(), threshold1of1Key3)
        XCTAssertEqual(try Leaf.threshold(n: 2, keys: [key3, key4]).serializedHex(), threshold2of2Keys34)
        XCTAssertEqual(try Leaf.hashlock(hashlockHash, n: 1, keys: [key3]).serializedHex(), hashlock1of1Key3)
        XCTAssertEqual(try Leaf.after(1755561600, n: 1, keys: [key4]).serializedHex(), after1of1Key4)
        for leafHex in [threshold1of1Key3, threshold2of2Keys34, hashlock1of1Key3, after1of1Key4] {
            XCTAssertEqual(try Leaf.parse(hex: leafHex).serializedHex(), leafHex)
        }
        let after = try Leaf.parse(hex: after1of1Key4)
        XCTAssertEqual(after.kind, .after)
        XCTAssertEqual(after.n, 1)
        XCTAssertEqual(after.keys, [key4])
        XCTAssertEqual(after.time, 1755561600)
    }

    func testThreeLeafFoldAndPath() throws {
        let tree = [threshold1of1Key3, after1of1Key4, hashlock1of1Key3]
        XCTAssertEqual(try Nutroot.root(leaves: tree), "3d4fbecf46f5c716d7cebd48863f3c4ab89e675e3beb4b3a28f3bd13b49d43ad")
        let path = try Nutroot.merklePath(leaves: tree, index: 2)
        XCTAssertEqual(path, ["23e8ff1693496ecad495b7ed3cdd7f8595c52a3adc0b92475835b0fb839116cb",
                              "9ed9c0b8907f7af4fce51cbeac218907bbf80ba40f3342df2406bce30616589a"])
        XCTAssertEqual(hex(try Nutroot.rootFrom(leaf: try hashlock1of1Key3.bytes, path: try path.map { try $0.bytes })),
                       "3d4fbecf46f5c716d7cebd48863f3c4ab89e675e3beb4b3a28f3bd13b49d43ad")
        let K = try CashuSwift.Crypto.nut20PublicKey("03a3e12cc077e5605f36441046f50c114fcc883b079a34028bed66732e3a419e51")
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K, leaves: try tree.map { try $0.bytes }).dataRepresentation)),
                       "022d17fddb224e53e12b40c58ab3e8828d08931640105c52fc4eaf765ed51b9999")
        // A permuted tree folds to the same root.
        XCTAssertEqual(try Nutroot.root(leaves: tree.reversed()), try Nutroot.root(leaves: tree))
    }

    func testDuplicateLeavesAreNotDeduplicated() throws {
        let tree = [threshold1of1Key3, threshold1of1Key3]
        let leafHash = "23e8ff1693496ecad495b7ed3cdd7f8595c52a3adc0b92475835b0fb839116cb"
        XCTAssertEqual(hex(Nutroot.leafHash(try threshold1of1Key3.bytes)), leafHash)
        XCTAssertEqual(try Nutroot.root(leaves: tree), "1eaf291448e2f3c3a4fc00bfd591917bbb807e63af0fb905d054002bddd2cbc6")
        XCTAssertEqual(try Nutroot.merklePath(leaves: tree, index: 0), [leafHash])
        XCTAssertEqual(try Nutroot.merklePath(leaves: tree, index: 1), [leafHash])
        let K = try CashuSwift.Crypto.nut20PublicKey(key6)
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K, leaves: try tree.map { try $0.bytes }).dataRepresentation)),
                       "03dd2f11ab23b670222ada50325b5d49cd07e1d7a721d9b52fa2039df1f1b0dbfd")
    }

    func testReceiverKeyedProofWithRefundLeaf() throws {
        let internalKey = "03a3e12cc077e5605f36441046f50c114fcc883b079a34028bed66732e3a419e51"
        let secret = "02d310a4d661e3158e7d360617e739d6bacbf015431b24a43168db0ab99ef8f828"
        let keypathPriv = "31b2e906239bae65b2d23718a037877b46a91b0b92f99fe8a899725f78d008e7"
        let leaves = [try after1of1Key4.bytes]
        XCTAssertEqual(try Nutroot.root(leaves: [after1of1Key4]), "9ed9c0b8907f7af4fce51cbeac218907bbf80ba40f3342df2406bce30616589a")
        let K = try CashuSwift.Crypto.nut20PublicKey(internalKey)
        XCTAssertEqual(hex(Nutroot.tweak(internalKey: Array(K.dataRepresentation), root: try "9ed9c0b8907f7af4fce51cbeac218907bbf80ba40f3342df2406bce30616589a".bytes)),
                       "b3b7846b14be0650bb03272d179931221637744d1997df80bf27d2df5effe8a4")
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K, leaves: leaves).dataRepresentation)), secret)

        // Carol's slot-0 key from ephemeral 5: k' = 3 + r_0, which tweaks to keypath_priv.
        let E = try priv(5).publicKey
        let carol = try XCTUnwrap(try CashuSwift.Crypto.P2BK.unblind(K, receiverKey: try priv(3), ephemeral: E, slot: 0))
        XCTAssertEqual(hex(Array(carol.publicKey.dataRepresentation)), internalKey)
        let keyPath = try Nutroot.keyPathPrivateKey(k: carol, leaves: leaves)
        XCTAssertEqual(hex(Array(keyPath.dataRepresentation)), keypathPriv)

        // Key-path witness over the illustrative digest.
        let digest = try illustrativeDigest.bytes
        let keyPathSig = "619e0726595b5adff06cc3e6ea1c409f10f7b064cf8888f0eed0efbac854eabf4632642930bdc7c4d7d983379301a4f263991dbd19d96e5ebcfab9e8583bd510"
        XCTAssertEqual(try CashuSwift.Crypto.schnorrSign(digest: digest, key: try schnorr(keypathPriv)), keyPathSig)
        XCTAssertTrue(CashuSwift.Crypto.schnorrVerify(digest: digest, signatureHex: keyPathSig, publicKey: try secret.bytes))

        // Alice's script-path witness after the locktime.
        let scriptSig = "0b2ea247bfca1264db86907aef4cb19935ed9a5b2043a757259dcdb5c599372c230602f2cfc0cd8b11aa98ff17fbed91f38f07db817263fcc7c50c846715873e"
        let witness = try Nutroot.scriptPathWitness(internalKey: internalKey, leaves: [after1of1Key4], leafIndex: 0,
                                                    inputDigest: digest, keys: [try schnorr(scalar(4))])
        XCTAssertEqual(witness, .init(signatures: [scriptSig], leaf: after1of1Key4, control: .init(K: internalKey, path: [])))
        XCTAssertNoThrow(try Nutroot.verifyScriptPath(witness, secret: secret, inputDigest: digest, now: 1755561600))
        XCTAssertThrowsError(try Nutroot.verifyScriptPath(witness, secret: secret, inputDigest: digest, now: 1755561599), "locktime")
        var doubled = witness
        doubled.signatures = [scriptSig, scriptSig]
        XCTAssertThrowsError(try Nutroot.verifyScriptPath(doubled, secret: secret, inputDigest: digest, now: 1755561600),
                             "more signatures than listed keys")

        // The same proof as spend info: the E-keyed shape resolves for Carol only, the K-disclosed
        // shape resolves without a key path.
        let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"
        let eKeyed = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: secret, C: "",
                                      spendInfo: .init(E: key5, tree: [after1of1Key4]))
        XCTAssertThrowsError(try Nutroot.resolve(eKeyed))
        XCTAssertThrowsError(try Nutroot.resolve(eKeyed, receiverKey: try priv(4)))
        let resolved = try Nutroot.resolve(eKeyed, receiverKey: try priv(3))
        XCTAssertEqual(hex(Array(try XCTUnwrap(resolved.keyPathKey).dataRepresentation)), keypathPriv)
        let disclosed = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: secret, C: "",
                                         spendInfo: .init(K: internalKey, tree: [after1of1Key4]))
        XCTAssertNil(try Nutroot.resolve(disclosed).keyPathKey)
        XCTAssertThrowsError(try Nutroot.keyPathKey(for: disclosed))
        var wrongK = disclosed
        wrongK.spendInfo = .init(K: key7, tree: [after1of1Key4])
        XCTAssertThrowsError(try Nutroot.resolve(wrongK))

        // Bearer proof with no conditions: k = 7 travels, secret is its bare key.
        let bearer = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: key7, C: "", spendInfo: .init(k: scalar(7)))
        XCTAssertEqual(hex(Array(try XCTUnwrap(try Nutroot.resolve(bearer).keyPathKey).dataRepresentation)), scalar(7))
    }

    func testTwoLeavesWithUnknownTypeAndFilledPath() throws {
        let leaf0Unknown = "00050200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f90a002103acd484e2f0c7f65309ad178a9f559abde09796974c57e714c35f110dfc27ccbe"
        let leaf1After = "00020200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f906000468cc9d00"
        let hash0 = "8714a51c3019861df9c4d0d6a1f30f0465ea1252e9c3b949802f73eda61cb101"
        let hash1 = "80468218b6e329d4d80682883617af0acd1d4a9d5b1658fbc448cc4781b4f254"
        let secret = "02f4ff2c2894698847760b62bce9d0d6c6c745d0d85c83577a00337d75437bccf0"
        XCTAssertEqual(hex(Nutroot.leafHash(try leaf0Unknown.bytes)), hash0)
        XCTAssertEqual(hex(Nutroot.leafHash(try leaf1After.bytes)), hash1)
        XCTAssertEqual(try Nutroot.root(leaves: [leaf0Unknown, leaf1After]), "9d8170c0f86d30de108834ff1ee334decac6ae094fb07652801d9c159c7b1bed")
        let K = try CashuSwift.Crypto.nut20PublicKey(key6)
        XCTAssertEqual(hex(Nutroot.tweak(internalKey: Array(K.dataRepresentation), root: try "9d8170c0f86d30de108834ff1ee334decac6ae094fb07652801d9c159c7b1bed".bytes)),
                       "153e9c65e6bea3351f4e78145f328e5aae7e7a4722967bf347f057bcaa47bfba")
        let leaves = [try leaf0Unknown.bytes, try leaf1After.bytes]
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K, leaves: leaves).dataRepresentation)), secret)
        XCTAssertEqual(try Nutroot.merklePath(leaves: [leaf0Unknown, leaf1After], index: 1), [hash0])

        let digest = try illustrativeDigest.bytes
        // Leaf 1 spends through [hash0] once its locktime passes.
        let good = try Nutroot.scriptPathWitness(internalKey: key6, leaves: [leaf0Unknown, leaf1After], leafIndex: 1,
                                                 inputDigest: digest, keys: [try schnorr(scalar(3))])
        XCTAssertEqual(good.control?.path, [hash0])
        XCTAssertNoThrow(try Nutroot.verifyScriptPath(good, secret: secret, inputDigest: digest, now: 1758240000))
        // Revealing the unknown-type leaf reconstructs the secret but MUST be rejected.
        let bad = CashuSwift.Proof.Witness(signatures: [], leaf: leaf0Unknown, control: .init(K: key6, path: [hash1]))
        XCTAssertThrowsError(try Nutroot.verifyScriptPath(bad, secret: secret, inputDigest: digest))
        XCTAssertThrowsError(try Leaf.parse(hex: leaf0Unknown))
        // And a disclosed tree containing it is rejected at receive time.
        let proof = CashuSwift.Proof(keysetID: "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6",
                                     amount: 1, secret: secret, C: "", spendInfo: .init(K: key6, tree: [leaf0Unknown, leaf1After]))
        XCTAssertThrowsError(try Nutroot.resolve(proof))
    }

    func testCommitLeaf() throws {
        let K = "028edfebd6fdea3e1d89359af20868a2e76315b36cdb1a79de497a1757ca7bd407"
        let hash = "64451ff981aa92887b070762e97302df00a0ab97a853c323394b0a9cfaf46fae"
        let leafCommit = "000408002064451ff981aa92887b070762e97302df00a0ab97a853c323394b0a9cfaf46fae"
        let secret = "028f86ae14b1a813b7093473faf7b1024979dd6da4db0790126daa2922331afce0"
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(Array("external data".utf8))), hash)
        XCTAssertEqual(try Leaf.commit(hash).serializedHex(), leafCommit)
        XCTAssertEqual(hex(Array(try Nutroot.numsInternalKey(offset: try priv(7)).dataRepresentation)), K)
        XCTAssertEqual(hex(Nutroot.leafHash(try leafCommit.bytes)), "20cccc22a45ddfdbec0647032487870dbeadb03471164eb6767b1234f9914f27")
        let tree = [threshold1of1Key3, leafCommit]
        XCTAssertEqual(try Nutroot.root(leaves: tree), "a23cd934664be4637fd2d9a16febca5ed06e7e3d0adef2231eeb7bcacaa156cd")
        let point = try CashuSwift.Crypto.nut20PublicKey(K)
        XCTAssertEqual(hex(Nutroot.tweak(internalKey: Array(point.dataRepresentation), root: try "a23cd934664be4637fd2d9a16febca5ed06e7e3d0adef2231eeb7bcacaa156cd".bytes)),
                       "26992654d7ef6a6422bc84867ce87e7c641a59dacf86e2b339e434a92af374cf")
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: point, leaves: try tree.map { try $0.bytes }).dataRepresentation)), secret)

        let digest = try illustrativeDigest.bytes
        let viaThreshold = try Nutroot.scriptPathWitness(internalKey: K, leaves: tree, leafIndex: 0, inputDigest: digest,
                                                         keys: [try schnorr(scalar(3))])
        XCTAssertEqual(viaThreshold.control?.path, ["20cccc22a45ddfdbec0647032487870dbeadb03471164eb6767b1234f9914f27"])
        XCTAssertNoThrow(try Nutroot.verifyScriptPath(viaThreshold, secret: secret, inputDigest: digest))
        XCTAssertThrowsError(try Nutroot.scriptPathWitness(internalKey: K, leaves: tree, leafIndex: 1, inputDigest: digest, keys: []))
        let revealCommit = CashuSwift.Proof.Witness(signatures: [], leaf: leafCommit,
                                                    control: .init(K: K, path: ["23e8ff1693496ecad495b7ed3cdd7f8595c52a3adc0b92475835b0fb839116cb"]))
        XCTAssertThrowsError(try Nutroot.verifyScriptPath(revealCommit, secret: secret, inputDigest: digest))

        // Script-only spend info: K - u·G == H checks out, and no key path exists.
        let proof = CashuSwift.Proof(keysetID: "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6",
                                     amount: 1, secret: secret, C: "", spendInfo: .init(K: K, tree: tree, u: scalar(7)))
        XCTAssertNil(try Nutroot.resolve(proof).keyPathKey)
        var wrongU = proof
        wrongU.spendInfo = .init(K: K, tree: tree, u: scalar(8))
        XCTAssertThrowsError(try Nutroot.resolve(wrongU))
    }

    func testRejectionVectors() {
        XCTAssertThrowsError(try Leaf.parse(hex: "00010200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9090004deadbeef"), "unknown field")
        XCTAssertThrowsError(try Leaf.parse(hex: "00040200010108002064451ff981aa92887b070762e97302df00a0ab97a853c323394b0a9cfaf46fae"), "commit with n")
        XCTAssertThrowsError(try Leaf.parse(hex: "0101"), "unknown version")
        XCTAssertThrowsError(try Leaf.threshold(n: 2, keys: [key3]), "n above key count")
        XCTAssertThrowsError(try Leaf.threshold(n: 1, keys: [key3, "03f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"]), "same x twice")
        XCTAssertThrowsError(try Nutroot.root(leaves: Array(repeating: threshold1of1Key3, count: 9)), "more than 8 leaves")
    }

    func testEmptyTweak() throws {
        let K = try CashuSwift.Crypto.nut20PublicKey(key3)
        XCTAssertEqual(hex(Nutroot.tweak(internalKey: Array(K.dataRepresentation), root: nil)),
                       "764c0e0da0d17acb5cc863fbe939211869e04e522c017171a0b71e91d5b69908")
        let secret = "03b2bb251c006ae42d9c19f3157d02b3c347b1fb6512885225a8699a06d9233aee"
        XCTAssertEqual(hex(Array(try Nutroot.secret(internalKey: K, leaves: []).dataRepresentation)), secret)
        XCTAssertEqual(hex(Array(try Nutroot.keyPathPrivateKey(k: try priv(3), leaves: []).dataRepresentation)),
                       "764c0e0da0d17acb5cc863fbe939211869e04e522c017171a0b71e91d5b6990b")
        // Resolves as the aggregated form with no tree disclosed.
        let proof = CashuSwift.Proof(keysetID: "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6",
                                     amount: 1, secret: secret, C: "", spendInfo: .init(k: scalar(3)))
        XCTAssertEqual(hex(Array(try XCTUnwrap(try Nutroot.resolve(proof).keyPathKey).dataRepresentation)),
                       "764c0e0da0d17acb5cc863fbe939211869e04e522c017171a0b71e91d5b6990b")
    }
}
