//
//  ProofSelection.swift
//  CashuSwift
//
//  Fee-aware ecash proof selection — a single, self-contained selector that
//  chooses which existing proofs a wallet should spend for a given operation.
//
//  Design goals:
//
//    * Generic & identity-preserving ("select in place"). `selectProofs` is
//      generic over any `ProofRepresenting`; the result's `selected` array
//      holds the *caller's own* proof values (a subset of the input), never
//      copies. A dependent wallet never converts to/from `CashuSwift.Proof`.
//      The dynamic program runs entirely on integers and original indices, so
//      the concrete proof type is read only at the boundary — no existentials,
//      no downcasts, and no added `Hashable`/`Equatable` requirement on
//      `ProofRepresenting`.
//
//    * Pure & deterministic. No networking, crypto, or randomness. The caller
//      refreshes keysets, reserves proofs, and performs the swap/melt. Given
//      the same request + policy seed the result is identical.
//
//    * Exact. Direct (fee-free) sends use exact subset-sum DP; mint
//      transactions use a fee-aware Pareto bounded-knapsack that is provably
//      optimal under the documented comparator unless `policy.maxStates` is hit
//      (in which case optimality is reported truthfully).
//
//  NUT-02 input fees: fee(S) = ceil( Σ inputFeePPK(S) / 1000 ), paid only when
//  a mint transaction (swap/melt/receive/…) is required — never for a direct
//  token send of existing proofs.
//

import Foundation
import CryptoKit

extension CashuSwift {

    // MARK: - Public API

    /// Why proofs are being selected. Determines whether a zero-fee *direct*
    /// send of existing proofs is acceptable, or whether a fee-bearing *mint
    /// transaction* (swap/melt/…) is required.
    public enum ProofSelectionPurpose: Sendable, Equatable {
        case tokenTransferUnlocked
        case tokenTransferLocked
        case paymentRequest
        case swap
        case melt
        case receive
        case maintenanceRotation

        /// Whether an exact, fee-free subset of existing proofs may satisfy the
        /// request. Only an unlocked direct transfer can be fulfilled without a
        /// mint transaction; every other purpose mints new outputs and pays the
        /// NUT-02 input fee.
        var allowsDirectExact: Bool { self == .tokenTransferUnlocked }
    }

    /// Tunable selection behaviour. Defaults match the wallet policy from the
    /// implementation plan: prefer exact direct sends, then minimise actual fee,
    /// change, proof count, and raw amount, then keyset hygiene, then a stable
    /// deterministic tie-break.
    public struct ProofSelectionPolicy: Sendable {
        /// Try an exact, fee-free direct subset before fee-aware selection
        /// (only consulted for purposes whose `allowsDirectExact` is true).
        public var preferDirectExact: Bool
        /// For mint transactions, break otherwise-equal candidates by spending
        /// *inactive* keysets first (keyset hygiene). Never overrides
        /// fee/change/count/amount.
        public var preferInactiveKeysetsForMintTransactions: Bool
        /// For direct sends, break otherwise-equal candidates by keeping the
        /// recipient on *active* keysets. Never overrides proof-count/fee order.
        public var avoidInactiveKeysetsForDirectSend: Bool
        /// Guardrail on the fee-aware open-state count. `nil` disables the cap.
        public var maxStates: Int?
        /// When the state cap is hit: return the best feasible result found so
        /// far (`true`) or throw `.stateLimitExceeded` (`false`).
        public var bestEffortWhenStateLimitHit: Bool
        /// Stable per-request entropy for deterministic tie-breaking. Never
        /// serialized into tokens or sent to the mint. Empty ⇒ fixed ordering
        /// (handy for tests); supply randomness to rotate which equal-shaped
        /// proofs get spent over time.
        public var randomSeed: Data

        public init(preferDirectExact: Bool = true,
                    preferInactiveKeysetsForMintTransactions: Bool = false,
                    avoidInactiveKeysetsForDirectSend: Bool = false,
                    maxStates: Int? = 200_000,
                    bestEffortWhenStateLimitHit: Bool = false,
                    randomSeed: Data = Data()) {
            self.preferDirectExact = preferDirectExact
            self.preferInactiveKeysetsForMintTransactions = preferInactiveKeysetsForMintTransactions
            self.avoidInactiveKeysetsForDirectSend = avoidInactiveKeysetsForDirectSend
            self.maxStates = maxStates
            self.bestEffortWhenStateLimitHit = bestEffortWhenStateLimitHit
            self.randomSeed = randomSeed
        }

