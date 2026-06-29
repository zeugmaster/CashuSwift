//
//  DistributionPlanningTests.swift
//  CashuSwiftTests
//
//  Pure unit tests for the denomination-distribution planner — no network.
//  Covers the helpers, the ideal-shape / fill / gap algorithms, their exact-sum
//  and valid-denomination invariants, the both-directions gap metric, degenerate
//  inputs, keyset-driven denomination caps, and randomized property tests.
//

import XCTest
@testable import CashuSwift

// MARK: - Fixtures

/// Builds a `Keyset` whose `keys` enumerate the given denominations (decoding
/// minimal JSON — the model has a custom `Decodable` init and no memberwise init).
private func keyset(denominations: [Int] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512,
                                            1024, 2048, 4096, 8192, 16384, 32768,
                                            65536, 131072, 262144, 524288, 1048576],
                    id: String = "00deadbeef0000",
                    unit: String = "sat",
                    active: Bool = true) -> CashuSwift.Keyset {
    let keysJSON = denominations.map { "\"\($0)\":\"02aa\"" }.joined(separator: ",")
    let json = """
    {"id":"\(id)","unit":"\(unit)","active":\(active),"input_fee_ppk":0,"keys":{\(keysJSON)}}
    """
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

/// A keyset with the empty-string placeholder keys (state before keys are loaded).
private func placeholderKeyset() -> CashuSwift.Keyset {
    let json = #"{"id":"00deadbeef0000","unit":"sat","active":true,"input_fee_ppk":0}"#
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

/// A minimal wallet-side proof type.
private struct P: ProofRepresenting {
    let keysetID: String
    let C: String
    let secret: String
    let amount: Int
    let dleq: CashuSwift.DLEQ?
}

private func proofs(_ amounts: [Int], keysetID: String = "00deadbeef0000") -> [P] {
    amounts.enumerated().map {
        P(keysetID: keysetID, C: "C\($0.offset)", secret: "s\($0.offset)",
          amount: $0.element, dleq: nil)
    }
}

private func isPowerOfTwo(_ n: Int) -> Bool { n > 0 && (n & (n - 1)) == 0 }
private func sum(_ xs: [Int]) -> Int { xs.reduce(0, +) }

/// SplitMix64 — deterministic RNG for property tests.
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

final class DistributionPlanningTests: XCTestCase {

    private let fullKeyset = keyset()

    // MARK: - Helpers: powersOfTwo / topBitDenomination

    func testPowersOfTwo() {
        XCTAssertEqual(CashuSwift.powersOfTwo(upTo: 0), [])
        XCTAssertEqual(CashuSwift.powersOfTwo(upTo: 1), [1])
        XCTAssertEqual(CashuSwift.powersOfTwo(upTo: 7), [1, 2, 4])
        XCTAssertEqual(CashuSwift.powersOfTwo(upTo: 8), [1, 2, 4, 8])
        XCTAssertEqual(CashuSwift.powersOfTwo(upTo: 100), [1, 2, 4, 8, 16, 32, 64])
    }

    func testTopBitDenomination() {
        XCTAssertEqual(CashuSwift.topBitDenomination(0), 0)
        XCTAssertEqual(CashuSwift.topBitDenomination(-5), 0)
        XCTAssertEqual(CashuSwift.topBitDenomination(1), 1)
        XCTAssertEqual(CashuSwift.topBitDenomination(2), 2)
        XCTAssertEqual(CashuSwift.topBitDenomination(3), 2)
        XCTAssertEqual(CashuSwift.topBitDenomination(7), 4)
        XCTAssertEqual(CashuSwift.topBitDenomination(8), 8)
        XCTAssertEqual(CashuSwift.topBitDenomination(5000), 4096)
        XCTAssertEqual(CashuSwift.topBitDenomination(1 << 40), 1 << 40)
    }

    // MARK: - Helpers: counts / flatten

    func testCountsBucketsByAmountAndIgnoresZero() {
        let c = CashuSwift.counts(of: proofs([1, 1, 2, 4, 4, 4, 0]))
        XCTAssertEqual(c, [1: 2, 2: 1, 4: 3])
    }

    func testCountsEmpty() {
        XCTAssertEqual(CashuSwift.counts(of: [P]()), [:])
    }

    func testFlattenAscendingWithRepetition() {
        XCTAssertEqual(CashuSwift.flatten([4: 2, 1: 3, 2: 1]), [1, 1, 1, 2, 4, 4])
        XCTAssertEqual(CashuSwift.flatten([:]), [])
        XCTAssertEqual(CashuSwift.flatten([8: 0, 2: 1]), [2])   // zero counts dropped
    }

    func testCountsFlattenRoundTrip() {
        let amounts = [1, 1, 1, 2, 8, 8, 64]
        XCTAssertEqual(CashuSwift.flatten(CashuSwift.counts(of: proofs(amounts))), amounts.sorted())
    }

    // MARK: - Helpers: supportedDenominations / denominationBasis

    func testSupportedDenominationsParsesPowersOfTwo() {
        XCTAssertEqual(CashuSwift.supportedDenominations(of: keyset(denominations: [1, 2, 4, 8, 16])),
                       [1, 2, 4, 8, 16])
    }

    func testSupportedDenominationsFiltersNonPowersOfTwoAndPlaceholder() {
        // 3, 5, 6 are not powers of two and must be dropped; placeholder "" too.
        let ks = keyset(denominations: [1, 2, 3, 4, 5, 6, 8])
        XCTAssertEqual(CashuSwift.supportedDenominations(of: ks), [1, 2, 4, 8])
        XCTAssertEqual(CashuSwift.supportedDenominations(of: placeholderKeyset()), [])
    }

    func testDenominationBasisAppliesCap() {
        XCTAssertEqual(CashuSwift.denominationBasis(keyset: fullKeyset, cap: 16), [1, 2, 4, 8, 16])
    }

    func testDenominationBasisFallsBackToPowersOfTwoWhenKeysetEmpty() {
        // No usable keys ⇒ synthesize powers of two up to the cap (always includes 1).
        XCTAssertEqual(CashuSwift.denominationBasis(keyset: placeholderKeyset(), cap: 8),
                       [1, 2, 4, 8])
    }

    // MARK: - idealCounts / idealDistribution: hand-computed cases

    func testIdealDistributionSmallBalances() {
        // Small-first redundancy: tiny balances prefer multiple 1s over a single larger
        // coin (more independent small offline payments), capped at N.
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 0, keyset: fullKeyset), [])
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 1, keyset: fullKeyset), [1])
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 2, keyset: fullKeyset), [1, 1])
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 3, keyset: fullKeyset), [1, 1, 1])
        // balance 4: three deficit 1s (=3) + a remainder 1 ⇒ four 1s.
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 4, keyset: fullKeyset), [1, 1, 1, 1])
        // balance 5: three 1s (=3) then a 2 fits the remainder ⇒ a 2 finally appears.
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 5, keyset: fullKeyset), [1, 1, 1, 2])
    }

    func testIdealDistributionN1MatchesBase2OnFullCovers() {
        // For balance == 2^k - 1, one-of-each ascending reproduces the base-2 split.
        let t = CashuSwift.DenominationTarget(countPerDenomination: 1)
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 7, target: t, keyset: fullKeyset),
                       [1, 2, 4])
        XCTAssertEqual(CashuSwift.idealDistribution(balance: 15, target: t, keyset: fullKeyset),
                       [1, 2, 4, 8])
    }

    func testIdealCountsRedundancyOnSmallDenominations() {
        // Large balance ⇒ small denominations reach the cap N, bulk lands on large denoms.
        let basis = CashuSwift.powersOfTwo(upTo: 1024)
        let ideal = CashuSwift.idealCounts(balance: 100_000,
                                           target: CashuSwift.DenominationTarget(countPerDenomination: 3),
                                           denominations: basis)
        // Every small denomination is held at least N times.
        for d in [1, 2, 4, 8, 16, 32, 64, 128, 256, 512] {
            XCTAssertGreaterThanOrEqual(ideal[d] ?? 0, 3, "expected ≥3 of denom \(d)")
        }
        // The largest denomination soaks up the remainder (far beyond N).
        XCTAssertGreaterThan(ideal[1024] ?? 0, 3)
        // Exact and within basis.
        XCTAssertEqual(basis.reduce(0) { $0 + $1 * (ideal[$1] ?? 0) }, 100_000)
    }

    func testIdealDistributionRespectsKeysetMaxDenomination() {
        // Keyset only offers up to 1024, but the balance's top bit is 8192.
        let ks = keyset(denominations: [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024])
        let dist = CashuSwift.idealDistribution(balance: 10_000, keyset: ks)
        XCTAssertEqual(sum(dist), 10_000)
        XCTAssertTrue(dist.allSatisfy { $0 <= 1024 }, "must not exceed keyset's max denomination")
        XCTAssertTrue(dist.allSatisfy(isPowerOfTwo))
    }

    func testIdealDistributionN0AbsorbsIntoLargestDenominations() {
        // N = 0 disables the soft fill; remainder absorption is greedy descending.
        let t = CashuSwift.DenominationTarget(countPerDenomination: 0)
        let dist = CashuSwift.idealDistribution(balance: 100, target: t, keyset: fullKeyset)
        XCTAssertEqual(sum(dist), 100)
        XCTAssertEqual(dist, CashuSwift.splitIntoBase2Numbers(100).sorted())  // == minimal base-2
    }

    // MARK: - idealDistribution: invariants (property)

    func testIdealDistributionExactSumAndValidDenoms_exhaustive() {
        for n in [0, 1, 2, 3, 5, 8] {
            let t = CashuSwift.DenominationTarget(countPerDenomination: n)
            for balance in 0...512 {
                let dist = CashuSwift.idealDistribution(balance: balance, target: t, keyset: fullKeyset)
                XCTAssertEqual(sum(dist), balance, "N=\(n) balance=\(balance)")
                let cap = CashuSwift.topBitDenomination(balance)
                XCTAssertTrue(dist.allSatisfy { isPowerOfTwo($0) && $0 <= cap },
                              "N=\(n) balance=\(balance) produced invalid denom in \(dist)")
            }
        }
    }

    func testIdealDistributionExactSum_randomLargeBalances() {
        var rng = SeededRNG(seed: 0xA11CE)
        for _ in 0..<2000 {
            let balance = Int(rng.next() % 50_000_000)
            let n = [1, 2, 3, 4, 6][Int(rng.next() % 5)]
            let t = CashuSwift.DenominationTarget(countPerDenomination: n)
            let dist = CashuSwift.idealDistribution(balance: balance, target: t, keyset: fullKeyset)
            XCTAssertEqual(sum(dist), balance)
            XCTAssertTrue(dist.allSatisfy(isPowerOfTwo))
        }
    }

    /// End-to-end: a wallet holding *exactly* the ideal shape has zero gap.
    func testIdealShapeHasZeroGap() {
        for balance in [1, 7, 50, 100, 333, 1000, 99_999] {
            let ideal = CashuSwift.idealDistribution(balance: balance, keyset: fullKeyset)
            let gap = CashuSwift.denominationGap(for: proofs(ideal), keyset: fullKeyset)
            XCTAssertEqual(gap.distance, 0, "balance=\(balance) ideal should be at target")
            XCTAssertTrue(gap.deficits.isEmpty)
            XCTAssertTrue(gap.surplus.isEmpty)
        }
    }

    // MARK: - fillDistribution: hand-computed cases

    func testFillFromEmptyReproducesIdeal() {
        let ideal = [1: 3, 2: 3, 4: 3]                      // sum 21
        let out = CashuSwift.fillDistribution(amount: 21, retained: [:], ideal: ideal,
                                              denominations: [1, 2, 4, 8])
        XCTAssertEqual(out, [1, 1, 1, 2, 2, 2, 4, 4, 4])
    }

    func testFillPrioritizesDeficitsSmallestFirst() {
        // Need denom 1 (deficit 1), rest absorbed as fewest coins.
        let out = CashuSwift.fillDistribution(amount: 3, retained: [:], ideal: [1: 1],
                                              denominations: [1, 2, 4])
        XCTAssertEqual(sum(out), 3)
        XCTAssertEqual(out, [1, 2])   // one deficit-1, remainder 2 absorbed as a single 2
    }

    func testFillDoesNotPileOntoSurplusWhileDeficitsRemain() {
        // denom 4 is already in heavy surplus; filling should target the deficits (1, 2)
        // and never add another 4. Trace: three 1s + one 2 satisfy deficits (rem 1),
        // then the trailing 1 sat can only be absorbed as a fourth 1.
        let retained = [4: 10]
        let ideal = [1: 3, 2: 3, 4: 3, 8: 3]
        let out = CashuSwift.fillDistribution(amount: 6, retained: retained, ideal: ideal,
                                              denominations: [1, 2, 4, 8])
        XCTAssertEqual(sum(out), 6)
        XCTAssertFalse(out.contains(4), "must not add to the already-surplus denom 4: \(out)")
        XCTAssertEqual(CashuSwift.counts(of: proofs(out)), [1: 4, 2: 1])
    }

    func testFillRemainderStaysWithinBasis() {
        // ideal capped at denom 4; a large amount must still decompose within [1,2,4].
        let out = CashuSwift.fillDistribution(amount: 1000, retained: [:],
                                              ideal: [1: 3, 2: 3, 4: 3],
                                              denominations: [1, 2, 4])
        XCTAssertEqual(sum(out), 1000)
        XCTAssertTrue(out.allSatisfy { [1, 2, 4].contains($0) })
    }

    // MARK: - fillDistribution: invariants (property)

    func testFillExactSumAndValidDenoms_random() {
        var rng = SeededRNG(seed: 0xF111)
        let basis = CashuSwift.powersOfTwo(upTo: 4096)
        for _ in 0..<3000 {
            // Random retained inventory.
            var retained: [Int: Int] = [:]
            for d in basis where rng.next() % 3 == 0 { retained[d] = Int(rng.next() % 6) }
            let n = [1, 2, 3, 4][Int(rng.next() % 4)]
            let retainedSum = retained.reduce(0) { $0 + $1.key * $1.value }
            let amount = Int(rng.next() % 20_000) + 1
            let ideal = CashuSwift.idealCounts(balance: retainedSum + amount,
                                               target: CashuSwift.DenominationTarget(countPerDenomination: n),
                                               denominations: basis)
            let out = CashuSwift.fillDistribution(amount: amount, retained: retained,
                                                  ideal: ideal, denominations: basis)
            XCTAssertEqual(sum(out), amount)
            XCTAssertTrue(out.allSatisfy { basis.contains($0) })
        }
    }

    // MARK: - preferredDistribution (public)

    func testPreferredDistributionExactSum() {
        let out = CashuSwift.preferredDistribution(forAmount: 137,
                                                   retained: proofs([1, 1, 64, 64]),
                                                   keyset: fullKeyset)
        XCTAssertEqual(sum(out), 137)
        XCTAssertTrue(out.allSatisfy(isPowerOfTwo))
    }

    func testPreferredDistributionEmptyRetainedEqualsIdeal() {
        for amount in [1, 13, 100, 4242] {
            let pref = CashuSwift.preferredDistribution(forAmount: amount, retained: [P](),
                                                        keyset: fullKeyset)
            let ideal = CashuSwift.idealDistribution(balance: amount, keyset: fullKeyset)
            XCTAssertEqual(pref, ideal, "amount=\(amount)")
        }
    }

    func testPreferredDistributionZeroAmount() {
        XCTAssertEqual(CashuSwift.preferredDistribution(forAmount: 0, retained: proofs([1, 2]),
                                                        keyset: fullKeyset), [])
    }

    /// Universal invariant: minting `amount` new proofs via the preferred split
    /// never *increases* any denomination's deficit, and reduces the total deficit
    /// by at most `amount` (each filled deficit-coin costs ≥1 sat). Holds for every
    /// retained inventory and amount — adding non-negative coins can only help.
    func testPreferredFillIsMonotoneOnDeficit_random() {
        var rng = SeededRNG(seed: 0x6A9)
        for _ in 0..<3000 {
            var retained: [Int: Int] = [:]
            for d in CashuSwift.powersOfTwo(upTo: 4096) where rng.next() % 3 == 0 {
                retained[d] = Int(rng.next() % 5)
            }
            let retainedProofs = proofs(CashuSwift.flatten(retained))
            let amount = Int(rng.next() % 20_000) + 1

            let out = CashuSwift.preferredDistribution(forAmount: amount,
                                                       retained: retainedProofs, keyset: fullKeyset)
            XCTAssertEqual(sum(out), amount)

            // Same projected-balance ideal the planner used internally.
            let retainedSum = retained.reduce(0) { $0 + $1.key * $1.value }
            let ideal = CashuSwift.idealCounts(
                balance: retainedSum + amount,
                target: .default,
                denominations: CashuSwift.denominationBasis(
                    keyset: fullKeyset, cap: CashuSwift.topBitDenomination(retainedSum + amount)))
            let outCounts = CashuSwift.counts(of: proofs(out))

            func totalDeficit(_ have: [Int: Int]) -> Int {
                ideal.reduce(0) { $0 + max(0, $1.value - (have[$1.key] ?? 0)) }
            }
            var combined = retained
            for (d, c) in outCounts { combined[d, default: 0] += c }

            let before = totalDeficit(retained)
            let after = totalDeficit(combined)
            XCTAssertLessThanOrEqual(after, before)              // never increases deficit
            XCTAssertGreaterThanOrEqual(after, before - amount)  // can't over-fill
        }
    }

    /// The motivating case: a wallet drained of small denominations (only large
    /// coins) is moved *closer* to the ideal by the target-aware split than by a
    /// plain base-2 split, because the fill rebuilds the depleted small coins while
    /// base-2 of a power-of-two amount just mints one more large coin.
    func testPreferredBeatsBase2WhenSmallDenominationsDepleted() {
        let retained = proofs([512, 512, 512, 512])           // no small denominations
        let amount = 8

        let preferred = CashuSwift.preferredDistribution(forAmount: amount,
                                                         retained: retained, keyset: fullKeyset)
        let base2 = CashuSwift.splitIntoBase2Numbers(amount) // == [8]

        XCTAssertEqual(sum(preferred), amount)
        XCTAssertTrue(preferred.contains(1), "should rebuild depleted small denominations")

        let gapPreferred = CashuSwift.denominationGap(for: retained + proofs(preferred),
                                                      keyset: fullKeyset).distance
        let gapBase2 = CashuSwift.denominationGap(for: retained + proofs(base2),
                                                  keyset: fullKeyset).distance
        XCTAssertLessThan(gapPreferred, gapBase2)
    }

    // MARK: - denominationGap: both directions

    func testGapDetectsDeficits() {
        // Only large coins held ⇒ small denominations are in deficit.
        let gap = CashuSwift.denominationGap(for: proofs([64, 64, 64]), keyset: fullKeyset)
        XCTAssertGreaterThan(gap.distance, 0)
        XCTAssertFalse(gap.deficits.isEmpty)
        XCTAssertGreaterThan(gap.deficits[1] ?? 0, 0, "should want some 1s it doesn't have")
    }

    func testGapDetectsSurplus() {
        // Far more 1s than any sane target ⇒ surplus on denom 1.
        let gap = CashuSwift.denominationGap(for: proofs(Array(repeating: 1, count: 50)),
                                             keyset: fullKeyset)
        XCTAssertGreaterThan(gap.surplus[1] ?? 0, 0)
        XCTAssertGreaterThan(gap.distance, 0)
    }

    func testGapBothDirectionsSimultaneously() {
        // Surplus of 4s, total deficit of small/other denoms.
        let gap = CashuSwift.denominationGap(for: proofs(Array(repeating: 4, count: 20)),
                                             keyset: fullKeyset)
        XCTAssertFalse(gap.surplus.isEmpty, "20×4 over target on denom 4")
        XCTAssertFalse(gap.deficits.isEmpty, "missing 1s/2s/etc.")
        XCTAssertEqual(gap.distance,
                       gap.deficits.values.reduce(0, +) + gap.surplus.values.reduce(0, +))
    }

    func testGapEmptyAndZeroBalance() {
        XCTAssertEqual(CashuSwift.denominationGap(for: [P](), keyset: fullKeyset).distance, 0)
        XCTAssertEqual(CashuSwift.denominationGap(for: proofs([0]), keyset: fullKeyset).distance, 0)
    }

    // MARK: - Degenerate keysets

    func testPlanningWithPlaceholderKeysetStillExact() {
        // Keys not loaded ⇒ basis falls back to powers of two; everything still sums.
        let ks = placeholderKeyset()
        XCTAssertEqual(sum(CashuSwift.idealDistribution(balance: 1234, keyset: ks)), 1234)
        let pref = CashuSwift.preferredDistribution(forAmount: 555, retained: proofs([8, 8]), keyset: ks)
        XCTAssertEqual(sum(pref), 555)
    }

    func testNonPowerOfTwoKeysetDenominationsIgnoredGracefully() {
        // A keyset that (oddly) lists only non-powers-of-two ⇒ fall back, stay exact.
        let ks = keyset(denominations: [3, 5, 6, 7])
        XCTAssertEqual(CashuSwift.supportedDenominations(of: ks), [])
        XCTAssertEqual(sum(CashuSwift.idealDistribution(balance: 99, keyset: ks)), 99)
    }

    // MARK: - DenominationTarget

    func testDenominationTargetDefaults() {
        XCTAssertEqual(CashuSwift.DenominationTarget.default.countPerDenomination, 3)
        XCTAssertNil(CashuSwift.DenominationTarget.default.maxDenomination)
    }

    func testDenominationTargetClampsNegativeCount() {
        XCTAssertEqual(CashuSwift.DenominationTarget(countPerDenomination: -4).countPerDenomination, 0)
    }

    func testExplicitMaxDenominationCapsTarget() {
        let t = CashuSwift.DenominationTarget(countPerDenomination: 3, maxDenomination: 8)
        let dist = CashuSwift.idealDistribution(balance: 10_000, target: t, keyset: fullKeyset)
        XCTAssertEqual(sum(dist), 10_000)
        XCTAssertTrue(dist.allSatisfy { $0 <= 8 }, "explicit cap must bound denominations")
    }
}
