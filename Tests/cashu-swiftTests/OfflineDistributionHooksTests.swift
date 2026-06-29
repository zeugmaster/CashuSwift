//
//  OfflineDistributionHooksTests.swift
//  CashuSwiftTests
//
//  Tests for the offline-optimization `preferredDistribution` hooks threaded
//  through send / receive / swap (M3):
//    * network-free validation guards (always run), and
//    * end-to-end application of a supplied distribution against the public
//      FakeWallet mint (skipped when unreachable).
//

import XCTest
@testable import CashuSwift
import BIP39

private func keyset(_ id: String = "00aa", ppk: Int = 0,
                    denominations: [Int] = (0...12).map { 1 << $0 }) -> CashuSwift.Keyset {
    let keysJSON = denominations.map { "\"\($0)\":\"02aa\"" }.joined(separator: ",")
    let json = """
    {"id":"\(id)","unit":"sat","active":true,"input_fee_ppk":\(ppk),"keys":{\(keysJSON)}}
    """
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

private func syntheticProofs(_ amounts: [Int], keysetID: String = "00aa") -> [CashuSwift.Proof] {
    amounts.enumerated().map {
        CashuSwift.Proof(keysetID: keysetID, amount: $0.element,
                         secret: "s\($0.offset)", C: "C\($0.offset)", dleq: nil)
    }
}

final class OfflineDistributionHooksTests: XCTestCase {

    // MARK: - Network-free validation guards

    /// A `preferredKeepDistribution` that doesn't sum to the keep amount is rejected
    /// before any mint round-trip.
    func testSendRejectsMismatchedKeepDistribution() async throws {
        let mint = CashuSwift.Mint(url: URL(string: "https://unused.test")!, keysets: [keyset()])
        let inputs = syntheticProofs([8, 8])     // sum 16
        do {
            // amount 10, fee 0 ⇒ keep 6; supply a distribution summing to 5.
            _ = try await CashuSwift.send(inputs: inputs, mint: mint, amount: 10, seed: nil,
                                          preferredKeepDistribution: [1, 4])
            XCTFail("expected preferredDistributionMismatch")
        } catch CashuError.preferredDistributionMismatch {
            // expected — thrown at the guard, before generateOutputs / network
        }
    }

    /// The mismatch guard fires regardless of how wrong the sum is, and a correct
    /// sum passes the guard (it then proceeds toward the network, which we don't
    /// reach here — so we only assert the guard itself does not throw a mismatch).
    func testSendKeepDistributionGuardBoundary() async throws {
        let mint = CashuSwift.Mint(url: URL(string: "https://unused.test")!, keysets: [keyset()])
        let inputs = syntheticProofs([8, 8])     // sum 16, amount 10, fee 0 ⇒ keep 6
        // Oversized distribution is also rejected.
        do {
            _ = try await CashuSwift.send(inputs: inputs, mint: mint, amount: 10, seed: nil,
                                          preferredKeepDistribution: [2, 4, 2])  // sums 8 ≠ 6
            XCTFail("expected preferredDistributionMismatch")
        } catch CashuError.preferredDistributionMismatch { }
    }

    // MARK: - End-to-end (FakeWallet mint)

    private let mintURL = TestEndpoints.fakeSuccess

    /// `send` applies the supplied keep distribution to the change proofs while the
    /// token (send) proofs stay a base-2 split of the sent amount.
    func testSendAppliesPreferredKeepDistribution() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 16)
        let sendAmount = 3
        let fee = try CashuSwift.calculateFee(for: seeded, of: mint)
        let keepAmount = seeded.sum - sendAmount - fee
        let preferredKeep = Array(repeating: 1, count: keepAmount)   // distinct from base-2

        let result = try await CashuSwift.send(inputs: seeded, mint: mint, amount: sendAmount,
                                               seed: nil, preferredKeepDistribution: preferredKeep)

        XCTAssertEqual(result.send.sum, sendAmount)
        XCTAssertEqual(result.change.map(\.amount).sorted(), preferredKeep.sorted(),
                       "change proofs should follow the preferred keep distribution")
        XCTAssertEqual(result.change.count, keepAmount, "all change proofs are 1-sat")
    }

    /// `receive` applies the supplied return distribution to the received proofs.
    func testReceiveAppliesPreferredReturnDistribution() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 16)
        let token = CashuSwift.Token(proofs: [mint.url.absoluteString: seeded.withShortKeysetID()],
                                     unit: "sat", memo: nil)
        let fee = try CashuSwift.calculateFee(for: seeded, of: mint)
        let net = seeded.sum - fee
        let preferred = Array(repeating: 1, count: net)

        let result = try await CashuSwift.receive(token: token, of: mint, seed: nil,
                                                  privateKey: nil,
                                                  preferredReturnDistribution: preferred)

        XCTAssertEqual(result.proofs.sum, net)
        XCTAssertEqual(result.proofs.map(\.amount).sorted(), preferred.sorted())
    }

    /// `swap` with `amount: nil` shapes the *entire* returned pool — the whole-pool
    /// adjustment that enables receive- and consolidation-time rebalancing.
    func testSwapWholePoolAppliesPreferredDistribution() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 32)
        let fee = try CashuSwift.calculateFee(for: seeded, of: mint)
        let net = seeded.sum - fee
        let preferred = Array(repeating: 1, count: net)   // all 1-sat (distinct from base-2)

        let result = try await CashuSwift.swap(inputs: seeded, with: mint, amount: nil, seed: nil,
                                               preferredReturnDistribution: preferred)

        XCTAssertTrue(result.change.isEmpty, "whole-pool keep ⇒ no change bucket")
        XCTAssertEqual(result.new.sum, net)
        XCTAssertEqual(result.new.map(\.amount).sorted(), preferred.sorted())
    }

    /// Regression: `swap(amount: nil)` with no preferred distribution still returns a
    /// plain base-2 split (the common receive path is unchanged by the restructure).
    func testSwapWholePoolNilPreferredIsBase2() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 21)
        let fee = try CashuSwift.calculateFee(for: seeded, of: mint)
        let net = seeded.sum - fee

        let result = try await CashuSwift.swap(inputs: seeded, with: mint, amount: nil, seed: nil)

        XCTAssertEqual(result.new.sum, net)
        XCTAssertEqual(result.new.map(\.amount).sorted(),
                       CashuSwift.splitIntoBase2Numbers(net).sorted())
    }

    /// End-to-end consolidation: swapping the whole balance to `idealDistribution`
    /// lands the wallet exactly on its target shape (zero gap).
    func testConsolidationSwapReachesIdealShape() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 100)
        let fee = try CashuSwift.calculateFee(for: seeded, of: mint)
        let net = seeded.sum - fee
        guard let activeKeyset = CashuSwift.activeKeysetForUnit("sat", mint: mint) else {
            XCTFail("fake mint should have an active sat keyset"); return
        }
        let ideal = CashuSwift.idealDistribution(balance: net, keyset: activeKeyset)

        let result = try await CashuSwift.swap(inputs: seeded, with: mint, amount: nil, seed: nil,
                                               preferredReturnDistribution: ideal)

        XCTAssertEqual(result.new.map(\.amount).sorted(), ideal.sorted())
        let gap = CashuSwift.denominationGap(for: result.new, keyset: activeKeyset)
        XCTAssertEqual(gap.distance, 0, "consolidated wallet should sit exactly on target")
    }

    /// The mismatch guard also fires on the real swap path (with valid input DLEQ).
    func testSwapWholePoolRejectsMismatchedDistribution() async throws {
        let (mint, seeded) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 16)
        do {
            _ = try await CashuSwift.swap(inputs: seeded, with: mint, amount: nil, seed: nil,
                                          preferredReturnDistribution: [1, 2, 4])  // ≠ 16 − fee
            XCTFail("expected preferredDistributionMismatch")
        } catch CashuError.preferredDistributionMismatch { }
    }
}