        public static let `default` = ProofSelectionPolicy()
    }

    /// Whether the result is a direct token send (no mint interaction) or a
    /// mint transaction (swap/melt) the caller must execute.
    public enum ProofSelectionKind: Sendable, Equatable { case directToken, mintTransaction }

    /// Whether the selection is mathematically proven optimal under the
    /// comparator, or a best-effort result returned because the state cap hit.
    public enum ProofSelectionOptimality: Sendable, Equatable { case provedOptimal, bestEffortStateLimitHit }

    /// Result of a selection.
    ///
    /// `selected` are the *caller's own* proof values — a subset of the array
    /// passed to `selectProofs`, never reconstructed — so a dependent wallet
    /// can reserve/spend them by identity without any type conversion.
    public struct ProofSelectionResult<P: ProofRepresenting> {
        public let kind: ProofSelectionKind
        /// The chosen proofs, a subset of the caller's input (ascending input order).
        public let selected: [P]
        /// NUT-02 input fee for `selected` (0 for a direct token send).
        public let inputFee: Int
        /// `Σ selected.amount − inputFee`.
        public let netAmount: Int
        /// `netAmount − targetAmount` (0 for a direct token send).
        public let changeAmount: Int
        /// Denomination split for the send/payment outputs (empty for direct).
        public let sendOutputAmounts: [Int]
        /// Denomination split for the change outputs (empty for direct / no change).
        public let changeOutputAmounts: [Int]
        /// NUT-08 blank-output amounts. Always empty here: melt callers size
        /// blanks via `generateBlankOutputs(quote:proofs:…)` from `selected`,
        /// reusing the library's vetted overpaid-fee-return logic rather than
        /// duplicating it (the selector does not know `quote.amount`).
        public let blankOutputAmounts: [Int]
        /// Keysets the selected proofs are drawn from.
        public let keysetIDsSpent: Set<String>
        public let optimality: ProofSelectionOptimality
    }

    public enum ProofSelectionError: Error, Sendable {
        /// No subset of eligible proofs can reach the target. Diagnostics avoid
        /// leaking secrets.
        case insufficientFunds(eligibleRawAmount: Int, requiredTarget: Int, purpose: ProofSelectionPurpose)
        /// Every input was filtered out (wrong unit, locked, zero-amount, …).
        case noEligibleProofs
        /// A proof's keyset could not be resolved against the provided mint —
        /// likely stale keyset data. The caller should refresh keysets and
        /// retry. Unknown fee info is never silently treated as 0.
        case missingKeysetInformation(keysetID: String)
        /// The fee-aware search exceeded `policy.maxStates` and best-effort
        /// fallback was disabled.
        case stateLimitExceeded
        /// `targetAmount` was negative.
        case invalidTarget
        case unsupportedPurpose(ProofSelectionPurpose)
    }

