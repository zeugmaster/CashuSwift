//
//  DistributionPlanning.swift
//  CashuSwift
//
//  Denomination-distribution planning for offline-send optimization.
//
//  A Cashu token is just a bundle of proofs, and an *offline* (unlocked) send of
//  amount `X` is possible iff the wallet already holds a subset of proofs summing
//  to exactly `X` — making change requires a swap round-trip to the mint. The
//  lever for making that true as often as possible is the wallet's *denomination
//  shape*: hold roughly `N` proofs of each power-of-two denomination so that exact
//  subsets exist for most amounts, repeatedly.
//
//  This file is the pure, deterministic math behind that idea. It computes:
//
//    * `idealDistribution(balance:…)` — the most offline-friendly partition of a
//      balance into powers of two under a per-denomination cap `N`.
//    * `preferredDistribution(forAmount:retained:…)` — the split for `amount` new
//      proofs that best moves a retained inventory *toward* the ideal (fills
//      deficits). The caller feeds it into an operation's `preferredDistribution`
//      hook.
//    * `denominationGap(for:…)` — how far a proof set is from its ideal, in both
//      directions (deficits *and* surplus), so a wallet can decide whether a
//      fee-incurring consolidation swap is worthwhile.
//
//  No networking, crypto, or randomness — given the same inputs the output is
//  identical. Policy (the value of `N`, when to rebalance) belongs to the wallet;
//  only the math lives here.
//
//  Note on direction: a single output split can only *add* coins, so it can fill
//  deficits but never remove a surplus. Surpluses are drained by spending
//  over-represented denominations as inputs (an input-selection concern handled in
//  `ProofSelection`) or by a full-balance consolidation swap. `denominationGap`
//  measures both directions so the wallet can drive that decision.
//

import Foundation

extension CashuSwift {

    // MARK: - Policy

    /// The target denomination shape a wallet wants to maintain so that exact
    /// (offline-sendable) subsets exist for as many amounts as possible.
    public struct DenominationTarget: Sendable, Equatable {
        /// Desired number of proofs to hold of each denomination (`N`). Higher ⇒
        /// more independent offline payments before a rebalance, at the cost of
        /// more proofs (bigger tokens, higher future per-proof input fees).
        public var countPerDenomination: Int
        /// Optional cap on the largest denomination to target. `nil` ⇒ the largest
        /// power of two the balance can afford (its top bit), so the usable range
        /// grows with the balance.
        public var maxDenomination: Int?

        public init(countPerDenomination: Int = 3, maxDenomination: Int? = nil) {
            self.countPerDenomination = max(0, countPerDenomination)
            self.maxDenomination = maxDenomination
        }

        public static let `default` = DenominationTarget()
    }

    // MARK: - Gap

    /// How far a proof set is from its target shape, in both directions.
    public struct DenominationGap: Sendable, Equatable {
        /// denomination → how many proofs *short* of the target.
        public let deficits: [Int: Int]
        /// denomination → how many proofs *over* the target.
        public let surplus: [Int: Int]
        /// Total proofs away from the target: `Σ deficits + Σ surplus` (L1 in coin
        /// counts). `0` ⇒ exactly at target. A wallet can threshold on this to
        /// decide whether a consolidation swap is worthwhile.
        public let distance: Int

        public init(deficits: [Int: Int], surplus: [Int: Int], distance: Int) {
            self.deficits = deficits
            self.surplus = surplus
            self.distance = distance
        }
    }

    // MARK: - Public API

    /// The ideal denomination shape for `balance`, as a flat, ascending list of
    /// amounts that sum exactly to `balance`.
    ///
    /// Suitable to pass directly as a `preferredReturnDistribution` when swapping
    /// the whole balance to normalize its shape (a consolidation swap).
    ///
    /// - Parameters:
    ///   - balance: The total amount to partition (e.g. a swap's total output).
    ///   - target: The desired per-denomination count and optional max denomination.
    ///   - keyset: Supplies the supported (power-of-two) denominations.
    /// - Returns: Amounts summing to `balance`; empty if `balance <= 0`.
    public static func idealDistribution(balance: Int,
                                         target: DenominationTarget = .default,
                                         keyset: Keyset) -> [Int] {
        guard balance > 0 else { return [] }
        let basis = denominationBasis(keyset: keyset,
                                      cap: target.maxDenomination ?? topBitDenomination(balance))
        guard !basis.isEmpty else { return splitIntoBase2Numbers(balance) }
        return flatten(idealCounts(balance: balance, target: target, denominations: basis))
    }

