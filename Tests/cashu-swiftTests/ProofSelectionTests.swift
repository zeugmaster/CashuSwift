//
//  ProofSelectionTests.swift
//  CashuSwiftTests
//
//  Pure unit tests for the fee-aware proof selector — no network. Covers the
//  documented unit cases, determinism, the generic "select in place" boundary,
//  binary-bundling round-trips, and brute-force property tests that compare the
//  dynamic program against exhaustive subset enumeration for small wallets.
//

import XCTest
@testable import CashuSwift

// MARK: - Test fixtures

/// Builds a `Keyset` with the given fee rate / activity by decoding minimal JSON
/// (the model has a custom `Decodable` init and no memberwise initializer).
private func ks(_ id: String, ppk: Int, active: Bool = true, unit: String = "sat") -> CashuSwift.Keyset {
    let json = "{\"id\":\"\(id)\",\"unit\":\"\(unit)\",\"active\":\(active),\"input_fee_ppk\":\(ppk)}"
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

private func mint(_ keysets: [CashuSwift.Keyset]) -> CashuSwift.Mint {
    CashuSwift.Mint(url: URL(string: "https://test.mint")!, keysets: keysets)
}

/// A valid serialized P2PK spending condition — makes a proof "locked".
private let lockedSecret = "[\"P2PK\",{\"nonce\":\"abc123\",\"data\":\"02deadbeef\",\"tags\":null}]"

private func proof(_ amount: Int, _ keysetID: String, id: Int, locked: Bool = false) -> CashuSwift.Proof {
    CashuSwift.Proof(keysetID: keysetID,
                     amount: amount,
                     secret: locked ? lockedSecret : "secret-\(id)",
                     C: "C-\(id)-\(keysetID)",
                     dleq: nil)
}

/// A wallet-side proof type distinct from `CashuSwift.Proof`, used to prove the
/// generic "select in place" boundary returns the caller's own type.
private struct WalletProof: ProofRepresenting {
    let keysetID: String
    let C: String
    let secret: String
    let amount: Int
    let dleq: CashuSwift.DLEQ?
}

// MARK: - Deterministic RNG (SplitMix64) for property tests

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

// MARK: - Brute-force oracles

private func ceilFee(_ ppk: Int) -> Int { ppk <= 0 ? 0 : (ppk + 999) / 1000 }

/// Optimal `(fee, change, count, raw)` over all subsets with `net >= target`,
/// minimised lexicographically. `nil` if no subset is feasible.
private func bruteForceMint(_ proofs: [(amount: Int, ppk: Int)], target: Int)
-> (fee: Int, change: Int, count: Int, raw: Int)? {
    var best: (fee: Int, change: Int, count: Int, raw: Int)?
    for mask in 0 ..< (1 << proofs.count) {
        var raw = 0, ppk = 0, count = 0
        for i in proofs.indices where mask & (1 << i) != 0 {
            raw += proofs[i].amount; ppk += proofs[i].ppk; count += 1
        }
        let fee = ceilFee(ppk)
        let net = raw - fee
        guard net >= target else { continue }
        let cand = (fee: fee, change: net - target, count: count, raw: raw)
        if best == nil
            || (cand.fee, cand.change, cand.count, cand.raw)
             < (best!.fee, best!.change, best!.count, best!.raw) {
            best = cand
        }
    }
    return best
}

/// Optimal `(count, ppk)` over subsets summing *exactly* to `target`.
private func bruteForceExact(_ proofs: [(amount: Int, ppk: Int)], target: Int)
-> (count: Int, ppk: Int)? {
    var best: (count: Int, ppk: Int)?
    for mask in 0 ..< (1 << proofs.count) {
        var raw = 0, ppk = 0, count = 0
        for i in proofs.indices where mask & (1 << i) != 0 {
            raw += proofs[i].amount; ppk += proofs[i].ppk; count += 1
        }
        guard raw == target else { continue }
        if best == nil || (count, ppk) < (best!.count, best!.ppk) { best = (count, ppk) }
    }
    return best
}

final class ProofSelectionTests: XCTestCase {

    // MARK: Documented unit cases

    /// #1 — exact direct send pays no fee.
    func testDirectExactPaysNoFee() throws {
        let m = mint([ks("A", ppk: 100)])
        let proofs = [proof(1, "A", id: 1), proof(2, "A", id: 2), proof(4, "A", id: 3)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 3, mint: m,
                                            unit: "sat", purpose: .tokenTransferUnlocked)
        XCTAssertEqual(r.kind, .directToken)
        XCTAssertEqual(r.inputFee, 0)
        XCTAssertEqual(r.selected.reduce(0) { $0 + $1.amount }, 3)
        XCTAssertEqual(r.selected.count, 2)
        XCTAssertEqual(r.changeAmount, 0)
    }

    /// #2 — direct exact beats the swap path even with high keyset fees.
    func testDirectExactBeatsHighFeeSwap() throws {
        let m = mint([ks("A", ppk: 999)])
        let proofs = [proof(10, "A", id: 1)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 10, mint: m,
                                            unit: "sat", purpose: .tokenTransferUnlocked)
        XCTAssertEqual(r.kind, .directToken)
        XCTAssertEqual(r.inputFee, 0)
        XCTAssertEqual(r.selected.count, 1)
    }

    /// #3 — fee-aware: raw amount is not enough once the fee is subtracted.
    func testFeeAwareRawAmountNotEnough() {
        let m = mint([ks("A", ppk: 1000)])
        let proofs = [proof(100, "A", id: 1)]
        XCTAssertThrowsError(try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                                         unit: "sat", purpose: .swap)) { error in
            guard case CashuSwift.ProofSelectionError.insufficientFunds(let raw, let target, _) = error else {
                return XCTFail("Expected insufficientFunds, got \(error)")
            }
            XCTAssertEqual(raw, 100)
            XCTAssertEqual(target, 100)
        }
    }

    /// #4 — fee-aware chooses the lower-fee feasible subset.
    func testFeeAwareChoosesLowerFee() throws {
        let m = mint([ks("HI", ppk: 1000), ks("LO", ppk: 0)])
        let proofs = [proof(100, "HI", id: 1), proof(101, "LO", id: 2)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.kind, .mintTransaction)
        XCTAssertEqual(r.inputFee, 0)
        XCTAssertEqual(r.selected.count, 1)
        XCTAssertEqual(r.selected.first?.amount, 101)
        XCTAssertEqual(r.netAmount, 101)
        XCTAssertEqual(r.changeAmount, 1)
    }

    /// #5 — rounding boundary: ppk 500 + 500 + 0 rounds up to fee 1.
    func testFeeRoundingBoundary() throws {
        let m = mint([ks("F", ppk: 500), ks("Z", ppk: 0)])
        let proofs = [proof(5, "F", id: 1), proof(5, "F", id: 2), proof(1, "Z", id: 3)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 10, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.selected.count, 3)
        XCTAssertEqual(r.selected.reduce(0) { $0 + $1.amount }, 11)
        XCTAssertEqual(r.inputFee, 1)
        XCTAssertEqual(r.netAmount, 10)
        XCTAssertEqual(r.changeAmount, 0)
    }

    /// #6 — fees are computed only from the selected proofs' keysets.
    func testMultipleKeysetFees() throws {
        let m = mint([ks("A", ppk: 0), ks("B", ppk: 999)])
        // Two ways to reach net 8: {8@A} fee 0, or {8@B} fee 1. Lower fee wins.
        let proofs = [proof(8, "A", id: 1), proof(8, "B", id: 2)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 8, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.inputFee, 0)
        XCTAssertEqual(r.selected.first?.keysetID, "A")
    }

    /// #7 — for mint transactions, inactive keysets win an otherwise-exact tie.
    func testInactiveKeysetPreferredForMint() throws {
        let m = mint([ks("ACT", ppk: 0, active: true), ks("INACT", ppk: 0, active: false)])
        let proofs = [proof(100, "ACT", id: 1), proof(100, "INACT", id: 2)]
        var policy = CashuSwift.ProofSelectionPolicy.default
        policy.preferInactiveKeysetsForMintTransactions = true
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap, policy: policy)
        XCTAssertEqual(r.selected.count, 1)
        XCTAssertEqual(r.selected.first?.keysetID, "INACT")
    }

    /// #8 — for direct sends, active keysets win an otherwise-exact tie.
    func testActiveKeysetPreferredForDirectSend() throws {
        let m = mint([ks("ACT", ppk: 0, active: true), ks("INACT", ppk: 0, active: false)])
        let proofs = [proof(100, "ACT", id: 1), proof(100, "INACT", id: 2)]
        var policy = CashuSwift.ProofSelectionPolicy.default
        policy.avoidInactiveKeysetsForDirectSend = true
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .tokenTransferUnlocked, policy: policy)
        XCTAssertEqual(r.kind, .directToken)
        XCTAssertEqual(r.selected.first?.keysetID, "ACT")
    }

    /// #9 — locked proofs are filtered out (not spendable inputs in v1).
    func testLockedProofsFiltered() throws {
        let m = mint([ks("A", ppk: 0)])
        let proofs = [proof(100, "A", id: 1, locked: true), proof(100, "A", id: 2)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.selected.count, 1)
        XCTAssertFalse(r.selected.contains { $0.secret == lockedSecret })

        // Only a locked proof present ⇒ nothing eligible.
        XCTAssertThrowsError(try CashuSwift.selectProofs([proof(100, "A", id: 3, locked: true)],
                                                         targetAmount: 50, mint: m,
                                                         unit: "sat", purpose: .swap)) { error in
            guard case CashuSwift.ProofSelectionError.noEligibleProofs = error else {
                return XCTFail("Expected noEligibleProofs, got \(error)")
            }
        }
    }

    /// #10 — state-limit behaviour is explicit: throw vs. best-effort.
    func testStateLimitThrows() {
        let m = mint([ks("A", ppk: 0)])
        let proofs = [proof(40, "A", id: 1), proof(40, "A", id: 2), proof(40, "A", id: 3)]
        var policy = CashuSwift.ProofSelectionPolicy.default
        policy.maxStates = 1
        policy.bestEffortWhenStateLimitHit = false
        XCTAssertThrowsError(try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                                         unit: "sat", purpose: .swap, policy: policy)) { error in
            guard case CashuSwift.ProofSelectionError.stateLimitExceeded = error else {
                return XCTFail("Expected stateLimitExceeded, got \(error)")
            }
        }
    }

    func testStateLimitBestEffort() throws {
        let m = mint([ks("A", ppk: 0)])
        let proofs = [proof(40, "A", id: 1), proof(40, "A", id: 2), proof(40, "A", id: 3)]
        var policy = CashuSwift.ProofSelectionPolicy.default
        policy.maxStates = 1
        policy.bestEffortWhenStateLimitHit = true
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap, policy: policy)
        XCTAssertEqual(r.optimality, .bestEffortStateLimitHit)
        XCTAssertGreaterThanOrEqual(r.netAmount, 100)
    }

    // MARK: Keyset resolution & diagnostics

    func testMissingKeysetThrows() {
        let m = mint([ks("A", ppk: 0)])
        let proofs = [proof(100, "UNKNOWN", id: 1)]
        XCTAssertThrowsError(try CashuSwift.selectProofs(proofs, targetAmount: 50, mint: m,
                                                         unit: "sat", purpose: .swap)) { error in
            guard case CashuSwift.ProofSelectionError.missingKeysetInformation(let id) = error else {
                return XCTFail("Expected missingKeysetInformation, got \(error)")
            }
            XCTAssertEqual(id, "UNKNOWN")
        }
    }

    func testWrongUnitFilteredNotThrown() throws {
        let m = mint([ks("SAT", ppk: 0, unit: "sat"), ks("USD", ppk: 0, unit: "usd")])
        let proofs = [proof(100, "SAT", id: 1), proof(100, "USD", id: 2)]
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.selected.count, 1)
        XCTAssertEqual(r.selected.first?.keysetID, "SAT")
    }

    func testShortV1KeysetIDResolves() throws {
        let full = "01" + String(repeating: "a", count: 62)   // 64 chars
        let m = mint([ks(full, ppk: 0)])
        let shortID = String(full.prefix(16))
        let proofs = [proof(100, shortID, id: 1)]   // proof carries shortened id
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 100, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.selected.count, 1)
        XCTAssertEqual(r.keysetIDsSpent, [shortID])
    }

    // MARK: Determinism & the generic boundary

    func testDeterministicForSameRequest() throws {
        let m = mint([ks("A", ppk: 1), ks("B", ppk: 2, active: false)])
        let proofs = (0..<12).map { proof([1, 2, 4, 8][$0 % 4], $0 % 2 == 0 ? "A" : "B", id: $0) }
        let seed = Data([1, 2, 3, 4])
        var policy = CashuSwift.ProofSelectionPolicy.default
        policy.randomSeed = seed
        let a = try CashuSwift.selectProofs(proofs, targetAmount: 13, mint: m,
                                            unit: "sat", purpose: .swap, policy: policy)
        let b = try CashuSwift.selectProofs(proofs, targetAmount: 13, mint: m,
                                            unit: "sat", purpose: .swap, policy: policy)
        XCTAssertEqual(a.selected.map { $0.C }, b.selected.map { $0.C })
    }

    /// The "select in place" guarantee: a foreign `ProofRepresenting` type goes
    /// in, the *same* type comes back — no conversion, no downcast.
    func testSelectInPlaceReturnsCallerType() throws {
        let m = mint([ks("A", ppk: 0)])
        let wallet = [
            WalletProof(keysetID: "A", C: "wc1", secret: "s1", amount: 4, dleq: nil),
            WalletProof(keysetID: "A", C: "wc2", secret: "s2", amount: 8, dleq: nil),
            WalletProof(keysetID: "A", C: "wc3", secret: "s3", amount: 16, dleq: nil),
        ]
        let result = try CashuSwift.selectProofs(wallet, targetAmount: 12, mint: m,
                                                 unit: "sat", purpose: .tokenTransferUnlocked)
        // Compile-time proof of type preservation:
        let selected: [WalletProof] = result.selected
        XCTAssertEqual(selected.reduce(0) { $0 + $1.amount }, 12)
        // Identity preserved: every returned proof is one of the inputs (by C).
        let inputCs = Set(wallet.map { $0.C })
        XCTAssertTrue(selected.allSatisfy { inputCs.contains($0.C) })
    }

    // MARK: Binary bundling round-trip

    func testBundlingExpandsToDistinctInputProofs() throws {
        let m = mint([ks("A", ppk: 0)])
        let proofs = (0..<13).map { proof(1, "A", id: $0) }   // 13 identical-shape proofs
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 5, mint: m,
                                            unit: "sat", purpose: .swap)
        XCTAssertEqual(r.selected.count, 5)
        XCTAssertEqual(r.selected.reduce(0) { $0 + $1.amount }, 5)
        XCTAssertEqual(r.inputFee, 0)
        // Distinct, real input proofs.
        let cs = r.selected.map { $0.C }
        XCTAssertEqual(Set(cs).count, 5)
        let inputCs = Set(proofs.map { $0.C })
        XCTAssertTrue(cs.allSatisfy { inputCs.contains($0) })
    }

    func testDirectNoExactSubsetFallsToMintTransaction() throws {
        let m = mint([ks("A", ppk: 0)])
        let proofs = [proof(2, "A", id: 1), proof(4, "A", id: 2)]   // no subset sums to 3
        let r = try CashuSwift.selectProofs(proofs, targetAmount: 3, mint: m,
                                            unit: "sat", purpose: .tokenTransferUnlocked)
        XCTAssertEqual(r.kind, .mintTransaction)
        XCTAssertGreaterThanOrEqual(r.netAmount, 3)
    }

    func testMeltTargetIncludesFeeReserve() throws {
        // Caller passes target = quote.amount + feeReserve. Selection guarantees
        // net >= target, i.e. sum >= amount + feeReserve + inputFee.
        let m = mint([ks("A", ppk: 100)])
        let proofs = (0..<8).map { proof(8, "A", id: $0) }   // 64 sat total
        let amount = 40, feeReserve = 5
        let r = try CashuSwift.selectProofs(proofs, targetAmount: amount + feeReserve, mint: m,
                                            unit: "sat", purpose: .melt)
        XCTAssertGreaterThanOrEqual(r.netAmount, amount + feeReserve)
        XCTAssertEqual(r.inputFee, ceilFee(r.selected.count * 100))
    }

    // MARK: Brute-force property tests

    private let keysetPool: [CashuSwift.Keyset] = [
        ks("K0", ppk: 0, active: true),
        ks("K1", ppk: 1, active: true),
        ks("K2", ppk: 100, active: true),
        ks("K3", ppk: 999, active: false),
        ks("K4", ppk: 1000, active: true),
        ks("K5", ppk: 1001, active: false),
    ]
    private let amountPool = [1, 2, 3, 4, 5, 7, 8, 16, 32, 64]

    func testBruteForceFeeAware() throws {
        let m = mint(keysetPool)
        var rng = SeededRNG(seed: 0xCA54_F00D)
        for _ in 0..<1500 {
            let n = Int.random(in: 1...12, using: &rng)
            var proofs: [CashuSwift.Proof] = []
            var oracle: [(amount: Int, ppk: Int)] = []
            for i in 0..<n {
                let k = keysetPool[Int.random(in: 0..<keysetPool.count, using: &rng)]
                let amount = amountPool[Int.random(in: 0..<amountPool.count, using: &rng)]
                proofs.append(proof(amount, k.keysetID, id: i))
                oracle.append((amount, k.inputFeePPK))
            }
            let allNet = oracle.reduce(0) { $0 + $1.amount } - ceilFee(oracle.reduce(0) { $0 + $1.ppk })
            guard allNet >= 1 else { continue }
            let target = Int.random(in: 1...(allNet + 3), using: &rng)   // sometimes infeasible

            let expected = bruteForceMint(oracle, target: target)
            do {
                let r = try CashuSwift.selectProofs(proofs, targetAmount: target, mint: m,
                                                    unit: "sat", purpose: .swap)
                guard let expected else {
                    return XCTFail("DP succeeded but brute force found no feasible subset (target \(target))")
                }
                let raw = r.selected.reduce(0) { $0 + $1.amount }
                XCTAssertEqual(r.inputFee, expected.fee, "fee mismatch, target \(target), proofs \(oracle)")
                XCTAssertEqual(r.changeAmount, expected.change, "change mismatch, target \(target), proofs \(oracle)")
                XCTAssertEqual(r.selected.count, expected.count, "count mismatch, target \(target), proofs \(oracle)")
                XCTAssertEqual(raw, expected.raw, "raw mismatch, target \(target), proofs \(oracle)")
                XCTAssertEqual(r.netAmount, raw - r.inputFee)
                XCTAssertGreaterThanOrEqual(r.netAmount, target)
                XCTAssertEqual(Set(r.selected.map { $0.C }).count, r.selected.count, "duplicate proofs selected")
            } catch CashuSwift.ProofSelectionError.insufficientFunds {
                XCTAssertNil(expected, "DP reported insufficient but brute force found a subset (target \(target), proofs \(oracle))")
            }
        }
    }

    func testBruteForceDirectExact() throws {
        let m = mint(keysetPool)
        var rng = SeededRNG(seed: 0x1234_5678)
        for _ in 0..<1500 {
            let n = Int.random(in: 1...12, using: &rng)
            var proofs: [CashuSwift.Proof] = []
            var oracle: [(amount: Int, ppk: Int)] = []
            for i in 0..<n {
                let k = keysetPool[Int.random(in: 0..<keysetPool.count, using: &rng)]
                let amount = amountPool[Int.random(in: 0..<amountPool.count, using: &rng)]
                proofs.append(proof(amount, k.keysetID, id: i))
                oracle.append((amount, k.inputFeePPK))
            }
            // Force a target that has at least one exact subset by summing a random subset.
            let mask = Int.random(in: 1..<(1 << n), using: &rng)
            var target = 0
            for i in 0..<n where mask & (1 << i) != 0 { target += oracle[i].amount }

            let expected = bruteForceExact(oracle, target: target)!   // the chosen subset guarantees one
            let r = try CashuSwift.selectProofs(proofs, targetAmount: target, mint: m,
                                                unit: "sat", purpose: .tokenTransferUnlocked)
            XCTAssertEqual(r.kind, .directToken, "exact subset exists but DP didn't pick a direct send (target \(target), proofs \(oracle))")
            XCTAssertEqual(r.inputFee, 0)
            let raw = r.selected.reduce(0) { $0 + $1.amount }
            XCTAssertEqual(raw, target)
            // Optimal on (count, ppk).
            let ppk = r.selected.reduce(0) { partial, p in
                partial + (keysetPool.first { $0.keysetID == p.keysetID }?.inputFeePPK ?? 0)
            }
            XCTAssertEqual(r.selected.count, expected.count, "count not minimal (target \(target), proofs \(oracle))")
            XCTAssertEqual(ppk, expected.ppk, "ppk not minimal among min-count subsets (target \(target), proofs \(oracle))")
            XCTAssertEqual(Set(r.selected.map { $0.C }).count, r.selected.count)
        }
    }
}