    /// Selects which existing proofs to spend for `purpose`.
    ///
    /// Identity-preserving: returns the caller's own `P` values (see
    /// `ProofSelectionResult.selected`).
    ///
    /// - Parameters:
    ///   - proofs: Candidate proofs. The wallet should pass unreserved proofs
    ///     for this `mint`/`unit`; reservation/concurrency is the caller's job.
    ///   - targetAmount: Amount to send/pay. For melt, pass
    ///     `quote.amount + feeReserve`; the selector's `net ≥ target` invariant
    ///     reproduces `Σ ≥ amount + feeReserve + inputFee`.
    ///   - mint: Source of per-keyset fee rates and active/inactive status.
    ///   - unit: The unit being spent (e.g. `"sat"`).
    ///   - purpose: Drives direct-vs-mint-transaction behaviour.
    ///   - policy: Tie-breaking knobs and guardrails.
    ///   - denominationTarget: Optional offline-optimization shape. When supplied,
    ///     selection moves toward the target in *both* directions: it prefers
    ///     spending over-represented (surplus) denominations as a low-priority
    ///     tie-breaker (never overriding fee/change/count), and it shapes
    ///     `changeOutputAmounts` to fill the wallet's denomination deficits instead
    ///     of a plain base-2 split. `nil` reproduces the prior base-2 behaviour
    ///     exactly. See `DistributionPlanning.swift`.
    /// - Returns: A `ProofSelectionResult` over the caller's proof type.
    /// - Throws: `ProofSelectionError` on infeasible / invalid / stale-keyset input.
    public static func selectProofs<P: ProofRepresenting>(
        _ proofs: [P],
        targetAmount: Int,
        mint: some MintRepresenting,
        unit: String,
        purpose: ProofSelectionPurpose,
        policy: ProofSelectionPolicy = .default,
        denominationTarget: DenominationTarget? = nil
    ) throws -> ProofSelectionResult<P> {

        guard targetAmount >= 0 else { throw ProofSelectionError.invalidTarget }

        let eligible = try eligibleProofs(proofs, mint: mint, unit: unit, seed: policy.randomSeed)
        guard !eligible.isEmpty else { throw ProofSelectionError.noEligibleProofs }

        if targetAmount == 0 {
            return ProofSelectionResult(kind: .directToken, selected: [], inputFee: 0,
                                        netAmount: 0, changeAmount: 0, sendOutputAmounts: [],
                                        changeOutputAmounts: [], blankOutputAmounts: [],
                                        keysetIDsSpent: [], optimality: .provedOptimal)
        }

        // Optional denomination-target context: the power-of-two basis used to shape
        // change outputs toward the wallet's ideal distribution. Absent ⇒
        // `changeOverride` nil ⇒ identical to the prior base-2 behaviour.
        //
        // Note: the target deliberately does *not* bias input selection. For
        // power-of-two denominations the selector's optimum is essentially unique in
        // (fee, change, count, amount), so a "drain surplus" input tie-breaker would
        // almost never fire yet would widen the Stage-2 Pareto frontier. The surplus
        // direction is handled where it can act without sacrificing optimality: a
        // wallet-initiated consolidation swap (see `idealDistribution` /
        // `denominationGap`). Here we only shape the change *outputs* (deficit fill).
        let plan = denominationTarget.map {
            denominationPlan(eligible: eligible, mint: mint, unit: unit, target: $0)
        }

        // Stage 1 — exact, fee-free direct subset.
        if purpose.allowsDirectExact && policy.preferDirectExact {
            let directItems = bundle(eligible,
                                     scoreForActive: directScorer(policy),
                                     dropFeeDominated: false)
            if let state = exactDirectSubset(directItems, target: targetAmount) {
                return directResult(state, items: directItems, proofs: proofs, target: targetAmount)
            }
        }

        // Stage 2 — fee-aware bounded knapsack (mint transaction).
        let mintItems = bundle(eligible,
                               scoreForActive: mintScorer(policy),
                               dropFeeDominated: true)
        let eligibleRaw = eligible.reduce(0) { $0 + $1.amount }
        let outcome = try feeAwareSubset(mintItems, target: targetAmount, policy: policy,
                                         eligibleRawAmount: eligibleRaw, purpose: purpose)

        let changeOverride = plan.map {
            changeOutputDistribution(state: outcome.state, items: mintItems,
                                     eligible: eligible, target: targetAmount, plan: $0)
        }
        return mintResult(outcome.state, optimality: outcome.optimality,
                          items: mintItems, proofs: proofs, target: targetAmount,
                          purpose: purpose, changeOutputAmountsOverride: changeOverride)
    }

    // MARK: - Denomination-target planning (offline-send optimization)

    /// The power-of-two basis (and target) used to shape change outputs toward the
    /// wallet's ideal denomination distribution.
    private struct DenominationPlan {
        let target: DenominationTarget
        let basis: [Int]
    }

    /// Resolves the basis to plan over from the eligible (this-mint/unit) inventory:
    /// the active keyset's supported denominations capped at the inventory's top bit,
    /// or synthesized powers of two if no keyset enumerates them.
    private static func denominationPlan(eligible: [EligibleProof],
                                         mint: some MintRepresenting,
                                         unit: String,
                                         target: DenominationTarget) -> DenominationPlan {
        let balance = eligible.reduce(0) { $0 + $1.amount }
        let cap = target.maxDenomination ?? topBitDenomination(balance)
        let basis = activeKeysetForUnit(unit, mint: mint).map { denominationBasis(keyset: $0, cap: cap) }
                    ?? powersOfTwo(upTo: cap)
        return DenominationPlan(target: target, basis: basis)
    }

