import XCTest
import secp256k1
@testable import CashuSwift

/// NUT-XX signing package vector (nuts #464, tests/XX).
final class SigningPackageTests: XCTestCase {

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private func scalar(_ n: UInt8) -> String { String(repeating: "0", count: 62) + String(format: "%02x", n) }

    let lockKey = "034b15129a9c665f37fbe9f6c80a7fe6ec0c809f34edde98d298aff94a1e8af276"
    let transcript = "12003d0100010802000f71756f74652d6d696e742d30303031030021034b15129a9c665f37fbe9f6c80a7fe6ec0c809f34edde98d298aff94a1e8af27604000021004b0100010802002102b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6030020567b4ba980dd0c51c80919633b384c0764b30e5250c4a8b8e3957c9f4208cdee"
    let leaf = "00010200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
    let K = "028edfebd6fdea3e1d89359af20868a2e76315b36cdb1a79de497a1757ca7bd407"
    let signature = "11edaf3608a6b1fbec19f1826e58ace09ca51aafbb7ad112a0b0b8f8787967d98eea2936bb55053dd463dbe47c2f23f37e5475ae4ebe92b328df54e80c7d9206"
    let unsigned = "nutspAeyJ2ZXJzaW9uIjoibnV0c3BBIiwidHJhbnNjcmlwdCI6IjEyMDAzZDAxMDAwMTA4MDIwMDBmNzE3NTZmNzQ2NTJkNmQ2OTZlNzQyZDMwMzAzMDMxMDMwMDIxMDM0YjE1MTI5YTljNjY1ZjM3ZmJlOWY2YzgwYTdmZTZlYzBjODA5ZjM0ZWRkZTk4ZDI5OGFmZjk0YTFlOGFmMjc2MDQwMDAwMjEwMDRiMDEwMDAxMDgwMjAwMjEwMmI3ZTA3N2QwMjBmYWJlZDQ1NmE2YmUxMzhhOGUyMGU5ZWY0MGI0NGQ4NzNmYTEyYzAwNWI2NTZlYjBjZjk5ZjYwMzAwMjA1NjdiNGJhOTgwZGQwYzUxYzgwOTE5NjMzYjM4NGMwNzY0YjMwZTUyNTBjNGE4YjhlMzk1N2M5ZjQyMDhjZGVlIiwic3BlbmRzIjpbeyJpbnB1dCI6MCwic2VjcmV0IjoiMDM0YjE1MTI5YTljNjY1ZjM3ZmJlOWY2YzgwYTdmZTZlYzBjODA5ZjM0ZWRkZTk4ZDI5OGFmZjk0YTFlOGFmMjc2IiwibGVhZiI6IjAwMDEwMjAwMDEwMTA0MDAyMTAyZjkzMDhhMDE5MjU4YzMxMDQ5MzQ0Zjg1Zjg5ZDUyMjliNTMxYzg0NTgzNmY5OWIwODYwMWYxMTNiY2UwMzZmOSIsImNvbnRyb2wiOnsiSyI6IjAyOGVkZmViZDZmZGVhM2UxZDg5MzU5YWYyMDg2OGEyZTc2MzE1YjM2Y2RiMWE3OWRlNDk3YTE3NTdjYTdiZDQwNyIsInBhdGgiOltdfSwic2lnbmF0dXJlcyI6W119XX0"
    let signedVector = "nutspAeyJ2ZXJzaW9uIjoibnV0c3BBIiwidHJhbnNjcmlwdCI6IjEyMDAzZDAxMDAwMTA4MDIwMDBmNzE3NTZmNzQ2NTJkNmQ2OTZlNzQyZDMwMzAzMDMxMDMwMDIxMDM0YjE1MTI5YTljNjY1ZjM3ZmJlOWY2YzgwYTdmZTZlYzBjODA5ZjM0ZWRkZTk4ZDI5OGFmZjk0YTFlOGFmMjc2MDQwMDAwMjEwMDRiMDEwMDAxMDgwMjAwMjEwMmI3ZTA3N2QwMjBmYWJlZDQ1NmE2YmUxMzhhOGUyMGU5ZWY0MGI0NGQ4NzNmYTEyYzAwNWI2NTZlYjBjZjk5ZjYwMzAwMjA1NjdiNGJhOTgwZGQwYzUxYzgwOTE5NjMzYjM4NGMwNzY0YjMwZTUyNTBjNGE4YjhlMzk1N2M5ZjQyMDhjZGVlIiwic3BlbmRzIjpbeyJpbnB1dCI6MCwic2VjcmV0IjoiMDM0YjE1MTI5YTljNjY1ZjM3ZmJlOWY2YzgwYTdmZTZlYzBjODA5ZjM0ZWRkZTk4ZDI5OGFmZjk0YTFlOGFmMjc2IiwibGVhZiI6IjAwMDEwMjAwMDEwMTA0MDAyMTAyZjkzMDhhMDE5MjU4YzMxMDQ5MzQ0Zjg1Zjg5ZDUyMjliNTMxYzg0NTgzNmY5OWIwODYwMWYxMTNiY2UwMzZmOSIsImNvbnRyb2wiOnsiSyI6IjAyOGVkZmViZDZmZGVhM2UxZDg5MzU5YWYyMDg2OGEyZTc2MzE1YjM2Y2RiMWE3OWRlNDk3YTE3NTdjYTdiZDQwNyIsInBhdGgiOltdfSwic2lnbmF0dXJlcyI6WyIxMWVkYWYzNjA4YTZiMWZiZWMxOWYxODI2ZTU4YWNlMDljYTUxYWFmYmI3YWQxMTJhMGIwYjhmODc4Nzk2N2Q5OGVlYTI5MzZiYjU1MDUzZGQ0NjNkYmU0N2MyZjIzZjM3ZTU0NzVhZTRlYmU5MmIzMjhkZjU0ZTgwYzdkOTIwNiJdfV19"

