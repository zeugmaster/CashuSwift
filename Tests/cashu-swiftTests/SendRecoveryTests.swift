import XCTest
@testable import CashuSwift

final class SendRecoveryTests: XCTestCase {
    typealias F = OnchainFixture

    func testLostResponseRestoresSavedLockedOutputsWithoutAnotherSwap() async throws {
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/v1/swap" { throw URLError(.timedOut) }
            XCTAssertEqual(request.url?.path, "/v1/restore")
            let body = try JSONDecoder().decode(CashuSwift.RestoreRequest.self, from: XCTUnwrap(request.httpBody))
            // Restoration need not preserve request order.
            let outputs = Array(body.outputs.reversed())
            return try JSONEncoder().encode(CashuSwift.RestoreResponse(outputs: outputs, signatures: F.promises(outputs)))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try CashuSwift.prepareSend(inputs: F.proofs([8], mint: mint), mint: mint,
            amount: 3, seed: F.seed, lockToPublicKey: F.point)
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(context.counterIncrease.increase, 2, "Only change uses deterministic counters for a locked send")
        let persisted = try F.roundTrip(context)
        let session = MintHTTPStub.session(marker: "recovery")
        defer { session.invalidateAndCancel() }
        do { _ = try await CashuSwift.send(context: persisted, from: mint, session: session); XCTFail() }
        catch { }
        let recovered = try await CashuSwift.restoreSend(context: persisted, from: mint, session: session)
        XCTAssertEqual(recovered?.send.sum, 3)
        XCTAssertEqual(recovered?.change.sum, 5)
        XCTAssertEqual(stub.requests.map { $0.url!.path }, ["/v1/swap", "/v1/restore"])
        XCTAssertTrue(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Test-Session") == "recovery" })
    }

    func testEmptyRecoveryRemainsPendingAndWrongMintNeverReceivesContext() async throws {
        let stub = try MintHTTPStub { _ in Data(#"{"outputs":[],"signatures":[]}"#.utf8) }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try CashuSwift.prepareSend(inputs: F.proofs([8], mint: mint), mint: mint, amount: 3, seed: F.seed)
        let session = MintHTTPStub.session(marker: "pending")
        defer { session.invalidateAndCancel() }
        let result = try await CashuSwift.restoreSend(context: context, from: mint, session: session)
        XCTAssertNil(result)
        let other = try F.mint(url: URL(string: "https://other.invalid")!)
        do { _ = try await CashuSwift.send(context: context, from: other, session: session); XCTFail() }
        catch { XCTAssertTrue(error is CashuSwift.SendRecoveryError) }
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testTruncatedSwapResponseDoesNotProducePartialToken() async throws {
        let stub = try MintHTTPStub { request in
            let body = try JSONDecoder().decode(CashuSwift.SwapRequest.self, from: XCTUnwrap(request.httpBody))
            return try JSONEncoder().encode(CashuSwift.SwapResponse(signatures: F.promises(Array(body.outputs.prefix(1)))))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let session = MintHTTPStub.session(marker: "partial")
        defer { session.invalidateAndCancel() }
        do { _ = try await CashuSwift.send(inputs: F.proofs([8], mint: mint), mint: mint, amount: 3, seed: F.seed, session: session); XCTFail() }
        catch { XCTAssertTrue(error is CashuSwift.SendRecoveryError) }
    }
}