    /// The change-output split that best fills the wallet's denomination deficits,
    /// given the inventory it retains after spending `state`'s inputs. Empty when
    /// there is no change. Sums exactly to the change amount (so it can feed a
    /// `preferredReturnDistribution` without a mismatch).
    private static func changeOutputDistribution(state: SelectionState,
                                                 items: [SelectionItem],
                                                 eligible: [EligibleProof],
                                                 target: Int,
                                                 plan: DenominationPlan) -> [Int] {
        let change = state.net - target
        guard change > 0 else { return [] }
        let spent = Set(state.chosen.flatMap { items[$0].indices })
        var retained: [Int: Int] = [:]
        var retainedSum = 0
        for e in eligible where !spent.contains(e.index) {
            retained[e.amount, default: 0] += 1
            retainedSum += e.amount
        }
        let ideal = idealCounts(balance: retainedSum + change, target: plan.target,
                                denominations: plan.basis)
        return fillDistribution(amount: change, retained: retained, ideal: ideal,
                                denominations: plan.basis)
    }

    // MARK: - Eligibility & keyset resolution

    private struct EligibleProof {
        let index: Int        // original index into the caller's array
        let amount: Int
        let ppk: Int
        let keysetID: String
        let active: Bool
        let tieBreak: UInt64
    }

    private static func eligibleProofs<P: ProofRepresenting>(
        _ proofs: [P], mint: some MintRepresenting, unit: String, seed: Data
    ) throws -> [EligibleProof] {
        var result: [EligibleProof] = []
        result.reserveCapacity(proofs.count)
        for (i, p) in proofs.enumerated() {
            guard p.amount > 0 else { continue }
            // v1: only unlocked proofs are spendable inputs (matches send/swap,
            // which reject inputs carrying a spending condition).
            if SpendingCondition.deserialize(from: p.secret) != nil { continue }
            guard let keyset = resolveKeyset(forID: p.keysetID, in: mint) else {
                throw ProofSelectionError.missingKeysetInformation(keysetID: p.keysetID)
            }
            guard keyset.unit == unit else { continue }
            result.append(EligibleProof(index: i,
                                        amount: p.amount,
                                        ppk: keyset.inputFeePPK,
                                        keysetID: keyset.keysetID,
                                        active: keyset.active,
                                        tieBreak: tieBreakValue(seed: seed,
                                                                keysetID: p.keysetID,
                                                                C: p.C)))
        }
        return result
    }

    /// Resolves a proof's keyset, handling legacy (12-char), v0 (`00…`) and v1
    /// (`01…`, possibly shortened) keyset IDs — mirrors `units(for:of:)`.
    private static func resolveKeyset(forID id: String, in mint: some MintRepresenting) -> Keyset? {
        if let exact = mint.keysets.first(where: { $0.keysetID == id }) { return exact }
        if id.hasPrefix("01") {
            let matches = mint.keysets.filter { $0.keysetID.hasPrefix(id) }
            if matches.count == 1 { return matches.first }
        }
        return nil
    }

    // MARK: - Binary bundling

    private struct GroupKey: Hashable {
        let amount: Int
        let ppk: Int
        let keysetID: String
    }

    /// A DP item: a single proof or a binary bundle of interchangeable proofs.
    private struct SelectionItem {
        let indices: [Int]    // original proof indices represented by this item
        let amount: Int
        let ppk: Int
        let proofCount: Int
        let keysetScore: Int
        let tieBreak: UInt64
    }

