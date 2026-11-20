import XCTest
@testable import CashuSwift

final class SessionInjectionTests: XCTestCase {
    typealias F = OnchainFixture

    func testLoadMintForwardsSessionToEveryKeyRequest() async throws {
        let fixture = try F.mint(url: URL(string: "https://mint.invalid")!)
        let stub = try MintHTTPStub { _ in
            try JSONSerialization.data(withJSONObject: ["keysets": fixture.keysets.map { try F.json($0) }])
        }
        defer { stub.remove() }
        let session = MintHTTPStub.session(marker: "load")
        defer { session.invalidateAndCancel() }
        let loaded = try await CashuSwift.loadMint(url: stub.url, session: session)
        XCTAssertEqual(loaded.keysets.count, 1)
        XCTAssertEqual(stub.requests.count, 2)
        for request in stub.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test-Session"), "load")
            XCTAssertEqual(request.timeoutInterval, 91)
        }
    }

    func testOnchainMetadataAndQuoteUseSameSession() async throws {
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/v1/info" { return try JSONEncoder().encode(F.info()) }
            return try JSONEncoder().encode(F.mintQuote())
        }
        defer { stub.remove() }
        let session = MintHTTPStub.session(marker: "onchain")
        defer { session.invalidateAndCancel() }
        let quote = try F.mintQuote()
        _ = try await CashuSwift.Onchain.requestMintQuote(.init(unit: "sat", pubkey: quote.pubkey),
            from: F.mint(url: stub.url), session: session)
        XCTAssertEqual(stub.requests.map { $0.url!.path }, ["/v1/info", "/v1/mint/quote/onchain"])
        XCTAssertTrue(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Test-Session") == "onchain" })
    }

    func testRestoreLoopAndProofCheckKeepInjectedSession() async throws {
        var restored = false
        let stub = try MintHTTPStub { request in
            let body = try XCTUnwrap(request.httpBody)
            if request.url?.path == "/v1/checkstate" {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let ys = try XCTUnwrap(json["Ys"] as? [String])
                return try JSONSerialization.data(withJSONObject: ["states": ys.map { ["Y": $0, "state": "UNSPENT"] }])
            }
            let outputs = try JSONDecoder().decode(CashuSwift.RestoreRequest.self, from: body).outputs
            if restored { return Data(#"{"outputs":[],"signatures":[]}"#.utf8) }
            restored = true
            return try JSONEncoder().encode(CashuSwift.RestoreResponse(outputs: outputs, signatures: F.promises(outputs)))
        }
        defer { stub.remove() }
        let session = MintHTTPStub.session(marker: "restore")
        defer { session.invalidateAndCancel() }
        let result = try await CashuSwift.restore(from: F.mint(url: stub.url), with: F.seed, batchSize: 1, session: session)
        XCTAssertEqual(result.result.flatMap(\.proofs).count, 1)
        XCTAssertEqual(stub.requests.count, 4)
        XCTAssertTrue(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Test-Session") == "restore" })
    }

    func testConcurrentSessionsRemainIndependentAndCallerOwned() async throws {
        let stub = try MintHTTPStub { _ in try JSONEncoder().encode(F.info()) }
        defer { stub.remove() }
        let a = MintHTTPStub.session(marker: "a")
        let b = MintHTTPStub.session(marker: "b")
        defer { a.invalidateAndCancel(); b.invalidateAndCancel() }
        let mint = try F.mint(url: stub.url)
        async let first = CashuSwift.loadMintInfo(from: mint, session: a)
        async let second = CashuSwift.loadMintInfo(from: mint, session: b)
        _ = try await (first, second)
        _ = try await CashuSwift.loadMintInfo(from: mint, session: a)
        XCTAssertEqual(stub.requests.compactMap { $0.value(forHTTPHeaderField: "X-Test-Session") }.sorted(), ["a", "a", "b"])
    }

    func testReceiveAndPaymentDeliveryKeepInjectedSession() async throws {
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/payment" { return Data("accepted".utf8) }
            let swap = try JSONDecoder().decode(CashuSwift.SwapRequest.self, from: XCTUnwrap(request.httpBody))
            return try JSONEncoder().encode(CashuSwift.SwapResponse(signatures: F.promises(swap.outputs)))
        }
        defer { stub.remove() }
        let session = MintHTTPStub.session(marker: "payment")
        defer { session.invalidateAndCancel() }
        let mint = try F.mint(url: stub.url)
        let payload = CashuSwift.PaymentRequestPayload(id: "session-test", memo: nil,
            mint: stub.url.absoluteString, unit: "sat", proofs: try F.proofs([8], mint: mint))
        let request = CashuSwift.PaymentRequest(paymentId: "session-test", amount: 8, unit: "sat",
            singleUse: nil, mints: nil, description: nil, transports: nil, lockingCondition: nil)
        let received = try await CashuSwift.receivePaymentRequest(payload: payload, request: request,
            mint: mint, seed: F.seed, privateKey: nil, session: session)
        XCTAssertEqual(received.proofs.sum, 8)
        _ = try await CashuSwift.sendPaymentViaHTTP(payload: payload,
            to: stub.url.appending(path: "payment").absoluteString, session: session)
        XCTAssertEqual(stub.requests.map { $0.url!.path }, ["/v1/swap", "/payment"])
        XCTAssertTrue(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Test-Session") == "payment" })
    }

    func testCancelledOperationDoesNotStartRequest() async throws {
        let stub = try MintHTTPStub { _ in XCTFail("Cancelled operation sent a request"); return Data() }
        defer { stub.remove() }
        let session = MintHTTPStub.session(marker: "cancel")
        defer { session.invalidateAndCancel() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CashuSwift.loadMint(url: stub.url, session: session)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(stub.requests.isEmpty)
    }
}