    func testDecodeSignEncodeAndMerge() throws {
        let package = try CashuSwift.SigningPackage(serialized: unsigned)
        XCTAssertEqual(package.version, "nutspA")
        XCTAssertEqual(package.transcript, transcript)
        XCTAssertEqual(package.spends, [.init(input: 0, secret: lockKey, leaf: leaf, control: .init(K: K, path: []))])
        XCTAssertEqual(hex(try package.transactionDigest()), "1b6a4f3f56d3808cb81d176a5f9959ebe5dc9251de66056794000ad758a9eb84")
        let inputs = try package.inputs()
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(hex(CashuSwift.TLV.sha256(inputs[0].record)), "a639745001afaad8964370e8ddc1406bbf14d478c6d56819f188c9b10392fe45")
        XCTAssertEqual(hex(try package.inputDigest(0)), "1e0acf51dc92e81c87ad238eea380c8238373aee3e2a30167547ce20c9212a50")

        // The same transaction built locally yields the same transcript.
        let local = CashuSwift.Transaction(inputs: [.mintQuote(id: "quote-mint-0001", amount: 8, lockKey: lockKey, issued: 0)],
                                           outputs: [.blinded(.init(amount: 8, B_: "b42a0bcc39598db1dca617aeea6bc367f2566636826dc961a54faae15b3b8d10afc1cb0206e70ab3b0e12c2b9478cd55",
                                                                    id: "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"))])
        XCTAssertEqual(hex(try local.transcript()), transcript)

        // Key 3 signs through the threshold leaf; key 4 holds nothing the leaf lists.
        let key3 = try secp256k1.Schnorr.PrivateKey(dataRepresentation: try scalar(3).bytes)
        let key4 = try secp256k1.Schnorr.PrivateKey(dataRepresentation: try scalar(4).bytes)
        XCTAssertEqual(try package.signed(with: [key4]).spends[0].signatures, [])
        let signed = try package.signed(with: [key3, key4])
        XCTAssertEqual(signed.spends[0].signatures, [signature])
        XCTAssertEqual(try package.signed(with: [key3]).signed(with: [key3]).spends[0].signatures, [signature], "no duplicate signatures")

        XCTAssertEqual(try CashuSwift.SigningPackage(serialized: try signed.serialize()), signed)
        XCTAssertEqual(try CashuSwift.SigningPackage(serialized: signedVector), signed)

        // Merge yields the quote input's witness.
        let witness = try signed.witness(for: 0)
        XCTAssertEqual(witness, .init(signatures: [signature], leaf: leaf, control: .init(K: K, path: [])))
        XCTAssertThrowsError(try package.witness(for: 0), "threshold not met before signing")

        // A signer refuses a spend whose secret does not belong to its input.
        var tampered = package
        tampered.spends[0].secret = "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
        XCTAssertThrowsError(try tampered.signed(with: [key3]))
        var wrongLeaf = package
        wrongLeaf.spends[0].leaf = "00010200010104002102e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"
        XCTAssertThrowsError(try wrongLeaf.signed(with: [key4]), "leaf does not commit to the secret")
    }

    func testPackageFromProofInputsAndMergeIntoProofs() throws {
        // A proof whose secret commits a threshold leaf for key 3 under internal key 6.
        let keysetID = "02b7e077d020fabed456a6be138a8e20e9ef40b44d873fa12c005b656eb0cf99f6"
        let key6 = "03fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a1460297556"
        let leaf = "00010200010104002102f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
        let secret = try CashuSwift.Nutroot.secret(internalKey: try CashuSwift.Crypto.nut20PublicKey(key6), leaves: [try leaf.bytes])
        let proof = CashuSwift.Proof(keysetID: keysetID, amount: 8, secret: hex(Array(secret.dataRepresentation)),
                                     C: "84d1b7291ae5737f3c851aa33cafe0f7afeb5ccb4da086c482bb85b7525e61547f1b5a6d1a01b1fed1f960d1a9d03327",
                                     spendInfo: .init(K: key6, tree: [leaf]))
        let outputs: [CashuSwift.Transaction.Output] = [.blinded(.init(amount: 8, B_: "b42a0bcc39598db1dca617aeea6bc367f2566636826dc961a54faae15b3b8d10afc1cb0206e70ab3b0e12c2b9478cd55", id: keysetID))]
        let transaction = CashuSwift.Transaction(inputs: [.proof(proof)], outputs: outputs)

        let package = try CashuSwift.SigningPackage(transaction: transaction, spends: [(0, 0)])
        XCTAssertEqual(package.spends[0].control, .init(K: key6, path: []))
        let signed = try package.signed(with: [try secp256k1.Schnorr.PrivateKey(dataRepresentation: try scalar(3).bytes)])
        XCTAssertEqual(signed.spends[0].signatures.count, 1)

        let merged = try signed.merge(into: [proof], transaction: transaction)
        let witness = try CashuSwift.Proof.Witness(json: try XCTUnwrap(merged[0].witness))
        XCTAssertNoThrow(try CashuSwift.Nutroot.verifyScriptPath(witness, secret: proof.secret, inputDigest: try transaction.inputDigest(0)))
        // The signing rule leaves the merged witness alone instead of trying a key path.
        XCTAssertEqual(try CashuSwift.signV3Inputs(merged, outputs: outputs)[0].witness, merged[0].witness)

        let other = CashuSwift.Transaction(inputs: [.proof(proof)], outputs: [.meltQuote(id: "q", amount: 8)])
        XCTAssertThrowsError(try signed.merge(into: [proof], transaction: other), "transcript mismatch")
    }
}
