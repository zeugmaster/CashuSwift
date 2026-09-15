import XCTest
@testable import CashuSwift

final class OnchainMeltTests: XCTestCase {
    typealias F = OnchainFixture
    typealias O = CashuSwift.Onchain

    func testPreparePersistsFeesBlanksAndCounterRange() throws {
        let mint = try F.mint(url: XCTUnwrap(URL(string: "https://mint-tests.invalid")), feePPK: 500)
        let quote = try F.meltQuote()
        let context = try O.prepareMelt(quote: quote, feeIndex: 7, from: mint,
                                       proofs: F.proofs([8, 8], mint: mint), seed: F.seed, info: F.info())
        XCTAssertEqual(context.inputFee, 1)
        XCTAssertEqual(context.material.outputs.map(\.amount), [0, 0, 0]) // maximum return is 7
        XCTAssertEqual(context.material.counterRange?.next, 10)
        let saved = try F.roundTrip(context)
        XCTAssertEqual(saved.feeIndex, 7)
        XCTAssertNil(saved.quote.selectedFeeIndex)
        XCTAssertEqual(try F.json(saved.executionBody)["fee_index"] as? Int, 7)
        XCTAssertEqual(saved.material.secrets, context.material.secrets)
        XCTAssertEqual(saved.material.blindingFactors, context.material.blindingFactors)
        XCTAssertThrowsError(try O.prepareMelt(quote: quote, feeIndex: 7, from: mint,
                                              proofs: F.proofs([8, 4], mint: mint), seed: nil, info: F.info()))
    }