    /// The denomination split for `amount` newly-minted proofs that best moves the
    /// wallet's `retained` inventory toward `target` (fills the largest deficits
    /// first). Use this for operations that produce new proofs without selecting
    /// the wallet's own proofs as inputs — `receive` and `mint`.
    ///
    /// For operations that *do* select inputs (`send`/swap/consolidation), prefer
    /// `selectProofs(…, denominationTarget:)`, which has the full proof set and can
    /// drain surpluses through input selection as well.
    ///
    /// The result is guaranteed to sum to exactly `amount`, so it is safe to pass
    /// into a `preferredDistribution` parameter without a mismatch.
    ///
    /// - Parameters:
    ///   - amount: The sum to materialize as new outputs.
    ///   - retained: The proofs that will remain after the operation (the wallet's
    ///     current valid proofs for this mint/unit; nothing is spent by receive/mint).
    ///   - target: The desired shape.
    ///   - keyset: Supplies the supported denominations.
    public static func preferredDistribution(forAmount amount: Int,
                                             retained: [some ProofRepresenting],
                                             target: DenominationTarget = .default,
                                             keyset: Keyset) -> [Int] {
        guard amount > 0 else { return [] }
        let retainedCounts = counts(of: retained)
        let retainedSum = retainedCounts.reduce(0) { $0 + $1.key * $1.value }
        // The ideal is computed against the projected post-operation balance, since
        // the new outputs add to what is retained.
        let projected = retainedSum + amount
        let basis = denominationBasis(keyset: keyset,
                                      cap: target.maxDenomination ?? topBitDenomination(projected))
        guard !basis.isEmpty else { return splitIntoBase2Numbers(amount) }
        let ideal = idealCounts(balance: projected, target: target, denominations: basis)
        return fillDistribution(amount: amount, retained: retainedCounts,
                                ideal: ideal, denominations: basis)
    }

    /// Measures how far `proofs` are from `target`, in both directions, so a wallet
    /// can decide whether to consolidate. The ideal is evaluated against the
    /// current balance (`Σ proofs.amount`).
    public static func denominationGap(for proofs: [some ProofRepresenting],
                                       target: DenominationTarget = .default,
                                       keyset: Keyset) -> DenominationGap {
        let have = counts(of: proofs)
        let balance = have.reduce(0) { $0 + $1.key * $1.value }
        guard balance > 0 else { return DenominationGap(deficits: [:], surplus: [:], distance: 0) }
        let basis = denominationBasis(keyset: keyset,
                                      cap: target.maxDenomination ?? topBitDenomination(balance))
        guard !basis.isEmpty else { return DenominationGap(deficits: [:], surplus: [:], distance: 0) }
        let ideal = idealCounts(balance: balance, target: target, denominations: basis)

        var deficits: [Int: Int] = [:]
        var surplus: [Int: Int] = [:]
        var distance = 0
        for d in Set(have.keys).union(ideal.keys) {
            let want = ideal[d] ?? 0
            let has = have[d] ?? 0
            if want > has {
                deficits[d] = want - has
                distance += want - has
            } else if has > want {
                surplus[d] = has - want
                distance += has - want
            }
        }
        return DenominationGap(deficits: deficits, surplus: surplus, distance: distance)
    }

    // MARK: - Internal math (kept internal: reachable from tests via @testable,
    //         but not part of the public surface — callers go through the API above)

    /// Buckets proofs by amount: `amount → count`. Ignores non-positive amounts.
    static func counts<P: ProofRepresenting>(of proofs: [P]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for p in proofs where p.amount > 0 { result[p.amount, default: 0] += 1 }
        return result
    }

    /// The power-of-two denominations a keyset offers, ascending. Parses the integer
    /// amount keys of `keyset.keys` and keeps only positive powers of two — this
    /// naturally drops the empty-string placeholder used before keys are loaded, as
    /// well as any non-power-of-two entries.
    static func supportedDenominations(of keyset: Keyset) -> [Int] {
        keyset.keys.keys
            .compactMap { Int($0) }
            .filter { $0 > 0 && ($0 & ($0 - 1)) == 0 }
            .sorted()
    }

