//
//  Faucet.swift
//  CashuSwiftTests
//
//  Thin client for the regtest faucet. The faucet is the only public way to
//  inject value into the regtest Lightning network without LND macaroons or
//  bitcoind RPC.
//

import Foundation
@testable import CashuSwift

enum Faucet {

    /// Hard cap enforced by the faucet (`FAUCET_MAX_AMOUNT`).
    static let maxAmountPerCall = 10_000

    enum FaucetError: Swift.Error, LocalizedError {
        case unreachable
        case badStatus(Int, String)
        case missingField(String)

        var errorDescription: String? {
            switch self {
            case .unreachable: "Faucet is unreachable"
            case .badStatus(let code, let body): "Faucet returned HTTP \(code): \(body)"
            case .missingField(let key): "Faucet response is missing field '\(key)'"
            }
        }
    }

    // MARK: - Health

    struct Health: Decodable {
        let status: String
        let lndNodes: [String]
        let mintUrl: String
        let maxAmount: Int

        enum CodingKeys: String, CodingKey {
            case status
            case lndNodes = "lnd_nodes"
            case mintUrl = "mint_url"
            case maxAmount = "max_amount"
        }
    }

    static func health() async throws -> Health {
        let url = TestEndpoints.faucet.appending(path: "/api/health")
        let (data, response) = try await URLSession.shared.data(from: url)
        try ensureOK(response, data: data)
        return try JSONDecoder().decode(Health.self, from: data)
    }

    // MARK: - Mint ecash

    /// Dispenses Cashu ecash redeemable at mint1.regtest.macadamia.cash.
    /// - Parameter amount: 1...10000 sats; defaults to 100.
    /// - Returns: The cashuB-encoded token string.
    static func mintEcashToken(amount: Int = 100) async throws -> String {
        precondition((1...maxAmountPerCall).contains(amount),
                     "Faucet mintEcash amount \(amount) outside permitted range 1...\(maxAmountPerCall)")
        struct Request: Encodable { let amount: Int }
        struct Response: Decodable {
            let token: String
            let amount: Int
            let mint: String
        }
        let url = TestEndpoints.faucet.appending(path: "/api/mint-ecash")
        let body = try JSONEncoder().encode(Request(amount: amount))
        let (data, response) = try await post(url: url, body: body)
        try ensureOK(response, data: data)
        return try JSONDecoder().decode(Response.self, from: data).token
    }

    /// Convenience: mints ecash from the faucet and returns it as a parsed `Token`,
    /// along with the proofs and mint URL string the token references.
    static func mintProofs(amount: Int = 100) async throws -> (proofs: [CashuSwift.Proof], mintURL: String) {
        let encoded = try await mintEcashToken(amount: amount)
        let token = try encoded.deserializeToken()
        guard let (mintURL, proofs) = token.proofsByMint.first else {
            throw FaucetError.missingField("proofs")
        }
        return (proofs, mintURL)
    }

    // MARK: - Pay invoice

    /// Pays an arbitrary regtest BOLT11 invoice (≤ 10 000 sat) from an LND node
    /// other than the invoice's destination.
    static func payInvoice(_ bolt11: String) async throws {
        struct Request: Encodable { let bolt11: String }
        struct Response: Decodable { let paid: Bool; let paymentHash: String; let paidFrom: String
            enum CodingKeys: String, CodingKey { case paid; case paymentHash = "payment_hash"; case paidFrom = "paid_from" }
        }
        let url = TestEndpoints.faucet.appending(path: "/api/pay-invoice")
        let body = try JSONEncoder().encode(Request(bolt11: bolt11))
        let (data, response) = try await post(url: url, body: body)
        try ensureOK(response, data: data)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if !decoded.paid {
            throw FaucetError.badStatus(200, "Faucet reported paid=false")
        }
    }

    // MARK: - Internals

    private static func post(url: URL, body: Data) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return try await URLSession.shared.data(for: req)
    }

    private static func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw FaucetError.unreachable
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw FaucetError.badStatus(http.statusCode, body)
        }
    }
}