    func testPendingBroadcastPaidAndRecoveryAfterRotation() async throws {
        // Set before the first request; all requests in this test are awaited serially.
        var context: O.MeltContext?
        var polls = 0
        let stub = try MintHTTPStub { request in
            let saved = try XCTUnwrap(context)
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/v1/melt/onchain")
                let body = try JSONDecoder().decode(O.MeltExecutionBody.self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(body.feeIndex, 7)
                XCTAssertEqual(Set(try F.json(body).keys), ["quote", "fee_index", "inputs", "outputs"])
                XCTAssertTrue(body.inputs.allSatisfy { $0.dleq == nil })
                // CDK 0.18's initial asynchronous acknowledgement has no index yet.
                return try JSONEncoder().encode(F.meltQuote(state: .pending))
            }
            polls += 1
            XCTAssertEqual(request.url?.path, "/v1/melt/quote/onchain/melt-1")
            if polls == 1 { return try JSONEncoder().encode(F.meltQuote(state: .pending, selected: 7, outpoint: F.outpoint)) }
            let promises = try F.promises(Array(saved.material.outputs.prefix(2)), amounts: [2, 4])
            return try JSONEncoder().encode(F.meltQuote(state: .paid, selected: 7, outpoint: F.outpoint, change: promises))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                    proofs: F.proofs([16], mint: mint), seed: F.seed, info: F.info())
        let saved = try F.roundTrip(XCTUnwrap(context))
        let pending = try await O.melt(context: saved, from: mint)
        XCTAssertEqual(pending.quote.state, .pending)
        XCTAssertNil(pending.changeRecovery.proofs)
        // Only the persisted keyset snapshot is needed to recover after rotation.
        let rotated = CashuSwift.Mint(url: mint.url, keysets: [])
        let broadcast = try await O.meltState(context: saved, from: rotated)
        XCTAssertEqual(broadcast.quote.outpoint, F.outpoint)
        XCTAssertNil(broadcast.changeRecovery.proofs)
        let paid = try await O.meltState(context: saved, from: rotated)
        XCTAssertEqual(paid.quote.state, .paid)
        XCTAssertEqual(paid.changeRecovery.proofs?.map(\.amount), [2, 4])
        let repeated = try await O.meltState(context: saved, from: rotated)
        XCTAssertEqual(repeated.changeRecovery.proofs?.map(\.secret), paid.changeRecovery.proofs?.map(\.secret))
        XCTAssertEqual(stub.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testLostPostResponsePollsWithoutResubmission() async throws {
        let stub = try MintHTTPStub { request in
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            return try JSONEncoder().encode(F.meltQuote(state: .paid, selected: 7, outpoint: F.outpoint))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                       proofs: F.proofs([8, 4], mint: mint), seed: nil, info: F.info())
        do { _ = try await O.melt(context: context, from: mint); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let result = try await O.meltState(context: F.roundTrip(context), from: mint)
        XCTAssertEqual(result.quote.state, .paid)
        XCTAssertEqual(result.changeRecovery.proofs?.count, 0)
        XCTAssertEqual(stub.requests.count, 2)
    }

    func testBadChangePreservesSettlementAndPromises() async throws {
        let bad = CashuSwift.Promise(id: "wrong-keyset", amount: 2, C_: F.point, dleq: nil)
        let stub = try MintHTTPStub { _ in
            try JSONEncoder().encode(F.meltQuote(state: .paid, selected: 7, outpoint: F.outpoint, change: [bad]))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                       proofs: F.proofs([16], mint: mint), seed: nil, info: F.info())
        let result = try await O.meltState(context: context, from: mint)
        XCTAssertEqual(result.quote.state, .paid)
        XCTAssertEqual(result.quote.change?.count, 1)
        if case .failed(.invalidPromises) = result.changeRecovery {} else { XCTFail() }
    }

    func testMismatchedFeeAndAmountAreReconciliationErrors() async throws {
        for altered in [try F.meltQuote(state: .pending, selected: 2),
                        try F.meltQuote(state: .pending, selected: 7, amount: 9),
                        try F.meltQuote(state: .pending, selected: 7, reserve: 3)] {
            let stub = try MintHTTPStub { _ in try JSONEncoder().encode(altered) }
            defer { stub.remove() }
            let mint = try F.mint(url: stub.url)
            let context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                           proofs: F.proofs([16], mint: mint), seed: nil, info: F.info())
            await assertOnchainError(O.Error.invalidResponse) { _ = try await O.meltState(context: context, from: mint) }
        }
    }

    func testZeroReserveOverflowExpiryDuplicatesAndInvalidKeysets() throws {
        let mint = try F.mint(url: XCTUnwrap(URL(string: "https://mint-tests.invalid")))
        let quote = try F.meltQuote(reserve: 0)
        let exact = try O.prepareMelt(quote: quote, feeIndex: 7, from: mint,
                                     proofs: F.proofs([8], mint: mint), seed: nil, info: F.info())
        XCTAssertTrue(exact.material.outputs.isEmpty)
        XCTAssertNil(exact.executionBody.outputs)
        XCTAssertThrowsError(try O.prepareMelt(quote: F.meltQuote(expiry: 1), feeIndex: 7, from: mint,
                                              proofs: F.proofs([16], mint: mint), seed: nil, info: F.info()))
        let inputs = try F.proofs([16], mint: mint)
        XCTAssertThrowsError(try O.prepareMelt(quote: quote, feeIndex: 7, from: mint,
                                              proofs: inputs + inputs, seed: nil, info: F.info()))
        XCTAssertThrowsError(try O.total([Int.max, 1]))
        var corrupt = mint
        corrupt.keysets[0].keys["1"] = F.address
        XCTAssertThrowsError(try O.prepareMelt(quote: quote, feeIndex: 7, from: corrupt,
                                              proofs: inputs, seed: nil, info: F.info()))
    }

    func testOmittedDenominationOverpaymentFailsRecovery() async throws {
        let stub = try MintHTTPStub { _ in
            try JSONEncoder().encode(F.meltQuote(state: .paid, selected: 7, outpoint: F.outpoint))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                       proofs: F.proofs([16], mint: mint), seed: nil, info: F.info())
        let result = try await O.meltState(context: context, from: mint)
        XCTAssertEqual(result.quote.state, .paid)
        // At least 4 sats must return even when the mint charges the full reserve.
        if case .failed(.invalidPromises) = result.changeRecovery {} else { XCTFail() }
    }

    func testCancellationBeforeSubmissionSendsNothing() async throws {
        let stub = try MintHTTPStub { _ in XCTFail("Cancelled task submitted proofs"); return Data() }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                       proofs: F.proofs([16], mint: mint), seed: nil, info: F.info())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await O.melt(context: context, from: mint)
        }
        do { _ = try await task.value; XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(stub.requests.isEmpty)
    }
}
