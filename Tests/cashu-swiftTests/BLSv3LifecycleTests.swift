import XCTest
import SwiftBLST
import secp256k1
@testable import CashuSwift

/// End-to-end exercise of the v3 dispatch through `generateOutputs` → (simulated mint
/// signing) → `unblindPromises` → `checkDLEQ` → `signV3Inputs`, using a locally constructed
/// v3 keyset.
final class BLSv3LifecycleTests: XCTestCase {

    typealias BLS = CashuSwift.Crypto.BLS

    private let amounts = [1, 2, 4, 8]

    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Build a v3 keyset with a distinct mint scalar per amount; returns the keyset and the
    /// per-amount scalars so the test can play the role of the mint.
    private func makeV3Keyset() throws -> (keyset: CashuSwift.Keyset, scalars: [Int: BLST.Scalar]) {
        var scalars = [Int: BLST.Scalar]()
        var keys = [String: String]()
        for (i, amount) in amounts.enumerated() {
            var bytes = [UInt8](repeating: 0, count: 32)
            bytes[31] = UInt8(i + 2)  // distinct non-zero scalar per amount
            let a = try BLST.Scalar(bytes: bytes)
            scalars[amount] = a
            keys[String(amount)] = hex(a.publicKeyG2().compressedBytes)
        }
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv3(keyset: keys, unit: "sat", inputFeePPK: 0)
        let json: [String: Any] = ["id": id, "unit": "sat", "active": true,
                                   "input_fee_ppk": 0, "keys": keys]
        let data = try JSONSerialization.data(withJSONObject: json)
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: data)
        XCTAssertTrue(keyset.validID)
        return (keyset, scalars)
    }

    /// Mint side: C_ = a·B_ for the amount's scalar.
    private func sign(outputs: [CashuSwift.Output], scalars: [Int: BLST.Scalar]) throws -> [CashuSwift.Promise] {
        try outputs.map { o in
            let B_ = try BLS.g1Point(fromHex: o.B_)
            let C_ = B_.multiplied(by: scalars[o.amount]!)
            return CashuSwift.Promise(id: o.id, amount: o.amount, C_: hex(C_.compressedBytes), dleq: nil)
        }
    }

    func testRandomOutputLifecycle() throws {
        let (keyset, scalars) = try makeV3Keyset()
        let mint = CashuSwift.Mint(url: URL(string: "https://mint.test")!, keysets: [keyset])

        let (outputs, blindingFactors, secrets) =
            try CashuSwift.Crypto.generateOutputs(amounts: amounts, keysetID: keyset.keysetID)

        // Outputs are compressed G1 (96 hex) on the v3 keyset; the secrets slot holds `k`.
        for o in outputs { XCTAssertEqual(o.B_.count, 96); XCTAssertEqual(o.id, keyset.keysetID) }
        for s in secrets { XCTAssertEqual(s.count, 64) }

        let promises = try sign(outputs: outputs, scalars: scalars)
        let proofs = try CashuSwift.Crypto.unblindPromises(promises,
                                                           blindingFactors: blindingFactors,
                                                           secrets: secrets,
                                                           keyset: keyset)

        XCTAssertEqual(proofs.count, amounts.count)
        for (p, k) in zip(proofs, secrets) {
            XCTAssertEqual(p.C.count, 96)   // unblinded signature is compressed G1
            XCTAssertNil(p.dleq)            // v3 proofs carry no DLEQ
            XCTAssertEqual(p.secret.count, 66)  // the wire secret is K = k·G
            XCTAssertEqual(p.spendInfo?.k, k)   // and the proof keeps its bearer key
            let K = try secp256k1.Signing.PrivateKey(dataRepresentation: try k.bytes).publicKey
            XCTAssertEqual(p.secret, hex(Array(K.dataRepresentation)))
        }

        // Pairing verification of the resulting proofs succeeds.
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)

        // NUT-07 lookup point is a G1 (96 hex) for v3 proofs.
        XCTAssertEqual(try CashuSwift.stateCheckY(for: proofs[0]).count, 96)

        // Spending them: every v3 input gets a key-path witness over its input digest.
        let next = try CashuSwift.Crypto.generateOutputs(amounts: [15], keysetID: keyset.keysetID)
        let signed = CashuSwift.stripDLEQ(try CashuSwift.signV3Inputs(proofs, outputs: next.outputs.map { .blinded($0) }))
        let transaction = CashuSwift.Transaction(inputs: proofs.map { .proof($0) }, outputs: next.outputs.map { .blinded($0) })
        XCTAssertThrowsError(try CashuSwift.signV3Inputs(CashuSwift.stripDLEQ(proofs), outputs: next.outputs.map { .blinded($0) }),
                             "wire proofs have no bearer key to sign with")
        for (i, p) in signed.enumerated() {
            let witness = try CashuSwift.Proof.Witness(json: try XCTUnwrap(p.witness))
            XCTAssertEqual(witness.signatures.count, 1)
            XCTAssertNil(p.spendInfo, "bearer keys never go on the wire")
            XCTAssertTrue(CashuSwift.Crypto.schnorrVerify(digest: try transaction.inputDigest(i),
                                                          signatureHex: witness.signatures[0],
                                                          publicKey: try p.secret.bytes))
        }
    }

    func testDeterministicOutputLifecycleAndReproducibility() throws {
        let (keyset, scalars) = try makeV3Keyset()
        let mint = CashuSwift.Mint(url: URL(string: "https://mint.test")!, keysets: [keyset])
        let seed = String(repeating: "42", count: 32)

        let first = try CashuSwift.Crypto.generateOutputs(amounts: amounts,
                                                          keysetID: keyset.keysetID,
                                                          deterministicFactors: (seed, 0))
        let second = try CashuSwift.Crypto.generateOutputs(amounts: amounts,
                                                           keysetID: keyset.keysetID,
                                                           deterministicFactors: (seed, 0))
        // Deterministic derivation is reproducible (the basis for NUT-13 restore).
        XCTAssertEqual(first.outputs.map(\.B_), second.outputs.map(\.B_))
        XCTAssertEqual(first.secrets, second.secrets)
        XCTAssertEqual(first.blindingFactors, second.blindingFactors)

        let promises = try sign(outputs: first.outputs, scalars: scalars)
        let proofs = try CashuSwift.Crypto.unblindPromises(promises,
                                                           blindingFactors: first.blindingFactors,
                                                           secrets: first.secrets,
                                                           keyset: keyset)
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)
    }

    func testUnblindRejectsForgedSignatureAndDLEQ() throws {
        let (keyset, scalars) = try makeV3Keyset()
        let (outputs, blindingFactors, secrets) =
            try CashuSwift.Crypto.generateOutputs(amounts: amounts, keysetID: keyset.keysetID)

        // Sign every output with the WRONG scalar (amount 1's key) — pairing must reject.
        let wrongScalars = Dictionary(uniqueKeysWithValues: amounts.map { ($0, scalars[1]!) })
        let forged = try sign(outputs: outputs, scalars: wrongScalars)

        XCTAssertThrowsError(try CashuSwift.Crypto.unblindPromises(forged,
                                                                  blindingFactors: blindingFactors,
                                                                  secrets: secrets,
                                                                  keyset: keyset))

        // A v3 promise carrying `dleq` is malformed (NUT-12).
        let withDLEQ = try sign(outputs: outputs, scalars: scalars).map {
            CashuSwift.Promise(id: $0.id, amount: $0.amount, C_: $0.C_, dleq: CashuSwift.DLEQ(e: "00", s: "00", r: nil))
        }
        XCTAssertThrowsError(try CashuSwift.Crypto.unblindPromises(withDLEQ,
                                                                  blindingFactors: blindingFactors,
                                                                  secrets: secrets,
                                                                  keyset: keyset))
    }

    func testReceiverKeyedSendAndClaim() throws {
        let (keyset, scalars) = try makeV3Keyset()
        let mint = CashuSwift.Mint(url: URL(string: "https://mint.test")!, keysets: [keyset])
        let receiver = try secp256k1.Signing.PrivateKey()
        let receiverHex = hex(Array(receiver.publicKey.dataRepresentation))

        let locked = try CashuSwift.Nutroot.receiverKeyedOutputs(amounts: [8], keysetID: keyset.keysetID,
                                                                 option: .init(k: receiverHex))
        let promises = try sign(outputs: locked.map(\.output), scalars: scalars)
        var proofs = try CashuSwift.Crypto.unblindPromises(promises,
                                                           blindingFactors: locked.map(\.blindingFactor),
                                                           secrets: locked.map(\.secret),
                                                           keyset: keyset)
        proofs = CashuSwift.attach(locked.map(\.spendInfo), to: proofs)
        XCTAssertNotNil(proofs[0].spendInfo?.E)
        XCTAssertNil(proofs[0].spendInfo?.k)
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)

        // Tokens carry the spend info and never a witness.
        let token = CashuSwift.Token(proofs: [mint.url.absoluteString: proofs], unit: "sat")
        let decoded = try (try token.serialize(to: .V4)).deserializeToken()
        let received = try XCTUnwrap(decoded.proofsByMint.values.first?.first)
        XCTAssertEqual(received.spendInfo, proofs[0].spendInfo)

        // Only the receiver can claim it, after which it key-path signs like a bearer proof.
        XCTAssertThrowsError(try CashuSwift.Nutroot.claim(received, receiverKey: nil))
        XCTAssertThrowsError(try CashuSwift.Nutroot.claim(received, receiverKey: try secp256k1.Signing.PrivateKey()))
        let claimed = try CashuSwift.Nutroot.claim(received, receiverKey: receiver)
        XCTAssertNotNil(claimed.spendInfo?.k)
        let next = try CashuSwift.Crypto.generateOutputs(amounts: [8], keysetID: keyset.keysetID)
        let signed = try CashuSwift.signV3Inputs([claimed], outputs: next.outputs.map { .blinded($0) })
        let witness = try CashuSwift.Proof.Witness(json: try XCTUnwrap(signed[0].witness))
        let transaction = CashuSwift.Transaction(inputs: [.proof(claimed)], outputs: next.outputs.map { .blinded($0) })
        XCTAssertTrue(CashuSwift.Crypto.schnorrVerify(digest: try transaction.inputDigest(0),
                                                      signatureHex: witness.signatures[0],
                                                      publicKey: try claimed.secret.bytes))
    }
}
