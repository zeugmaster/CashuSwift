//
//  OfflineTokenTests.swift
//  CashuSwiftTests
//
//  Tests for the offline-send primitive: the synchronous, network-free
//  `offlineToken(for:mint:memo:)` builder and the `canSendOffline` predicate,
//  plus their round-trip with `selectProofs(…, purpose: .tokenTransferUnlocked)`.
//

import XCTest
@testable import CashuSwift

private func keyset(_ id: String = "00aa", unit: String = "sat",
                    denominations: [Int] = (0...10).map { 1 << $0 }) -> CashuSwift.Keyset {
    let keysJSON = denominations.map { "\"\($0)\":\"02aa\"" }.joined(separator: ",")
    let json = """
    {"id":"\(id)","unit":"\(unit)","active":true,"input_fee_ppk":0,"keys":{\(keysJSON)}}
    """
    return try! JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
}

private let lockedSecret = "[\"P2PK\",{\"nonce\":\"abc123\",\"data\":\"02deadbeef\",\"tags\":null}]"

private func proof(_ amount: Int, _ keysetID: String = "00aa", id: Int, locked: Bool = false) -> CashuSwift.Proof {
    CashuSwift.Proof(keysetID: keysetID, amount: amount,
                     secret: locked ? lockedSecret : "secret-\(id)", C: "C-\(id)", dleq: nil)
}

private func proofs(_ amounts: [Int], keysetID: String = "00aa") -> [CashuSwift.Proof] {
    amounts.enumerated().map { proof($0.element, keysetID, id: $0.offset) }
}

final class OfflineTokenTests: XCTestCase {

    private let m = CashuSwift.Mint(url: URL(string: "https://test.mint")!, keysets: [keyset()])

    // MARK: - offlineToken

    func testOfflineTokenBundlesProofs() throws {
        let token = try CashuSwift.offlineToken(for: proofs([1, 2]), mint: m, memo: "here you go")
        XCTAssertEqual(token.unit, "sat")
        XCTAssertEqual(token.memo, "here you go")
        XCTAssertEqual(token.proofsByMint.count, 1)
        XCTAssertEqual(token.proofsByMint[m.url.absoluteString]?.sum, 3)
    }

    /// The build is genuinely network-free: it succeeds even for a mint URL that
    /// could never be contacted (it is a synchronous, non-`async` call).
    func testOfflineTokenIsNetworkFree() throws {
        let offlineMint = CashuSwift.Mint(url: URL(string: "https://192.0.2.1.invalid")!,
                                          keysets: [keyset()])
        let token = try CashuSwift.offlineToken(for: proofs([4, 8]), mint: offlineMint)
        XCTAssertEqual(token.proofsByMint.values.first?.sum, 12)
    }

    func testOfflineTokenRejectsEmptyProofs() {
        XCTAssertThrowsError(try CashuSwift.offlineToken(for: [], mint: m))
    }

    func testOfflineTokenRejectsLockedProofs() {
        let withLock = proofs([1, 2]) + [proof(4, id: 99, locked: true)]
        XCTAssertThrowsError(try CashuSwift.offlineToken(for: withLock, mint: m)) { error in
            guard case CashuError.spendingConditionError = error else {
                return XCTFail("expected spendingConditionError, got \(error)")
            }
        }
    }

    func testOfflineTokenRejectsMixedUnits() {
        let multiMint = CashuSwift.Mint(url: URL(string: "https://test.mint")!,
                                        keysets: [keyset("00aa", unit: "sat"),
                                                  keyset("00bb", unit: "usd")])
        let mixed = proofs([1, 2], keysetID: "00aa") + proofs([4], keysetID: "00bb")
        XCTAssertThrowsError(try CashuSwift.offlineToken(for: mixed, mint: multiMint))
    }

    // MARK: - Round-trip with selectProofs

    /// A `.directToken` selection feeds straight into `offlineToken` — the full
    /// offline-send path, no network anywhere.
    func testSelectProofsDirectTokenRoundTrip() throws {
        let wallet = proofs([1, 2, 4, 8])
        let r = try CashuSwift.selectProofs(wallet, targetAmount: 3, mint: m, unit: "sat",
                                            purpose: .tokenTransferUnlocked)
        XCTAssertEqual(r.kind, .directToken)
        let token = try CashuSwift.offlineToken(for: r.selected, mint: m, memo: nil)
        XCTAssertEqual(token.proofsByMint[m.url.absoluteString]?.sum, 3)
    }

    // MARK: - canSendOffline

    func testCanSendOfflineTrueForExactSubsets() {
        let wallet = proofs([1, 2, 4])
        for amount in [1, 2, 3, 4, 5, 6, 7] {   // every value in [1, 7] is exactly representable
            XCTAssertTrue(CashuSwift.canSendOffline(wallet, amount: amount, mint: m, unit: "sat"),
                          "\(amount) should be offline-sendable")
        }
    }

    func testCanSendOfflineFalseWhenChangeWouldBeNeeded() {
        // {2,4}: amounts 2,4,6 only — 3 and 5 require change (a mint swap).
        let wallet = proofs([2, 4])
        XCTAssertFalse(CashuSwift.canSendOffline(wallet, amount: 3, mint: m, unit: "sat"))
        XCTAssertFalse(CashuSwift.canSendOffline(wallet, amount: 5, mint: m, unit: "sat"))
        XCTAssertTrue(CashuSwift.canSendOffline(wallet, amount: 6, mint: m, unit: "sat"))
    }

    func testCanSendOfflineFalseWhenInsufficient() {
        XCTAssertFalse(CashuSwift.canSendOffline(proofs([1, 2]), amount: 10, mint: m, unit: "sat"))
    }

    func testCanSendOfflineFalseForEmptyWallet() {
        XCTAssertFalse(CashuSwift.canSendOffline([CashuSwift.Proof](), amount: 1, mint: m, unit: "sat"))
    }
}
