//
//  RegtestMintTests.swift
//  CashuSwiftTests
//
//  Exercises melt and fee paths against the regtest Lightning mints using
//  the public faucet to seed sats. Real LND-backed payments — slower than
//  the fake mints and dependent on the regtest network being healthy.
//

import XCTest
@testable import CashuSwift

final class RegtestMintTests: XCTestCase {

    // MARK: - Faucet seeding

    func testFaucetSeedsValidProofs() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtMint1(amount: 32)
        XCTAssertEqual(proofs.sum, 32)
        XCTAssertEqual(mint.url, TestEndpoints.regtestMint1)
        // Faucet-minted proofs may or may not carry DLEQ data depending on the
        // Nutshell version it shells out to. We only assert that the DLEQ check
        // doesn't *fail*; `.valid` and `.noData` are both acceptable.
        let dleq = try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint)
        XCTAssertNotEqual(dleq, .fail, "Faucet-seeded proofs should not have invalid DLEQ data")
    }

    // MARK: - Fees on the regtest mint

    func testRegtestMintAdvertisesInputFees() async throws {
        let mint = try await MintTestSupport.loadMint(TestEndpoints.regtestMint1)
        XCTAssertTrue(mint.keysets.contains(where: { $0.inputFeePPK > 0 }),
                      "Regtest mint should advertise a non-zero input fee per keyset")
    }

    func testCalculatedFeeMatchesAdvertisedRate() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtMint1(amount: 16)
        let calculated = try CashuSwift.calculateFee(for: proofs, of: mint)
        // Each proof contributes inputFeePPK ppk; we round up the sum to whole sats.
        guard let inputFeePPK = mint.keysets.first(where: { $0.keysetID == proofs.first?.keysetID })?.inputFeePPK else {
            XCTFail("Could not locate keyset for proof"); return
        }
        let expected = ((inputFeePPK * proofs.count) + 999) / 1000
        XCTAssertEqual(calculated, expected)
    }

    // MARK: - Melt: pay an invoice issued by a *different* mint

    /// Mints sats on mint1 via the faucet, asks mint2 for a mint quote (which is a
    /// BOLT11 invoice on LND2), then melts on mint1 to pay it. End-to-end real-LN
    /// payment between regtest LND nodes.
    func testMeltCrossMintReturnsPaid() async throws {
        try await MintTestSupport.skipIfFaucetUnavailable()
        try await MintTestSupport.skipIfUnreachable(TestEndpoints.regtestMint1)
        try await MintTestSupport.skipIfUnreachable(TestEndpoints.regtestMint2)

        // 1) Seed sats on mint1.
        let (sourceMint, sourceProofs) = try await MintTestSupport.seedProofsAtMint1(amount: 200)

        // 2) Ask mint2 for a 50-sat invoice to pay.
        let targetMint = try await MintTestSupport.loadMint(TestEndpoints.regtestMint2)
        let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(
            .init(unit: "sat", amount: 50), from: targetMint
        )

        // 3) Melt on mint1 for that invoice.
        let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(
            .init(unit: "sat", request: mintQuote.request), from: sourceMint
        )

        let inputFee = try CashuSwift.calculateFee(for: sourceProofs, of: sourceMint)
        let needed = try meltQuote.requiredInputAmount(inputFee: inputFee)
        XCTAssertGreaterThanOrEqual(sourceProofs.sum, needed,
                                    "Faucet must seed enough sats to cover amount + LN fee reserve + input fee")

        let result = try await CashuSwift.Bolt11.melt(quote: meltQuote, from: sourceMint, proofs: sourceProofs)
        XCTAssertEqual(result.quote.state, .paid)

        // 4) Confirm by minting on mint2 — the quote is now PAID.
        let issued = try await CashuSwift.Bolt11.mint(quote: mintQuote, from: targetMint, seed: nil)
        XCTAssertEqual(issued.proofs.sum, 50)
    }

    // MARK: - Token state check after spending

    /// Mints, sends, receives, then asks the mint about the original input
    /// proofs — they should all report `spent`.
    func testProofStateAfterSendIsSpent() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtMint1(amount: 100)
        let sendResult = try await CashuSwift.send(inputs: proofs, mint: mint, seed: nil)
        _ = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: nil)
        let states = try await CashuSwift.check(proofs, mint: mint)
        XCTAssertTrue(states.allSatisfy { $0 == .spent })
    }

    // MARK: - Overpayment returns change

    /// Melt quote's `fee_reserve` is the *maximum* the mint may charge for the
    /// Lightning payment. If the actual route fee is lower (regtest hop with no
    /// real fees), the mint returns the unused reserve as blind signatures over
    /// the blank outputs we supplied.
    func testMeltReturnsUnusedFeeReserveAsChange() async throws {
        try await MintTestSupport.skipIfFaucetUnavailable()
        try await MintTestSupport.skipIfUnreachable(TestEndpoints.regtestMint1)
        try await MintTestSupport.skipIfUnreachable(TestEndpoints.regtestMint2)

        let (sourceMint, sourceProofs) = try await MintTestSupport.seedProofsAtMint1(amount: 500)
        let targetMint = try await MintTestSupport.loadMint(TestEndpoints.regtestMint2)
        let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(
            .init(unit: "sat", amount: 100), from: targetMint
        )
        let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(
            .init(unit: "sat", request: mintQuote.request), from: sourceMint
        )

        let blankOutputs = try CashuSwift.generateBlankOutputs(
            quote: meltQuote,
            proofs: sourceProofs,
            mint: sourceMint,
            unit: "sat",
            seed: nil
        )

        let result = try await CashuSwift.Bolt11.melt(
            quote: meltQuote,
            from: sourceMint,
            proofs: sourceProofs,
            blankOutputs: blankOutputs
        )
        XCTAssertEqual(result.quote.state, .paid)

        let change = result.change ?? []
        let inputFee = try CashuSwift.calculateFee(for: sourceProofs, of: sourceMint)
        // The invariant: change.sum + amount + actual_LN_fee + inputFee == proofs.sum,
        // and actual_LN_fee ∈ [0, feeReserve]. Therefore change.sum lies between
        // (proofs.sum - amount - inputFee - feeReserve) and (proofs.sum - amount - inputFee).
        let maxPossibleChange = sourceProofs.sum - 100 - inputFee
        let minPossibleChange = max(0, maxPossibleChange - meltQuote.feeReserve)
        XCTAssertGreaterThanOrEqual(change.sum, minPossibleChange)
        XCTAssertLessThanOrEqual(change.sum, maxPossibleChange)
    }
}
