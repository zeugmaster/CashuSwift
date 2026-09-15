import XCTest
import secp256k1
@testable import CashuSwift

final class OnchainMintTests: XCTestCase {
    typealias F = OnchainFixture
    typealias O = CashuSwift.Onchain

    func testSignedIssuanceRoundTripAndValidDLEQ() async throws {
        let stub = try MintHTTPStub { request in
            XCTAssertEqual(request.url?.path, "/v1/mint/onchain")
            let data = try XCTUnwrap(request.httpBody)
            let body = try JSONDecoder().decode(CashuSwift.SignedMintExecutionBody.self, from: data)
            XCTAssertEqual(Set(try F.json(body).keys), ["quote", "outputs", "signature"])
            let key = try O.quoteLockingKey(seed: F.seed, counter: 0)
            let pubkey = try secp256k1.Schnorr.PublicKey(dataRepresentation: key.publicKey.bytes, format: .compressed)
            let signature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: body.signature.bytes)
            XCTAssertTrue(try pubkey.xonly.isValidSignature(signature, for: CashuSwift.Crypto.nut20MessageToSign(
                quoteID: body.quote, outputs: body.outputs)))
            return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: F.promises(body.outputs)))
        }
        defer { stub.remove() }
        var mint = try F.mint(url: stub.url)
        let key = try O.quoteLockingKey(seed: F.seed, counter: 0)
        let context = try O.prepareMint(quote: F.mintQuote(), from: mint, amount: 6,
                                       seed: F.seed, quoteKey: key.privateKey, info: F.info(), preferredDistribution: [4, 2])
        XCTAssertEqual(context.material.counterRange?.start, 7)
        XCTAssertEqual(context.material.counterRange?.next, 9)
        XCTAssertTrue(stub.requests.isEmpty)
        let saved = try F.roundTrip(context)
        let result = try await O.mint(context: saved, from: mint)
        let proofs = try XCTUnwrap(result.recovery.proofs)
        XCTAssertEqual(proofs.map(\.amount), [4, 2])
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)

        mint.keysets[0].derivationCounter = try XCTUnwrap(context.material.counterRange).next
        let updated = try F.mintQuote(paid: 12, issued: 6, updated: 101)
        let second = try O.prepareMint(quote: updated, from: mint, amount: 6, seed: F.seed,
                                      quoteKey: key.privateKey, info: F.info())
        let secondResult = try await O.mint(context: second, from: mint)
        XCTAssertTrue(Set(proofs.map(\.secret)).isDisjoint(with: try XCTUnwrap(secondResult.recovery.proofs).map(\.secret)))
    }

    func testQuoteCreationRefreshAndBinding() async throws {
        let initial = try F.mintQuote(paid: 0)
        let paid = try F.mintQuote(updated: 101)
        let stub = try MintHTTPStub { request in
            switch request.url?.path {
            case "/v1/info": return try JSONEncoder().encode(F.info())
            case "/v1/mint/quote/onchain":
                let body = try JSONDecoder().decode(O.MintQuoteRequest.self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(Set(try F.json(body).keys), ["unit", "pubkey"])
                return try JSONEncoder().encode(initial)
            case "/v1/mint/quote/onchain/mint-1": return try JSONEncoder().encode(paid)
            default: throw O.Error.invalidResponse
            }
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let created = try await O.requestMintQuote(.init(unit: "sat", pubkey: initial.pubkey), from: mint)
        let refreshed = try await O.mintQuoteState(created, from: mint)
        XCTAssertEqual(refreshed.mintableAmount, 12)
        XCTAssertEqual(stub.requests.count, 3)
        await assertOnchainError(O.Error.invalidResponse) {
            let otherKey = try O.quoteLockingKey(seed: F.seed, counter: 1)
            _ = try await O.requestMintQuote(.init(unit: "sat", pubkey: otherKey.publicKey), from: mint, info: F.info())
        }
        await assertOnchainError(O.Error.invalidQuote) {
            _ = try await O.mintQuoteState("../info", from: mint)
        }
    }

    func testInvalidPreparationAndTamperedContextFailBeforeNetwork() async throws {
        let stub = try MintHTTPStub { _ in XCTFail("Unexpected request"); return Data() }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let quote = try F.mintQuote()
        let key = try O.quoteLockingKey(seed: F.seed, counter: 0)
        for amount in [-1, 0, 13] {
            XCTAssertThrowsError(try O.prepareMint(quote: quote, from: mint, amount: amount, seed: nil,
                                                 quoteKey: key.privateKey, info: F.info()))
        }
        XCTAssertThrowsError(try O.prepareMint(quote: quote, from: mint, amount: 6, seed: nil,
                                             quoteKey: Data(repeating: 1, count: 32), info: F.info()))
        XCTAssertThrowsError(try O.prepareMint(quote: quote, from: mint, amount: 6, seed: nil,
                                             quoteKey: key.privateKey, info: F.info(), preferredDistribution: [3, 3]))
        let context = try O.prepareMint(quote: quote, from: mint, amount: 6, seed: nil,
                                       quoteKey: key.privateKey, info: F.info())
        XCTAssertNil(context.material.counterRange)
        var json = try F.json(context)
        json["version"] = 2
        let unsupported: O.MintContext = try F.decode(json)
        await assertOnchainError(O.Error.unsupportedContextVersion) {
            _ = try await O.mint(context: unsupported, from: mint)
        }
        json = try F.json(context)
        var material = try XCTUnwrap(json["material"] as? [String: Any])
        material["secrets"] = ["tampered", "secrets"]
        json["material"] = material
        let tampered: O.MintContext = try F.decode(json)
        await assertOnchainError(O.Error.invalidContext) { _ = try await O.mint(context: tampered, from: mint) }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testRecoveryRejectsMissingInvalidAndMismatchedPromises() throws {
        let mint = try F.mint(url: XCTUnwrap(URL(string: "https://mint-tests.invalid")))
        let key = try O.quoteLockingKey(seed: F.seed, counter: 0)
        let context = try O.prepareMint(quote: F.mintQuote(), from: mint, amount: 6, seed: nil,
                                       quoteKey: key.privateKey, info: F.info())
        let good = try F.promises(context.material.outputs)
        let missing = good.map { CashuSwift.Promise(id: $0.id, amount: $0.amount, C_: $0.C_, dleq: nil) }
        if case .failed(.missingDLEQ) = O.recoverMint(promises: missing, context: context).recovery {} else { XCTFail() }
        XCTAssertNil(O.recoverMint(promises: Array(good.reversed()), context: context).recovery.proofs)
        XCTAssertNil(O.recoverMint(promises: Array(good.dropLast()), context: context).recovery.proofs)
        let wrongID = good.map { CashuSwift.Promise(id: "00wrong", amount: $0.amount, C_: $0.C_, dleq: $0.dleq) }
        XCTAssertNil(O.recoverMint(promises: wrongID, context: context).recovery.proofs)
        let invalidDLEQ = good.map { CashuSwift.Promise(id: $0.id, amount: $0.amount, C_: F.point, dleq: $0.dleq) }
        XCTAssertNil(O.recoverMint(promises: invalidDLEQ, context: context).recovery.proofs)
        XCTAssertEqual(O.recoverMint(promises: good, context: context).recovery.proofs?.count, 2)
    }

    func testLostMintResponseRestoresSavedRandomOutputs() async throws {
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/v1/mint/onchain" { throw URLError(.timedOut) }
            XCTAssertEqual(request.url?.path, "/v1/restore")
            let body = try JSONDecoder().decode(CashuSwift.RestoreRequest.self, from: XCTUnwrap(request.httpBody))
            let reordered = Array(body.outputs.reversed())
            return try JSONEncoder().encode(CashuSwift.RestoreResponse(outputs: reordered, signatures: F.promises(reordered)))
        }
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        let key = try O.quoteLockingKey(seed: F.seed, counter: 0)
        let prepared = try O.prepareMint(quote: F.mintQuote(), from: mint, amount: 6, seed: nil,
                                        quoteKey: key.privateKey, info: F.info())
        do { _ = try await O.mint(context: prepared, from: mint); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let restored = try await O.restoreMint(context: F.roundTrip(prepared), from: mint)
        XCTAssertEqual(restored.recovery.proofs?.map(\.amount), prepared.material.outputs.map(\.amount))
        XCTAssertEqual(restored.recovery.proofs?.map(\.secret), prepared.material.secrets)
        XCTAssertEqual(stub.requests.filter { $0.url?.path == "/v1/mint/onchain" }.count, 1)
    }
}
