//
//  FakeMintErrorTests.swift
//  CashuSwiftTests
//
//  Failure-path tests against the FakeWallet error and exception mints, and
//  against an unpaid regtest mint quote.
//

import XCTest
@testable import CashuSwift

final class FakeMintErrorTests: XCTestCase {

    /// Asking the mint to issue against a quote whose invoice was never paid
    /// should throw `CashuError.quoteNotPaid`. The regtest mints back to real
    /// LND and do not simulate auto-settlement, so the quote stays `UNPAID`.
    func testMintOnUnpaidRegtestQuoteFails() async throws {
        let mint = try await MintTestSupport.loadMint(TestEndpoints.regtestMint1)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 42)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        do {
            _ = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: nil)
            XCTFail("Mint on an unpaid regtest quote should throw")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteNotPaid)
        }
    }

    /// `error-short` deterministically reports `PAY_INVOICE_STATE=FAILED` after a
    /// short delay. Incoming payments still settle (FAKEWALLET_BRR=true), so we
    /// can seed proofs and exercise a real failure on the melt path.
    func testMeltAgainstFailureBackendReportsFailure() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(TestEndpoints.fakeErrorShort, amount: 32)

        // Target invoice — use a separate fake mint so we can produce a payable invoice.
        let targetMint = try await MintTestSupport.loadMint(TestEndpoints.fakeSuccess)
        let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(
            .init(unit: "sat", amount: 8), from: targetMint
        )
        let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(
            .init(unit: "sat", request: mintQuote.request), from: mint
        )

        // Allow generous timeout since the error backend waits before reporting.
        do {
            let result = try await CashuSwift.Bolt11.melt(
                quote: meltQuote,
                from: mint,
                proofs: proofs,
                timeout: 30
            )
            // If the call returns without throwing, the resulting quote state
            // must not be `.paid` — that would mean the backend silently succeeded.
            XCTAssertNotEqual(result.quote.state, .paid,
                              "Failure backend should not report payment as PAID")
        } catch {
            // Any CashuError thrown by the failure backend is a valid outcome — we
            // only assert that the wallet propagates it rather than silently
            // marking the quote PAID.
        }
    }

    /// `exception` mint throws server-side exceptions when checking outgoing
    /// payment state. Incoming payments still settle (FAKEWALLET_BRR=true), so
    /// we can seed proofs but must fail on melt — the wallet should surface
    /// the thrown error rather than crash or silently report success.
    func testMeltAgainstExceptionBackendIsHandled() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(TestEndpoints.fakeException, amount: 32)

        let targetMint = try await MintTestSupport.loadMint(TestEndpoints.fakeSuccess)
        let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(
            .init(unit: "sat", amount: 8), from: targetMint
        )
        let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(
            .init(unit: "sat", request: mintQuote.request), from: mint
        )

        do {
            let result = try await CashuSwift.Bolt11.melt(
                quote: meltQuote,
                from: mint,
                proofs: proofs,
                timeout: 30
            )
            XCTAssertNotEqual(result.quote.state, .paid,
                              "Exception backend should not report payment as PAID")
        } catch {
            // Any thrown error is acceptable — we only assert that the wallet
            // surfaces the failure rather than silently completing.
        }
    }
}
