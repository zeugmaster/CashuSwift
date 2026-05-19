//
//  FakeMintMintingTests.swift
//  CashuSwiftTests
//
//  Mint-quote, mint, state-check, restore, and metadata-loading tests against
//  the public FakeWallet success mint. These exercise the wallet's full
//  bolt11 mint pipeline without depending on real Lightning settlement.
//

import XCTest
@testable import CashuSwift
import BIP39

final class FakeMintMintingTests: XCTestCase {

    private let mintURL = TestEndpoints.fakeSuccess

    // MARK: - Discovery

    func testMintIsReachable() async throws {
        try await MintTestSupport.skipIfUnreachable(mintURL)
        let mint = try await CashuSwift.loadMint(url: mintURL, type: CashuSwift.Mint.self)
        let reachable = await mint.isReachable()
        XCTAssertTrue(reachable)
        XCTAssertTrue(mint.keysets.contains(where: { $0.active }),
                      "Mint should advertise at least one active keyset")
    }

    func testInfoLoad() async throws {
        let mint = try await MintTestSupport.loadMint(mintURL)
        let info = try await CashuSwift.loadMintInfo(from: mint)
        XCTAssertNotNil(info.name)
        XCTAssertNotNil(info.nuts, "Mint info should advertise supported NUTs")
    }

    func testKeysetIDsValidate() async throws {
        let mint = try await MintTestSupport.loadMint(mintURL)
        XCTAssertFalse(mint.keysets.isEmpty)
        XCTAssertTrue(mint.keysets.allSatisfy { $0.validID },
                      "All keysets advertised by the mint should have a self-consistent ID")
    }

    func testKeysetValidationDetectsTampering() async throws {
        var mint = try await MintTestSupport.loadMint(mintURL)
        XCTAssertTrue(mint.keysets.allSatisfy { $0.validID })

        guard var first = mint.keysets.first, let pair = first.keys.first else {
            XCTFail("Mint should have at least one keyset with keys")
            return
        }
        let lastChar = pair.value.last ?? "a"
        let tampered = String(pair.value.dropLast()) + (lastChar == "a" ? "b" : "a")
        first.keys[pair.key] = tampered
        mint.keysets[0] = first

        XCTAssertFalse(mint.keysets[0].validID,
                       "Tampering with a key should invalidate the keyset ID")
        XCTAssertTrue(mint.keysets.dropFirst().allSatisfy { $0.validID },
                      "Other keysets should still be valid")
    }

    // MARK: - Mint quote shape

    func testMintQuoteShape() async throws {
        let mint = try await MintTestSupport.loadMint(mintURL)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 21)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        XCTAssertFalse(quote.quote.isEmpty, "Quote ID should not be empty")
        XCTAssertTrue(quote.request.lowercased().hasPrefix("ln"), "request should be a BOLT11 invoice")
        XCTAssertEqual(quote.unit, "sat")
    }

    // MARK: - Mint flow

    func testMintFlow() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 21)
        XCTAssertEqual(proofs.sum, 21)
        XCTAssertFalse(proofs.isEmpty)
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)
    }

    func testMintFlowProducesValidDLEQ() async throws {
        let (_, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 8)
        XCTAssertTrue(proofs.allSatisfy { $0.dleq != nil },
                      "Each issued proof should carry DLEQ proof data")
    }

    func testMintWithDeterministicSecrets() async throws {
        let seed = String(bytes: Mnemonic().seed)
        let mint = try await MintTestSupport.loadMint(mintURL)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 32)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        let result = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: seed)
        XCTAssertEqual(result.proofs.sum, 32)
    }

    // MARK: - State check

    func testMintStateCheck() async throws {
        let mint = try await MintTestSupport.loadMint(mintURL)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 16)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        let refreshed = try await CashuSwift.Bolt11.mintQuoteState(quote.quote, from: mint)
        XCTAssertEqual(refreshed.quote, quote.quote)
    }

    // MARK: - Restore

    func testRestoreSeededProofs() async throws {
        let seed = String(bytes: Mnemonic().seed)
        var mint = try await MintTestSupport.loadMint(mintURL)
        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 2047)
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        let issued = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: seed)

        // Advance the keyset's derivation counter to mirror what a persistent wallet would do.
        if let idx = mint.keysets.firstIndex(where: { $0.keysetID == issued.proofs.first?.keysetID }) {
            mint.keysets[idx].derivationCounter += issued.proofs.count
        }

        // Burn the first two proofs via swap so the restore can't simply re-issue everything.
        let burnSeed = String(bytes: Mnemonic().seed)
        _ = try await CashuSwift.swap(inputs: Array(issued.proofs.prefix(2)),
                                      with: mint,
                                      amount: nil,
                                      seed: burnSeed,
                                      preferredReturnDistribution: nil)

        guard let restored = try await CashuSwift.restore(mint: mint, with: seed).first?.proofs as? [CashuSwift.Proof] else {
            XCTFail("Restore did not return any proofs")
            return
        }
        XCTAssertEqual(restored, Array(issued.proofs.dropFirst(2)))

        let (_, dleqValid) = try await CashuSwift.restore(from: mint, with: seed)
        XCTAssertTrue(dleqValid)
    }

    func testRestoreLargeBatch() async throws {
        let seed = String(bytes: Mnemonic().seed)
        let mint = try await MintTestSupport.loadMint(mintURL)
        let distribution = Array(repeating: 1, count: 200)

        let request = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: distribution.reduce(0, +))
        let quote = try await CashuSwift.Bolt11.requestMintQuote(request, from: mint)
        let result = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: seed, preferredDistribution: distribution)

        let restore = try await CashuSwift.restore(from: mint, with: seed, batchSize: 300)
        XCTAssertEqual(restore.result.first?.proofs.count, result.proofs.count)
    }

    // MARK: - Token v4 round-trip

    func testTokenV4RoundTrip() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 8)
        let token = CashuSwift.Token(proofs: [mint.url.absoluteString: proofs.withShortKeysetID()],
                                     unit: "sat",
                                     memo: nil)
        let v4 = try token.serialize(to: .V4)
        let roundTripped = try v4.deserializeToken()
        XCTAssertEqual(roundTripped.unit, "sat")
        XCTAssertEqual(roundTripped.proofsByMint.first?.value.sum, proofs.sum)
    }
}