    /// The effective denomination basis to plan over: the keyset's supported
    /// denominations no greater than `cap`, or — if the keyset enumerates none
    /// (keys not yet loaded) — synthesized powers of two up to `cap`. Always
    /// includes `1` in the fallback, guaranteeing exact decomposition.
    static func denominationBasis(keyset: Keyset, cap: Int) -> [Int] {
        let supported = supportedDenominations(of: keyset).filter { $0 <= cap }
        return supported.isEmpty ? powersOfTwo(upTo: cap) : supported
    }

    /// Powers of two `1, 2, 4, …` up to and including `cap` (empty if `cap < 1`).
    static func powersOfTwo(upTo cap: Int) -> [Int] {
        guard cap >= 1 else { return [] }
        var result: [Int] = []
        var d = 1
        while d <= cap {
            result.append(d)
            d <<= 1
        }
        return result
    }

    /// The largest power of two `≤ n` (its top set bit); `0` for `n <= 0`.
    static func topBitDenomination(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return 1 << (Int.bitWidth - 1 - n.leadingZeroBitCount)
    }

    /// The ideal `denomination → count` shape for `balance`.
    ///
    /// Two passes over the (ascending) basis:
    ///   1. **Soft fill, small-first:** give each denomination up to `N` coins,
    ///      smallest first — front-loading redundancy on the small/medium
    ///      denominations that everyday offline payments deplete.
    ///   2. **Remainder absorption, large-first:** whatever budget is left (because
    ///      `N` of each was already met, or larger denominations were capped) is
    ///      soaked up by the largest denominations, exceeding `N` where needed.
    ///
    /// Sums to exactly `balance` provided the basis includes `1` (always true for a
    /// real keyset and for the synthesized fallback).
    static func idealCounts(balance: Int,
                            target: DenominationTarget,
                            denominations: [Int]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var remaining = balance

        let n = target.countPerDenomination
        if n > 0 {
            for d in denominations {           // ascending
                guard remaining >= d else { continue }
                let add = min(n, remaining / d)
                if add > 0 {
                    result[d, default: 0] += add
                    remaining -= add * d
                }
            }
        }

        for d in denominations.reversed() {    // descending
            guard remaining >= d else { continue }
            let add = remaining / d
            result[d, default: 0] += add
            remaining -= add * d
        }
        return result
    }

    /// The split for `amount` new outputs that best fills the deficit between
    /// `retained` and `ideal`.
    ///
    ///   1. **Fill deficits, small-first:** create the under-represented
    ///      denominations the wallet is short of, smallest first.
    ///   2. **Absorb the remainder, large-first:** any budget beyond the total
    ///      deficit (which is small — the ideal is sized for the projected balance)
    ///      is emitted as the fewest possible coins, minimizing how much it adds to
    ///      any already-satisfied denomination.
    ///
    /// Sums to exactly `amount` (basis includes `1`). Fills deficits only — it
    /// cannot remove a surplus; that is the job of input selection / consolidation.
    static func fillDistribution(amount: Int,
                                 retained: [Int: Int],
                                 ideal: [Int: Int],
                                 denominations: [Int]) -> [Int] {
        var out: [Int: Int] = [:]
        var remaining = amount

        for d in denominations {               // ascending: satisfy explicit deficits
            guard remaining >= d else { continue }
            let deficit = max(0, (ideal[d] ?? 0) - (retained[d] ?? 0))
            guard deficit > 0 else { continue }
            let add = min(deficit, remaining / d)
            if add > 0 {
                out[d, default: 0] += add
                remaining -= add * d
            }
        }

        for d in denominations.reversed() {    // descending: absorb remainder in fewest coins
            guard remaining >= d else { continue }
            let add = remaining / d
            out[d, default: 0] += add
            remaining -= add * d
        }
        return flatten(out)
    }

    /// Flattens a `denomination → count` map into an ascending list of amounts.
    static func flatten(_ counts: [Int: Int]) -> [Int] {
        var result: [Int] = []
        for d in counts.keys.sorted() {
            let c = counts[d] ?? 0
            if c > 0 { result.append(contentsOf: repeatElement(d, count: c)) }
        }
        return result
    }
}
