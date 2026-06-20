//
//  ProofSelectionTargetTests.swift
//  CashuSwiftTests
//
//  Tests for the optional `denominationTarget` on `selectProofs`: it shapes the
//  change outputs toward the wallet's ideal denomination distribution (deficit
//  fill) while leaving input selection — and therefore fee/change/count — exactly
//  as the no-target path produces it.
//

import XCTest
@testable import CashuSwift

// MARK: - Fixtures

private let allDenoms = (0...20).map { 1 << $0 }   // 1 … 1,048,576

private func ks(_ id: String = "00aa", ppk: Int = 0, active: Bool = true,
                unit: String = "sat", denominations: [Int] = allDenoms) -> CashuSwift.Keyset {
    let keysJSON = denominations.map { "\"\($0)\":\"02aa\"" }.joined(separator: ",")
    let json = """
    {"id":"\(id)","unit":"\(unit)","active":\(active),"input_fee_ppk":\(ppk),"keys":{\(keysJSON)}}
    """
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

private func mint(_ keysets: [CashuSwift.Keyset] = [ks()]) -> CashuSwift.Mint {
    CashuSwift.Mint(url: URL(string: "https://test.mint")!, keysets: keysets)
}

private func proofs(_ amounts: [Int], keysetID: String = "00aa") -> [CashuSwift.Proof] {
    amounts.enumerated().map {
        CashuSwift.Proof(keysetID: keysetID, amount: $0.element,
                         secret: "s\($0.offset)", C: "C\($0.offset)", dleq: nil)
    }
}

private func sum(_ xs: [Int]) -> Int { xs.reduce(0, +) }
private func isPowerOfTwo(_ n: Int) -> Bool { n > 0 && (n & (n - 1)) == 0 }

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class ProofSelectionTargetTests: XCTestCase {

    private let m = mint()

    // MARK: - Target-aware change outputs

    /// A wallet of only large coins, swapping with change, rebuilds its depleted
    /// small denominations in the change instead of taking a base-2 split.
    func testTargetAwareChangeFillsSmallDenominationDeficits() throws {
        let r = try CashuSwift.selectProofs(proofs([512, 512]), targetAmount: 500, mint: m,
                                            unit: "sat", purpose: .swap,
                                            denominationTarget: .default)
        XCTAssertEqual(r.kind, .mintTransaction)
        XCTAssertEqual(r.inputFee, 0)
        XCTAssertEqual(r.selected.count, 1)            // one 512 covers it
        XCTAssertEqual(r.changeAmount, 12)
        // Target-aware: fill the denom-1 and denom-2 deficits rather than base-2 [4,8].
        XCTAssertEqual(r.changeOutputAmounts, [1, 1, 1, 1, 2, 2, 2, 2])
        XCTAssertNotEqual(r.changeOutputAmounts, CashuSwift.splitIntoBase2Numbers(12))
        XCTAssertEqual(sum(r.changeOutputAmounts), r.changeAmount)
    }

    /// Send (payment) outputs always stay base-2 — their denominations are the
    /// recipient's concern, not ours.
    func testSendOutputsStayBase2EvenWithTarget() throws {
        let r = try CashuSwift.selectProofs(proofs([512, 512]), targetAmount: 500, mint: m,
                                            unit: "sat", purpose: .swap,
                                            denominationTarget: .default)
        XCTAssertEqual(r.sendOutputAmounts, CashuSwift.splitIntoBase2Numbers(500))
    }

    /// Without a target, change is the plain base-2 split (regression guard).
    func testNilTargetChangeIsBase2() throws {
        let r = try CashuSwift.selectProofs(proofs([512, 512]), targetAmount: 500, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.changeAmount, 12)
        XCTAssertEqual(r.changeOutputAmounts, CashuSwift.splitIntoBase2Numbers(12)) // [4, 8]
    }

    /// A direct (exact) send is unaffected by the target: still a direct token, no
    /// change, no outputs, identical inputs.
    func testDirectExactSendUnaffectedByTarget() throws {
        let input = proofs([1, 2, 4])
        let withTarget = try CashuSwift.selectProofs(input, targetAmount: 3, mint: m, unit: "sat",
                                                     purpose: .tokenTransferUnlocked,
                                                     denominationTarget: .default)
        let without = try CashuSwift.selectProofs(input, targetAmount: 3, mint: m, unit: "sat",
                                                  purpose: .tokenTransferUnlocked)
        XCTAssertEqual(withTarget.kind, .directToken)
        XCTAssertEqual(withTarget.changeOutputAmounts, [])
        XCTAssertEqual(withTarget.sendOutputAmounts, [])
        XCTAssertEqual(withTarget.selected.map(\.amount), without.selected.map(\.amount))
        XCTAssertEqual(withTarget.selected.map(\.secret), without.selected.map(\.secret))
    }

    // MARK: - Invariants (property)

    /// The shaped change always sums to exactly the change amount and uses only
    /// power-of-two denominations — so it can feed `preferredReturnDistribution`
    /// without a `preferredDistributionMismatch`.
    func testChangeOutputAmountsAlwaysSumToChangeAmount_random() throws {
        var rng = SeededRNG(seed: 0xC0FFEE)
        var sawChange = false
        for _ in 0..<1500 {
            let wallet = (0..<(Int(rng.next() % 8) + 1)).map { _ in 1 << Int(rng.next() % 11) }
            let total = sum(wallet)
            let target = Int(rng.next() % UInt64(max(1, total)))   // < total ⇒ feasible
            guard target > 0 else { continue }
            let r = try CashuSwift.selectProofs(proofs(wallet), targetAmount: target, mint: m,
                                                unit: "sat", purpose: .swap,
                                                denominationTarget: .default)
            XCTAssertEqual(sum(r.changeOutputAmounts), r.changeAmount)
            XCTAssertTrue(r.changeOutputAmounts.allSatisfy(isPowerOfTwo))
            if r.changeAmount > 0 { sawChange = true }
        }
        XCTAssertTrue(sawChange, "test should have exercised the change path")
    }

    /// The crux regression: supplying a target must NOT change which proofs are
    /// selected, the fee, the change amount, or the send outputs — only the change
    /// output denominations. Input selection optimality is fully preserved.
    func testTargetDoesNotAlterInputSelection_random() throws {
        var rng = SeededRNG(seed: 0x5151)
        for _ in 0..<1500 {
            let wallet = (0..<(Int(rng.next() % 10) + 1)).map { _ in 1 << Int(rng.next() % 12) }
            let total = sum(wallet)
            let target = Int(rng.next() % UInt64(max(1, total)))
            guard target > 0 else { continue }
            for purpose in [CashuSwift.ProofSelectionPurpose.swap, .tokenTransferUnlocked] {
                let a = try CashuSwift.selectProofs(proofs(wallet), targetAmount: target, mint: m,
                                                    unit: "sat", purpose: purpose)
                let b = try CashuSwift.selectProofs(proofs(wallet), targetAmount: target, mint: m,
                                                    unit: "sat", purpose: purpose,
                                                    denominationTarget: .default)
                XCTAssertEqual(a.kind, b.kind)
                XCTAssertEqual(a.selected.map(\.secret), b.selected.map(\.secret))
                XCTAssertEqual(a.inputFee, b.inputFee)
                XCTAssertEqual(a.changeAmount, b.changeAmount)
                XCTAssertEqual(a.netAmount, b.netAmount)
                XCTAssertEqual(a.sendOutputAmounts, b.sendOutputAmounts)
            }
        }
    }

    // MARK: - Value demonstration

    /// The shaped change leaves the wallet closer to its ideal shape than a base-2
    /// change would, when small denominations are depleted.
    func testTargetAwareChangeReducesGapVersusBase2() throws {
        let keyset = ks()
        let r = try CashuSwift.selectProofs(proofs([512, 512, 512, 512]), targetAmount: 503,
                                            mint: m, unit: "sat", purpose: .swap,
                                            denominationTarget: .default)
        XCTAssertEqual(r.changeAmount, 9)
        let retainedAfterSpend = proofs(Array(repeating: 512, count: 3))   // 3 unselected 512s

        let gapTarget = CashuSwift.denominationGap(
            for: retainedAfterSpend + proofs(r.changeOutputAmounts), keyset: keyset).distance
        let gapBase2 = CashuSwift.denominationGap(
            for: retainedAfterSpend + proofs(CashuSwift.splitIntoBase2Numbers(9)), keyset: keyset).distance

        XCTAssertTrue(r.changeOutputAmounts.contains(1), "should rebuild small denominations")
        XCTAssertLessThan(gapTarget, gapBase2)
    }

    // MARK: - Degenerate

    /// With fees on the keyset, the target still only shapes change; the fee-bearing
    /// selection is unchanged and the change still sums correctly.
    func testTargetWithFeesKeepsChangeExact() throws {
        let feeMint = mint([ks("00bb", ppk: 100)])
        let r = try CashuSwift.selectProofs(proofs([64, 64, 64], keysetID: "00bb"),
                                            targetAmount: 100, mint: feeMint, unit: "sat",
                                            purpose: .swap, denominationTarget: .default)
        XCTAssertGreaterThan(r.inputFee, 0)
        XCTAssertEqual(sum(r.changeOutputAmounts), r.changeAmount)
        XCTAssertEqual(r.netAmount, sum(r.selected.map(\.amount)) - r.inputFee)
    }
}