    /// Groups interchangeable proofs `(amount, ppk, keyset)` and binary-splits
    /// each group's count into bundles `1, 2, 4, …, remainder`, so the DP can
    /// form any count `0…k` while collapsing item count. `dropFeeDominated`
    /// removes proofs that can never improve net value in a fee-aware
    /// transaction (`amount ≤ ⌊ppk/1000⌋`); it must stay `false` for fee-free
    /// direct sends.
    private static func bundle(_ eligible: [EligibleProof],
                               scoreForActive: (Bool) -> Int,
                               dropFeeDominated: Bool) -> [SelectionItem] {
        var groups: [GroupKey: [EligibleProof]] = [:]
        for e in eligible {
            if dropFeeDominated && e.amount <= e.ppk / 1000 { continue }
            groups[GroupKey(amount: e.amount, ppk: e.ppk, keysetID: e.keysetID), default: []].append(e)
        }

        var items: [SelectionItem] = []
        for (key, membersUnsorted) in groups {
            // Deterministic member assignment to bundles.
            let members = membersUnsorted.sorted { $0.tieBreak < $1.tieBreak }
            let score = scoreForActive(members[0].active)
            var start = 0
            for size in binarySplit(members.count) {
                let slice = members[start ..< start + size]
                start += size
                items.append(SelectionItem(indices: slice.map { $0.index },
                                           amount: key.amount * size,
                                           ppk: key.ppk * size,
                                           proofCount: size,
                                           keysetScore: score * size,
                                           tieBreak: slice.reduce(UInt64(0)) { $0 ^ $1.tieBreak }))
            }
        }

        // Deterministic, iteration-order-independent processing order.
        items.sort { ($0.amount, $0.ppk, $0.proofCount, $0.tieBreak)
                   < ($1.amount, $1.ppk, $1.proofCount, $1.tieBreak) }
        return items
    }

    /// Splits `count` into a minimal binary cover: `1, 2, 4, …` then the
    /// remainder (e.g. `13 → [1, 2, 4, 6]`).
    private static func binarySplit(_ count: Int) -> [Int] {
        var sizes: [Int] = []
        var remaining = count
        var block = 1
        while remaining > 0 {
            let take = min(block, remaining)
            sizes.append(take)
            remaining -= take
            block *= 2
        }
        return sizes
    }

    private static func directScorer(_ policy: ProofSelectionPolicy) -> (Bool) -> Int {
        policy.avoidInactiveKeysetsForDirectSend ? { $0 ? 0 : 1 } : { _ in 0 }
    }

    private static func mintScorer(_ policy: ProofSelectionPolicy) -> (Bool) -> Int {
        policy.preferInactiveKeysetsForMintTransactions ? { $0 ? 1 : 0 } : { _ in 0 }
    }

    // MARK: - DP state

    private struct SelectionState {
        let amount: Int
        let ppk: Int
        let proofCount: Int
        let keysetScore: Int
        let tieBreak: UInt64
        let chosen: [Int]     // indices into the items array (backpointer)

        static let zero = SelectionState(amount: 0, ppk: 0, proofCount: 0,
                                         keysetScore: 0, tieBreak: 0, chosen: [])

        var fee: Int { ppk <= 0 ? 0 : (ppk + 999) / 1000 }
        var net: Int { amount - fee }

        func adding(_ item: SelectionItem, itemIndex: Int) -> SelectionState {
            SelectionState(amount: amount + item.amount,
                           ppk: ppk + item.ppk,
                           proofCount: proofCount + item.proofCount,
                           keysetScore: keysetScore + item.keysetScore,
                           tieBreak: tieBreak ^ item.tieBreak,
                           chosen: chosen + [itemIndex])
        }
    }

    // MARK: - Stage 1: exact direct subset

    /// Exact subset-sum DP keyed by amount `≤ target`. `dp[a]` keeps the best
    /// state reaching exactly `a` under the direct comparator. Returns the best
    /// state reaching exactly `target`, or `nil` if none exists.
    private static func exactDirectSubset(_ items: [SelectionItem], target: Int) -> SelectionState? {
        var dp: [Int: SelectionState] = [0: .zero]
        for (i, item) in items.enumerated() {
            // Transition only from states that predate this item (0/1 knapsack).
            let snapshot = dp
            for amount in snapshot.keys.sorted() {
                let next = amount + item.amount
                if next > target { continue }
                let candidate = snapshot[amount]!.adding(item, itemIndex: i)
                if let existing = dp[next] {
                    if directBetter(candidate, than: existing) { dp[next] = candidate }
                } else {
                    dp[next] = candidate
                }
            }
        }
        return dp[target]
    }

