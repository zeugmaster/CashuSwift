import Foundation
import XCTest
import secp256k1
@testable import CashuSwift

final class Bolt12MintTests: XCTestCase {
    private let seed = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
    private let keyID = "009a1f293253e41e"
    // Test mint uses scalar 1 for every denomination, so C_ = B_.
    private let mintPublicKey = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    private func quote(amount: Int? = nil, paid: Int = 12, issued: Int = 4,
                       pubkey: String? = nil, unit: String = "sat", id: String = "quote-1") throws -> CashuSwift.Bolt12.MintQuote {
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        return .init(quote: id, request: "lno1-test-offer", amount: amount, unit: unit,
                     expiry: nil, pubkey: pubkey ?? key.publicKey, amountPaid: paid, amountIssued: issued)
    }

    private func fixture(handler: @escaping (URLRequest) throws -> Data = mintResponse) throws -> (CashuSwift.Mint, MintHTTPStub) {
        let stub = try MintHTTPStub(handler: handler)
        addTeardownBlock { stub.remove() }
        let keys = Dictionary(uniqueKeysWithValues: [1, 2, 4, 8, 256].map { (String($0), mintPublicKey) })
        let data = try JSONSerialization.data(withJSONObject: [
            "id": keyID, "unit": "sat", "active": true, "keys": keys, "derivationCounter": 7
        ])
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: data)
        return (CashuSwift.Mint(url: stub.url, keysets: [keyset]), stub)
    }

    func testTypedMintSignsExactOutputsForPartialAndAmountlessQuotes() async throws {
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        for originalAmount: Int? in [nil, 1] {
            let (mint, stub) = try fixture()
            let quote = try quote(amount: originalAmount, pubkey: key.publicKey.uppercased())
            let result = try await CashuSwift.Bolt12.mint(
                quote: quote, from: mint, amount: 6, seed: seed, quoteKey: key.privateKey,
                preferredDistribution: [4, 2]
            )
            XCTAssertEqual(result.proofs.map(\.amount), [4, 2])
            XCTAssertEqual(result.dleqResult, .noData)
            XCTAssertEqual(stub.requests.count, 1)
            let request = try XCTUnwrap(stub.requests.first)
            XCTAssertEqual(request.url?.path, "/v1/mint/bolt12")
            XCTAssertEqual(request.httpMethod, "POST")
            let bodyData = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["quote", "outputs", "signature"])
            let body = try JSONDecoder().decode(WireMintRequest.self, from: bodyData)
            XCTAssertEqual(body.quote, quote.quote)
            XCTAssertEqual(body.outputs.map(\.amount), [4, 2])
            XCTAssertEqual(body.outputs.map(\.id), [keyID, keyID])
            let pubkey = try secp256k1.Schnorr.PublicKey(dataRepresentation: key.publicKey.bytes, format: .compressed)
            let signature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: Data(try XCTUnwrap(body.signature).bytes))
            XCTAssertTrue(pubkey.xonly.isValidSignature(signature, for: try currentMessage(body)))

            var changed = body
            changed.quote += "-different"
            XCTAssertFalse(pubkey.xonly.isValidSignature(signature, for: try currentMessage(changed)))
            changed = body
            changed.outputs[0].amount = 8
            XCTAssertFalse(pubkey.xonly.isValidSignature(signature, for: try currentMessage(changed)))
            changed = body
            changed.outputs.reverse()
            XCTAssertFalse(pubkey.xonly.isValidSignature(signature, for: try currentMessage(changed)))
            changed = body
            changed.outputs[0].B_ = mintPublicKey
            XCTAssertFalse(pubkey.xonly.isValidSignature(signature, for: try currentMessage(changed)))
        }
    }

    func testQuoteCreationAndRefreshAllowRepeatedIssuance() async throws {
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        let initial = try quote(paid: 12, issued: 0)
        let refreshed = try quote(paid: 12, issued: 6)
        let (mint, stub) = try fixture { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/mint/quote/bolt12"):
                let data = try XCTUnwrap(request.httpBody)
                let body = try JSONDecoder().decode(CashuSwift.Bolt12.MintQuoteRequest.self, from: data)
                XCTAssertEqual(body.pubkey, key.publicKey)
                XCTAssertNil(body.amount)
                return try JSONEncoder().encode(initial)
            case ("GET", "/v1/mint/quote/bolt12/quote-1"):
                return try JSONEncoder().encode(refreshed)
            default:
                return try mintResponse(request)
            }
        }
        let requested = try await CashuSwift.Bolt12.requestMintQuote(
            .init(unit: "sat", amount: nil, pubkey: key.publicKey), from: mint
        )
        let first = try await CashuSwift.Bolt12.mint(quote: requested, from: mint, amount: 6, seed: nil, quoteKey: key.privateKey)
        let updated = try await CashuSwift.Bolt12.mintQuoteState(requested.quote, from: mint)
        XCTAssertEqual(try updated.mintableAmount, 6)
        let second = try await CashuSwift.Bolt12.mint(quote: updated, from: mint, amount: 6, seed: nil, quoteKey: key.privateKey)
        XCTAssertEqual(first.proofs.reduce(0) { $0 + $1.amount }, 6)
        XCTAssertEqual(second.proofs.reduce(0) { $0 + $1.amount }, 6)
        XCTAssertTrue(Set(first.proofs.map(\.secret)).isDisjoint(with: second.proofs.map(\.secret)))
        XCTAssertEqual(stub.requests.count, 4)
    }

    func testInvalidAccountingThrowsWithoutNetworkOrOverflow() async throws {
        let (mint, stub) = try fixture()
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        for (paid, issued) in [(-1, 0), (0, -1), (0, 1), (Int.max, Int.min), (Int.min, Int.max)] {
            let quote = try quote(paid: paid, issued: issued)
            XCTAssertThrowsError(try quote.mintableAmount) { error in
                XCTAssertEqual(error as? CashuError, .invalidQuoteAccounting)
            }
            await assertError(.invalidQuoteAccounting) {
                _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: 1, seed: nil, quoteKey: key.privateKey)
            }
        }
        XCTAssertEqual(try quote(paid: Int.max, issued: 0).mintableAmount, Int.max)
        XCTAssertEqual(try quote(paid: Int.max, issued: Int.max).mintableAmount, 0)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testInvalidAmountsAndDistributionsFailBeforeNetwork() async throws {
        let (mint, stub) = try fixture()
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        let quote = try quote(paid: Int.max, issued: 0)
        for amount in [0, -1] {
            await assertError(.invalidAmount) {
                _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: amount, seed: nil, quoteKey: key.privateKey)
            }
        }
        for (amount, split, error): (Int, [Int], CashuError) in [
            (4, [0, 4], .invalidAmount), (4, [-4, 8], .invalidAmount),
            (4, [3, 1], .invalidAmount), (16, [16], .invalidAmount),
            (4, [], .preferredDistributionMismatch("")),
            (4, [2], .preferredDistributionMismatch("")),
            (4, [1 << 62, 1 << 62], .preferredDistributionMismatch(""))
        ] {
            await assertError(error) {
                _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: amount, seed: nil,
                                                     quoteKey: key.privateKey, preferredDistribution: split)
            }
        }
        // Check generated denominations too, not only a preferred split.
        await assertError(.invalidAmount) {
            _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: 16, seed: nil, quoteKey: key.privateKey)
        }
        for limitedQuote in [try self.quote(), try self.quote(paid: 12, issued: 12)] {
            await assertError(.amountOutsideOfLimitRange) {
                _ = try await CashuSwift.Bolt12.mint(quote: limitedQuote, from: mint, amount: 9, seed: nil, quoteKey: key.privateKey)
            }
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testInvalidOrMismatchedKeysAndUnsignedMintFailBeforeNetwork() async throws {
        let (mint, stub) = try fixture()
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        let wrongKey = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 1)
        let quote = try quote()
        for privateKey in [Data(), Data(repeating: 0, count: 32), wrongKey.privateKey] {
            await assertError(.invalidKey("")) {
                _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: 1, seed: nil, quoteKey: privateKey)
            }
        }
        for publicKey in ["", "not-hex", "02" + String(repeating: "ff", count: 32), String(key.publicKey.dropFirst(2))] {
            let invalidQuote = try self.quote(pubkey: publicKey)
            await assertError(.invalidKey("")) {
                _ = try await CashuSwift.Bolt12.mint(quote: invalidQuote, from: mint, amount: 1, seed: nil, quoteKey: key.privateKey)
            }
            await assertError(publicKey.isEmpty ? .bolt12RequiresPubkey : .invalidKey("")) {
                _ = try await CashuSwift.Bolt12.requestMintQuote(.init(unit: "sat", amount: nil, pubkey: publicKey), from: mint)
            }
        }
        await assertError(.quoteSigningKeyRequired) {
            _ = try await CashuSwift.Bolt12.mint(quote: quote, from: mint, amount: 1, seed: nil)
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testQuoteResponsesValidateKeyUnitAccountingAndID() async throws {
        let key = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        let other = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 1)
        let cases: [(CashuSwift.Bolt12.MintQuote, CashuError)] = [
            (try quote(pubkey: other.publicKey), .invalidKey("")),
            (try quote(pubkey: "invalid"), .invalidKey("")),
            (try quote(unit: "msat"), .unitError("")),
            (try quote(paid: 0, issued: 1), .invalidQuoteAccounting)
        ]
        for (response, error) in cases {
            let (mint, _) = try fixture { _ in try JSONEncoder().encode(response) }
            await assertError(error) {
                _ = try await CashuSwift.Bolt12.requestMintQuote(.init(unit: "sat", amount: nil, pubkey: key.publicKey), from: mint)
            }
        }
        for (response, error) in [(try quote(id: "other"), CashuError.inputError("")),
                                  (try quote(paid: 0, issued: -1), .invalidQuoteAccounting)] {
            let (mint, _) = try fixture { _ in try JSONEncoder().encode(response) }
            await assertError(error) { _ = try await CashuSwift.Bolt12.mintQuoteState("quote-1", from: mint) }
        }
    }

    func testGenericSigningDefaultsAndLegacyCompatibility() async throws {
        let key = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 0)
        let typedKey = try CashuSwift.Bolt12.quoteLockingKey(seed: seed, counter: 0)
        XCTAssertEqual(key.privateKey, typedKey.privateKey)
        XCTAssertEqual(key.publicKey, typedKey.publicKey)
        let pubkey = try secp256k1.Schnorr.PublicKey(dataRepresentation: key.publicKey.bytes, format: .compressed)
        let quote = CashuSwift.Generic.MintQuote(method: .init(rawValue: "onchain"), quote: "generic-quote",
                                               request: "test-payment", unit: "sat", amount: 6,
                                               state: .paid, expiry: nil, raw: [:])
        for legacy in [false, true] {
            let (mint, stub) = try fixture()
            let result: CashuSwift.IssueResult
            if legacy {
                result = try await CashuSwift.Generic.mint(quote: quote, from: mint, seed: nil, quoteKey: key.privateKey,
                                                          amount: 2, signatureFormat: .legacyConcat)
            } else {
                // Preserve both default amount and default signature format.
                result = try await CashuSwift.Generic.mint(quote: quote, from: mint, seed: nil, quoteKey: key.privateKey)
            }
            XCTAssertEqual(result.proofs.reduce(0) { $0 + $1.amount }, legacy ? 2 : 6)
            let request = try XCTUnwrap(stub.requests.first)
            XCTAssertEqual(request.url?.path, "/v1/mint/onchain")
            let data = try XCTUnwrap(request.httpBody)
            let body = try JSONDecoder().decode(WireMintRequest.self, from: data)
            let signature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: Data(try XCTUnwrap(body.signature).bytes))
            let legacyMessage = Data((body.quote + body.outputs.map { $0.B_.lowercased() }.joined()).utf8)
            XCTAssertEqual(pubkey.xonly.isValidSignature(signature, for: legacyMessage), legacy)
            XCTAssertEqual(pubkey.xonly.isValidSignature(signature, for: try currentMessage(body)), !legacy)
            // Keep the old public wire-body name usable.
            _ = try JSONDecoder().decode(CashuSwift.Generic.SignedMintExecutionBody.self, from: data)
        }
    }

    private func assertError(_ expected: CashuError, file: StaticString = #filePath, line: UInt = #line,
                             operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CashuError, expected, file: file, line: line)
        }
    }
}

