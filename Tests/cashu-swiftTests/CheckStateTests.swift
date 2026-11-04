import Foundation
import XCTest
@testable import CashuSwift

final class CheckStateTests: XCTestCase {
    func testDetailedStatesExposePendingWitnessAndDigestAndKeepLegacyAPI() async throws {
        let witness = #"{"signatures":["test-signature"]}"#
        let digest = String(repeating: "ab", count: 32)
        let stub = try MintHTTPStub { request in
            XCTAssertEqual(request.url?.path, "/v1/checkstate")
            let body = try JSONDecoder().decode(CashuSwift.Proof.StateCheckRequest.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.Ys[0].count, 96)
            return try JSONSerialization.data(withJSONObject: ["states": [
                ["Y": body.Ys[0], "state": "PENDING", "witness": witness, "input_digest": digest]
            ]])
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url)
        let proofs = try V3Fixture.proofs([1], mint: mint)
        let detailed = try await CashuSwift.checkState(proofs, mint: mint)
        XCTAssertEqual(detailed[0].state, .pending)
        XCTAssertEqual(detailed[0].witness, witness)
        XCTAssertEqual(detailed[0].inputDigest, digest)
        let legacy = try await CashuSwift.check(proofs, mint: mint)
        XCTAssertEqual(legacy, [.pending])
    }

    func testCheckStateRejectsMissingOrMismatchedEntries() async throws {
        for entries: [[String: String]] in [[], [["Y": "wrong-proof", "state": "SPENT"]]] {
            let stub = try MintHTTPStub { _ in try JSONSerialization.data(withJSONObject: ["states": entries]) }
            defer { stub.remove() }
            let mint = try V3Fixture.mint(url: stub.url)
            let proofs = try V3Fixture.proofs([1], mint: mint)
            do {
                _ = try await CashuSwift.check(proofs, url: mint.url)
                XCTFail("mismatched state response accepted")
            } catch CashuError.inputError { }
        }
    }
}