    /// Direct-send comparator: fewest proofs, then lowest total ppk (the
    /// recipient may later spend the token), then keyset hygiene, then a stable
    /// tie-break.
    private static func directBetter(_ a: SelectionState, than b: SelectionState) -> Bool {
        if a.proofCount != b.proofCount { return a.proofCount < b.proofCount }
        if a.ppk != b.ppk { return a.ppk < b.ppk }
        if a.keysetScore != b.keysetScore { return a.keysetScore < b.keysetScore }
        if a.tieBreak != b.tieBreak { return a.tieBreak < b.tieBreak }
        return lexLess(a.chosen.sorted(), b.chosen.sorted())
    }

    // MARK: - Stage 2: fee-aware bounded knapsack

    /// Fee-aware Pareto DP. Finds the selection minimising the mint-transaction
    /// comparator subject to `net ≥ target`.
    private static func feeAwareSubset(_ items: [SelectionItem],
                                       target: Int,
                                       policy: ProofSelectionPolicy,
                                       eligibleRawAmount: Int,
                                       purpose: ProofSelectionPurpose) throws
    -> (state: SelectionState, optimality: ProofSelectionOptimality) {

        // The all-items selection is the maximum achievable net; if it can't
        // reach the target nothing can.
        let allState = items.enumerated().reduce(SelectionState.zero) {
            $0.adding($1.element, itemIndex: $1.offset)
        }
        guard allState.net >= target else {
            throw ProofSelectionError.insufficientFunds(eligibleRawAmount: eligibleRawAmount,
                                                         requiredTarget: target,
                                                         purpose: purpose)
        }

        // Seed `best` (hence the fee-pruning bound) with cheap feasible
        // heuristics, falling back to the guaranteed-feasible all-items state.
        var best = allState
        for seed in heuristicSeeds(items, target: target) {
            if mintBetter(seed, than: best, target: target) { best = seed }
        }

        // states[amount] = Pareto-minimal open (net < target) states at `amount`.
        var states: [Int: [SelectionState]] = [0: [.zero]]
        var stateCount = 1

        for (i, item) in items.enumerated() {
            let snapshot = states
            for amount in snapshot.keys.sorted() {
                for state in snapshot[amount]! {
                    let candidate = state.adding(item, itemIndex: i)
                    // Adding proofs never lowers ppk, hence never lowers fee:
                    // a candidate already above the best fee can never win.
                    if candidate.fee > best.fee { continue }
                    if candidate.net >= target {
                        // Feasible: evaluate, but do not extend — extension only
                        // raises amount/ppk/count, never lowering fee or change.
                        if mintBetter(candidate, than: best, target: target) { best = candidate }
                    } else {
                        insertPareto(candidate, into: &states[candidate.amount, default: []],
                                     stateCount: &stateCount)
                    }
                }
            }
            if let maxStates = policy.maxStates, stateCount > maxStates {
                if policy.bestEffortWhenStateLimitHit {
                    return (best, .bestEffortStateLimitHit)
                } else {
                    throw ProofSelectionError.stateLimitExceeded
                }
            }
        }
        return (best, .provedOptimal)
    }

    /// Deterministic greedy feasible candidates to tighten the fee bound before
    /// the exhaustive DP. Correctness does not depend on these.
    private static func heuristicSeeds(_ items: [SelectionItem], target: Int) -> [SelectionState] {
        func greedy(_ order: [Int]) -> SelectionState? {
            var s = SelectionState.zero
            for i in order {
                if s.net >= target { break }
                s = s.adding(items[i], itemIndex: i)
            }
            return s.net >= target ? s : nil
        }
        let byAmountDesc = items.indices.sorted { items[$0].amount > items[$1].amount }
        let byPPKAsc     = items.indices.sorted { (items[$0].ppk, -items[$0].amount)
                                                < (items[$1].ppk, -items[$1].amount) }
        let byAmountAsc  = items.indices.sorted { items[$0].amount < items[$1].amount }
        return [byAmountDesc, byPPKAsc, byAmountAsc].compactMap(greedy)
    }

    /// Inserts `candidate` into a same-amount Pareto bucket, dropping it if
    /// dominated and evicting any states it dominates. Dominance uses
    /// `(ppk, proofCount, keysetScore)` — all additive under future identical
    /// extensions at equal amount, so a dominated state can never yield a
    /// better outcome. The random `tieBreak` is deliberately excluded (it would
    /// neuter pruning); determinism instead comes from deterministic processing
    /// order plus the final comparator.
    private static func insertPareto(_ candidate: SelectionState,
                                     into bucket: inout [SelectionState],
                                     stateCount: inout Int) {
        for existing in bucket where weaklyDominates(existing, candidate) { return }
        let before = bucket.count
        bucket.removeAll { weaklyDominates(candidate, $0) }
        stateCount -= (before - bucket.count)
        bucket.append(candidate)
        stateCount += 1
    }