private struct WireMintRequest: Decodable {
    var quote: String
    var outputs: [WireOutput]
    var signature: String?
}

private struct WireOutput: Decodable {
    var amount: Int
    var id: String
    var B_: String
}

/// Independent NUT-20 encoding from captured wire fields, without the production message helper.
private func currentMessage(_ body: WireMintRequest) throws -> Data {
    func frame(_ bytes: Data) -> Data {
        var count = UInt32(bytes.count).bigEndian
        return withUnsafeBytes(of: &count) { Data($0) } + bytes
    }
    var message = Data("Cashu_MintQuoteSig_v1".utf8) + frame(Data(body.quote.utf8))
    for output in body.outputs {
        var amount = UInt64(output.amount).bigEndian
        let amountBytes = withUnsafeBytes(of: &amount) { Data($0.drop(while: { $0 == 0 })) }
        message += frame(amountBytes)
        message += frame(Data(try output.B_.bytes))
    }
    return message
}

private func mintResponse(_ request: URLRequest) throws -> Data {
    let data = try XCTUnwrap(request.httpBody)
    let body = try JSONDecoder().decode(WireMintRequest.self, from: data)
    let promises = body.outputs.map { CashuSwift.Promise(id: $0.id, amount: $0.amount, C_: $0.B_, dleq: nil) }
    return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: promises))
}
