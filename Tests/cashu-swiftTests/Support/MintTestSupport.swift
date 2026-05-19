//
//  MintTestSupport.swift
//  CashuSwiftTests
//
//  Shared helpers for integration tests against the public test infrastructure.
//

import Foundation
import XCTest
@testable import CashuSwift

enum MintTestSupport {

    /// Probes `/v1/info` on the given mint URL with a short timeout. Throws
    /// `XCTSkip` so the test is reported as skipped (not failed) when the
    /// infrastructure isn't reachable from this host.
    static func skipIfUnreachable(_ url: URL, file: StaticString = #filePath, line: UInt = #line) async throws {
        var req = URLRequest(url: url.appending(path: "/v1/info"), timeoutInterval: 5)
        req.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw XCTSkip("Mint \(url) returned non-OK status; skipping.", file: file, line: line)
            }
        } catch is XCTSkip {
            throw XCTSkip("Mint \(url) is unreachable; skipping.", file: file, line: line)
        } catch {
            throw XCTSkip("Mint \(url) is unreachable (\(error)); skipping.", file: file, line: line)
        }
    }

    /// Probes the faucet's `/api/health` endpoint. Throws `XCTSkip` if the
    /// faucet is down — used by tests that depend on seeding regtest sats.
    static func skipIfFaucetUnavailable(file: StaticString = #filePath, line: UInt = #line) async throws {
        do {
            _ = try await Faucet.health()
        } catch {
            throw XCTSkip("Faucet is unavailable (\(error)); skipping.", file: file, line: line)
        }
    }

    /// Loads a mint, skipping the calling test if the mint is unreachable.
    static func loadMint(_ url: URL, file: StaticString = #filePath, line: UInt = #line) async throws -> CashuSwift.Mint {
        try await skipIfUnreachable(url, file: file, line: line)
        return try await CashuSwift.loadMint(url: url, type: CashuSwift.Mint.self)
    }

    /// End-to-end "give me funded proofs at the regtest faucet's mint (mint1)".
    /// The faucet always mints at mint1; cross-mint tests should swap or melt
    /// from there.
    ///
    /// - Returns: `(mint, proofs)` where `proofs` sum to `amount` and live on
    ///            the returned mint.
    static func seedProofsAtMint1(amount: Int = 100,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async throws -> (mint: CashuSwift.Mint, proofs: [CashuSwift.Proof]) {
        try await skipIfFaucetUnavailable(file: file, line: line)
        try await skipIfUnreachable(TestEndpoints.regtestMint1, file: file, line: line)
        let (proofs, mintURL) = try await Faucet.mintProofs(amount: amount)
        guard URL(string: mintURL) == TestEndpoints.regtestMint1 else {
            XCTFail("Faucet returned token for unexpected mint \(mintURL)", file: file, line: line)
            throw FaucetMismatch.unexpectedMint(mintURL)
        }
        let mint = try await CashuSwift.loadMint(url: TestEndpoints.regtestMint1)
        // Normalize proof keyset IDs to full-length using the freshly loaded mint
        // (faucet emits short-form keyset IDs in v2 tokens).
        let normalizedProofs = try proofs.withFullKeysetID(of: mint)
        return (mint, normalizedProofs)
    }

    /// Issues a fresh batch of proofs at a FakeWallet mint by going through the
    /// full mint-quote → mint flow. The mint settles instantly so this is the
    /// fast way to seed test fixtures without involving the regtest faucet.
    static func seedProofsAtFakeMint(_ mintURL: URL = TestEndpoints.fakeSuccess,
                                     amount: Int,
                                     unit: String = "sat",
                                     seed: String? = nil,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) async throws -> (mint: CashuSwift.Mint, proofs: [CashuSwift.Proof]) {
        let mint = try await loadMint(mintURL, file: file, line: line)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: unit, amount: amount)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        // FakeWallet's `_SUCCESS` backend reports PAID after a brief delay (~1s incoming).
        // Allow a few retries before issuing.
        for _ in 0..<5 {
            let refreshed = try await CashuSwift.Bolt11.mintQuoteState(quote.quote, from: mint)
            if refreshed.state == .paid { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let issue = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: seed)
        return (mint, issue.proofs)
    }

    enum FaucetMismatch: Swift.Error {
        case unexpectedMint(String)
    }
}
