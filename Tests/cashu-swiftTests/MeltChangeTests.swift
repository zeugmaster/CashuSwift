//
//  MeltChangeTests.swift
//  cashu-swiftTests
//
//  Offline coverage for `CashuSwift.recoverMeltChange`, the non-throwing
//  post-payment change recovery shared by `_melt` and `_meltState`. A tiny
//  in-process "mint" signs blank outputs with known keys so every branch of
//  the recovery can be driven without a network.
//

import XCTest
@testable import CashuSwift
import secp256k1

final class MeltChangeTests: XCTestCase {

    private typealias BlankOutputs = (outputs: [CashuSwift.Output],
                                      blindingFactors: [String],
                                      secrets: [String])

    private static let keysetID = "00ad268c4d1f5826"
    private static let foreignKeysetID = "00ffffffffffffff"
    private static let mintURL = URL(string: "https://mint.example")!

    /// Mint-side private keys per denomination. The test mint signs with these.
    private static let mintKeys: [Int: String] = [
        1: "0000000000000000000000000000000000000000000000000000000000000011",
        2: "0000000000000000000000000000000000000000000000000000000000000022",
        4: "0000000000000000000000000000000000000000000000000000000000000033",
    ]

    // MARK: - Fixtures

    private func makeMint() throws -> CashuSwift.Mint {
        var keys = [String: String]()
        for (amount, k) in Self.mintKeys {
            let priv = try CashuSwift.Crypto.PrivateKey(dataRepresentation: k.bytes)
            keys[String(amount)] = priv.publicKey.stringRepresentation
        }
        let json: [String: Any] = ["id": Self.keysetID,
                                   "unit": "sat",
                                   "active": true,
                                   "keys": keys,
                                   "input_fee_ppk": 0]
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self,
                                              from: JSONSerialization.data(withJSONObject: json))
        return CashuSwift.Mint(url: Self.mintURL, keysets: [keyset])
    }

    private func makeBlankOutputs(count: Int, keysetID: String = MeltChangeTests.keysetID) throws -> BlankOutputs {
        try CashuSwift.Crypto.generateOutputs(amounts: Array(repeating: 0, count: count), keysetID: keysetID)
    }

    /// Acts as the mint: `C_ = k_amount * B_`.
    private func sign(_ output: CashuSwift.Output,
                      amount: Int,
                      dleq: CashuSwift.DLEQ? = nil) throws -> CashuSwift.Promise {
        let k = try XCTUnwrap(Self.mintKeys[amount])
        let B_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: output.B_.bytes, format: .compressed)
        let C_ = try B_.multiply(k.bytes)
        return CashuSwift.Promise(id: output.id, amount: amount, C_: C_.stringRepresentation, dleq: dleq)
    }

    private func assertUnrecoverable(_ outcome: CashuSwift.MeltChange,
                                     echoing expected: [CashuSwift.Promise],
                                     file: StaticString = #filePath,
                                     line: UInt = #line) {
        guard case .unrecoverable(let promises, _) = outcome else {
            return XCTFail("expected .unrecoverable, got \(outcome)", file: file, line: line)
        }
        // The caller needs the original promises to persist and retry.
        XCTAssertEqual(promises.map(\.C_), expected.map(\.C_), file: file, line: line)
        // Legacy fields must look exactly like the pre-enum behaviour.
        XCTAssertNil(outcome.recoveredProofs, file: file, line: line)
        XCTAssertEqual(outcome.legacyDLEQResult, .valid, file: file, line: line)
    }

    // MARK: - Success

    func testRecoversChangeFromValidPromises() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 3)
        // NUT-08: the mint signs a prefix of the blank outputs with the change denominations.
        let promises = [try sign(blanks.outputs[0], amount: 2),
                        try sign(blanks.outputs[1], amount: 1)]

        let outcome = CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint)

        guard case .recovered(let proofs, let dleq) = outcome else {
            return XCTFail("expected .recovered, got \(outcome)")
        }
        XCTAssertEqual(dleq, .noData)
        XCTAssertEqual(proofs.map(\.amount), [2, 1])
        XCTAssertEqual(proofs.map(\.secret), Array(blanks.secrets.prefix(2)))
        XCTAssertEqual(proofs.map(\.keysetID), [Self.keysetID, Self.keysetID])

        // Each unblinded C must equal k_amount * hash_to_curve(secret), i.e. a signature
        // the mint would accept, which proves the full blind-signature round trip.
        for proof in proofs {
            let k = try XCTUnwrap(Self.mintKeys[proof.amount])
            let Y = try CashuSwift.Crypto.secureHashToCurve(message: proof.secret)
            XCTAssertEqual(proof.C, try Y.multiply(k.bytes).stringRepresentation)
        }

        XCTAssertEqual(outcome.recoveredProofs?.count, 2)
        XCTAssertEqual(outcome.legacyDLEQResult, .noData)
    }

    // MARK: - Nothing to recover

    func testMissingOrEmptyPromisesIsNone() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 2)

        for promises in [nil, []] as [[CashuSwift.Promise]?] {
            let outcome = CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint)
            guard case .none = outcome else {
                return XCTFail("expected .none for promises \(String(describing: promises)), got \(outcome)")
            }
            XCTAssertNil(outcome.recoveredProofs)
            XCTAssertEqual(outcome.legacyDLEQResult, .valid)
        }

        // A mint echoing `change: []` when the wallet sent no blank outputs is benign.
        let echoed = CashuSwift.recoverMeltChange(promises: [], blankOutputs: nil, mint: mint)
        guard case .none = echoed else {
            return XCTFail("expected .none, got \(echoed)")
        }
    }

    // MARK: - Unrecoverable

    func testPromisesWithoutBlankOutputsAreUnrecoverable() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let promises = [try sign(blanks.outputs[0], amount: 1)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: nil, mint: mint),
                            echoing: promises)

        let empty: BlankOutputs = ([], [], [])
        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: empty, mint: mint),
                            echoing: promises)
    }

    func testMorePromisesThanBlankOutputsIsUnrecoverable() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let extra = try makeBlankOutputs(count: 1)
        let promises = [try sign(blanks.outputs[0], amount: 1),
                        try sign(extra.outputs[0], amount: 2)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint),
                            echoing: promises)
    }

    func testDenominationMissingFromKeysetIsUnrecoverable() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let signed = try sign(blanks.outputs[0], amount: 1)
        // The mint claims a denomination the keyset has no key for.
        let promises = [CashuSwift.Promise(id: signed.id, amount: 8, C_: signed.C_, dleq: nil)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint),
                            echoing: promises)
    }

    func testMalformedSignatureIsUnrecoverable() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let promises = [CashuSwift.Promise(id: Self.keysetID, amount: 1, C_: "not-a-curve-point", dleq: nil)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint),
                            echoing: promises)
    }

    func testBlankOutputKeysetUnknownToMintIsUnrecoverable() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1, keysetID: Self.foreignKeysetID)
        let promises = [try sign(blanks.outputs[0], amount: 1)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint),
                            echoing: promises)
    }

    func testMixedBlankOutputKeysetsIsUnrecoverable() throws {
        let mint = try makeMint()
        let a = try makeBlankOutputs(count: 1)
        let b = try makeBlankOutputs(count: 1, keysetID: Self.foreignKeysetID)
        let mixed: BlankOutputs = (a.outputs + b.outputs,
                                   a.blindingFactors + b.blindingFactors,
                                   a.secrets + b.secrets)
        let promises = [try sign(a.outputs[0], amount: 1)]

        assertUnrecoverable(CashuSwift.recoverMeltChange(promises: promises, blankOutputs: mixed, mint: mint),
                            echoing: promises)
    }

    // MARK: - DLEQ never throws after payment

    func testMalformedDLEQDataReportsFailedCheck() throws {
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let promises = [try sign(blanks.outputs[0], amount: 1, dleq: .init(e: "zz", s: "zz", r: nil))]

        let outcome = CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint)

        guard case .recovered(let proofs, let dleq) = outcome else {
            return XCTFail("expected .recovered, got \(outcome)")
        }
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(dleq, .fail)
        XCTAssertEqual(outcome.legacyDLEQResult, .fail)
    }

    func testPromiseLabelledWithForeignKeysetFailsDLEQ() throws {
        // The mint signs with our requested key but labels the promise with a keyset the
        // wallet does not know. Unblinding uses the blank outputs' keyset and succeeds;
        // the DLEQ check cannot resolve the foreign ID and must report failure, not throw.
        let mint = try makeMint()
        let blanks = try makeBlankOutputs(count: 1)
        let signed = try sign(blanks.outputs[0], amount: 1)
        let promises = [CashuSwift.Promise(id: Self.foreignKeysetID, amount: 1, C_: signed.C_, dleq: nil)]

        let outcome = CashuSwift.recoverMeltChange(promises: promises, blankOutputs: blanks, mint: mint)

        guard case .recovered(let proofs, let dleq) = outcome else {
            return XCTFail("expected .recovered, got \(outcome)")
        }
        XCTAssertEqual(proofs.count, 1)
        XCTAssertEqual(dleq, .fail)
    }
}