    /// `a` weakly dominates `b` at equal amount (assumed): no worse on any
    /// future-preserved field. Equal states dominate each other, which dedups.
    private static func weaklyDominates(_ a: SelectionState, _ b: SelectionState) -> Bool {
        a.ppk <= b.ppk && a.proofCount <= b.proofCount && a.keysetScore <= b.keysetScore
    }

    /// Mint-transaction comparator: lowest fee, then change, then proof count,
    /// then raw amount, then keyset hygiene, then a stable tie-break.
    private static func mintBetter(_ a: SelectionState, than b: SelectionState, target: Int) -> Bool {
        let af = a.fee, bf = b.fee
        if af != bf { return af < bf }
        let ac = a.net - target, bc = b.net - target
        if ac != bc { return ac < bc }
        if a.proofCount != b.proofCount { return a.proofCount < b.proofCount }
        if a.amount != b.amount { return a.amount < b.amount }
        if a.keysetScore != b.keysetScore { return a.keysetScore < b.keysetScore }
        if a.tieBreak != b.tieBreak { return a.tieBreak < b.tieBreak }
        return lexLess(a.chosen.sorted(), b.chosen.sorted())
    }

    // MARK: - Result assembly

    private static func directResult<P: ProofRepresenting>(
        _ state: SelectionState, items: [SelectionItem], proofs: [P], target: Int
    ) -> ProofSelectionResult<P> {
        let proofIndices = state.chosen.flatMap { items[$0].indices }.sorted()
        let selected = proofIndices.map { proofs[$0] }
        return ProofSelectionResult(kind: .directToken,
                                    selected: selected,
                                    inputFee: 0,
                                    netAmount: target,
                                    changeAmount: 0,
                                    sendOutputAmounts: [],
                                    changeOutputAmounts: [],
                                    blankOutputAmounts: [],
                                    keysetIDsSpent: Set(selected.map { $0.keysetID }),
                                    optimality: .provedOptimal)
    }

    private static func mintResult<P: ProofRepresenting>(
        _ state: SelectionState, optimality: ProofSelectionOptimality,
        items: [SelectionItem], proofs: [P], target: Int, purpose: ProofSelectionPurpose,
        changeOutputAmountsOverride: [Int]? = nil
    ) -> ProofSelectionResult<P> {
        let proofIndices = state.chosen.flatMap { items[$0].indices }.sorted()
        let selected = proofIndices.map { proofs[$0] }
        let fee = state.fee
        let net = state.net
        let change = net - target
        // Use the target-aware change split when supplied; otherwise the base-2 split.
        let changeOutputAmounts = changeOutputAmountsOverride
            ?? (change > 0 ? splitIntoBase2Numbers(change) : [])
        return ProofSelectionResult(kind: .mintTransaction,
                                    selected: selected,
                                    inputFee: fee,
                                    netAmount: net,
                                    changeAmount: change,
                                    sendOutputAmounts: splitIntoBase2Numbers(target),
                                    changeOutputAmounts: changeOutputAmounts,
                                    blankOutputAmounts: [],
                                    keysetIDsSpent: Set(selected.map { $0.keysetID }),
                                    optimality: optimality)
    }

    // MARK: - Helpers

    /// Stable per-proof tie-break: `SHA256(seed ‖ keysetID ‖ C)`, first 8 bytes.
    private static func tieBreakValue(seed: Data, keysetID: String, C: String) -> UInt64 {
        var hasher = SHA256()
        hasher.update(data: seed)
        hasher.update(data: Data(keysetID.utf8))
        hasher.update(data: Data(C.utf8))
        var value: UInt64 = 0
        for byte in hasher.finalize().prefix(8) { value = (value << 8) | UInt64(byte) }
        return value
    }

    /// Lexicographic `<` for equal-purpose index lists (ultimate tie-break to
    /// guarantee a fully deterministic winner regardless of dictionary order).
    private static func lexLess(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x < y }
        return a.count < b.count
    }
}
