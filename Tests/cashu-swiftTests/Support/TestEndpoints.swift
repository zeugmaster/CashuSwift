//
//  TestEndpoints.swift
//  CashuSwiftTests
//
//  Public, persistent test infrastructure. See the project's testing
//  infrastructure reference for endpoint semantics.
//

import Foundation

enum TestEndpoints {

    // MARK: - FakeWallet mints (simulated Lightning, deterministic timing)

    /// Happy-path FakeWallet mint with brief (~5s outgoing, ~1s incoming) delays.
    static let fakeSuccess = URL(string: "https://success.fake.macadamia.cash")!

    /// Happy-path FakeWallet mint with ~90s outgoing delay. Use for polling/timeout tests.
    static let fakeSuccessLong = URL(string: "https://success-long.fake.macadamia.cash")!

    /// FakeWallet mint that deterministically reports payment FAILED after ~3s.
    static let fakeErrorShort = URL(string: "https://error-short.fake.macadamia.cash")!

    /// FakeWallet mint that reports FAILED after ~120s — use for slow-failure / timeout boundary tests.
    static let fakeErrorLong = URL(string: "https://error-long.fake.macadamia.cash")!

    /// FakeWallet mint that throws exceptions from both payment-state and pay-invoice paths.
    static let fakeException = URL(string: "https://exception.fake.macadamia.cash")!

    // MARK: - Regtest Lightning mints (real LND backends on shared regtest)

    /// Regtest mint #1 — backed by LND1. Direct channels to LND2 and LND3.
    static let regtestMint1 = URL(string: "https://mint1.regtest.macadamia.cash")!

    /// Regtest mint #2 — backed by LND2. Direct channels to LND1 and LND4.
    static let regtestMint2 = URL(string: "https://mint2.regtest.macadamia.cash")!

    /// Regtest mint #3 — backed by LND3. Direct channels to LND1 and LND4.
    static let regtestMint3 = URL(string: "https://mint3.regtest.macadamia.cash")!

    /// Regtest mint #4 — backed by LND4. Direct channels to LND2 and LND3 only (inbound capacity).
    static let regtestMint4 = URL(string: "https://mint4.regtest.macadamia.cash")!

    // MARK: - Faucet

    /// Programmatic value-injection service for the regtest network.
    static let faucet = URL(string: "https://faucet.regtest.macadamia.cash")!
}
