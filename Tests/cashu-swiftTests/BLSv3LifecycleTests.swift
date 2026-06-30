import XCTest
import SwiftBLST
@testable import CashuSwift

/// End-to-end exercise of the v3 dispatch through `generateOutputs` → (simulated mint
/// signing) → `unblindPromises` → `checkDLEQ`, using a locally constructed v3 keyset.
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
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv2(keyset: keys,
                                                              unit: "sat",
                                                              inputFeePPK: 0,
                                                              finalExpiry: nil,
                                                              versionByte: "02")
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

        // Outputs are compressed G1 (96 hex) on the v3 keyset.
        for o in outputs { XCTAssertEqual(o.B_.count, 96); XCTAssertEqual(o.id, keyset.keysetID) }

        let promises = try sign(outputs: outputs, scalars: scalars)
        let proofs = try CashuSwift.Crypto.unblindPromises(promises,
                                                           blindingFactors: blindingFactors,
                                                           secrets: secrets,
                                                           keyset: keyset)

        XCTAssertEqual(proofs.count, amounts.count)
        for p in proofs {
            XCTAssertEqual(p.C.count, 96)   // unblinded signature is compressed G1
            XCTAssertNil(p.dleq)            // v3 proofs carry no DLEQ
        }

        // Pairing verification of the resulting proofs succeeds.
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)

        // NUT-07 lookup point is a G1 (96 hex) for v3 proofs.
        XCTAssertEqual(try CashuSwift.stateCheckY(for: proofs[0]).count, 96)
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

    func testUnblindRejectsForgedSignature() throws {
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
    }
}
