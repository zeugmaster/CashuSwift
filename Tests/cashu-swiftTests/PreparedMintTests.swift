import Foundation
import XCTest
import secp256k1
@testable import CashuSwift

final class PreparedMintTests: XCTestCase {
    func testBolt11RetainsAccountingAndMintsRemainingOrPartialBalance() async throws {
        let key = try CashuSwift.quoteLockingKey(seed: V3Fixture.seed, mintPubkey: OnchainFixture.point, counter: 0)
        let quote: CashuSwift.Bolt11.MintQuote = try OnchainFixture.decode([
            "quote": "bolt11-quote", "request": "lnbc-test", "unit": "sat", "amount": 12,
            "state": "ISSUED", "pubkey": key.publicKey, "amount_paid": 12, "amount_issued": 4
        ])
        XCTAssertEqual(try quote.mintableAmount, 8)
        XCTAssertEqual(try OnchainFixture.roundTrip(quote).quoteAmountIssued, 4)
        let stub = try MintHTTPStub { request in
            if request.httpMethod == "GET" { return try JSONEncoder().encode(quote) }
            XCTAssertEqual(request.url?.path, "/v1/mint/bolt11")
            let body = try JSONDecoder().decode(CashuSwift.SignedMintExecutionBody.self, from: XCTUnwrap(request.httpBody))
            let tx = try CashuSwift.Transaction(mintQuote: quote, outputs: body.outputs)
            try CashuSwift.Nutroot.verifyWitness(.init(signatures: [body.signature]), secret: key.publicKey,
                inputDigest: tx.inputDigest(0))
            return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: V3Fixture.promises(body.outputs)))
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url)
        let remaining = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: nil, quoteKey: key.privateKey)
        XCTAssertEqual(remaining.proofs.map(\.amount), [8])
        let partial = try await CashuSwift.Bolt11.mint(quote: quote, from: mint, amount: 2, seed: nil, quoteKey: key.privateKey)
        XCTAssertEqual(partial.proofs.map(\.amount), [2])
        let outputs = try CashuSwift.Crypto.generateOutputs(amounts: [2], keysetID: mint.keysets[0].keysetID).outputs
        for (paid, issued): (Int?, Int?) in [(nil, nil), (12, nil), (nil, 4), (-1, 0), (12, -1), (12, 13)] {
            let invalid = CashuSwift.Bolt11.MintQuote(quote: quote.quote, request: quote.request, amount: 12,
                unit: "sat", state: .paid, expiry: nil, pubkey: key.publicKey, amountPaid: paid, amountIssued: issued)
            XCTAssertThrowsError(try invalid.mintableAmount)
            XCTAssertThrowsError(try CashuSwift.Transaction(mintQuote: invalid, outputs: outputs))
        }
        XCTAssertThrowsError(try CashuSwift.prepareMint(quote: quote, from: mint, amount: 16, seed: nil))
    }

    func testKeyPathMintSignsRefreshedAccountingAndRejectsChangedQuoteIdentity() async throws {
        let key = try CashuSwift.Crypto.v3QuoteLockKey(seed: V3Fixture.seed,
            mintPubkey: OnchainFixture.point, counter: 0)
        let old = CashuSwift.Bolt12.MintQuote(quote: "quote-1", request: "lno-test", amount: nil, unit: "sat",
            expiry: nil, pubkey: key.publicKey, amountPaid: 16, amountIssued: 0)
        let current = CashuSwift.Bolt12.MintQuote(quote: old.quote, request: old.request, amount: nil, unit: "sat",
            expiry: nil, pubkey: key.publicKey, amountPaid: 16, amountIssued: 4)
        let stub = try MintHTTPStub { request in
            if request.httpMethod == "GET" { return try JSONEncoder().encode(current) }
            let body = try JSONDecoder().decode(CashuSwift.SignedMintExecutionBody.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.signature.count, 128)
            let witness = CashuSwift.Proof.Witness(signatures: [body.signature])
            try CashuSwift.Nutroot.verifyWitness(witness, secret: key.publicKey,
                inputDigest: CashuSwift.Transaction(mintQuote: current, outputs: body.outputs).inputDigest(0))
            XCTAssertThrowsError(try CashuSwift.Nutroot.verifyWitness(witness, secret: key.publicKey,
                inputDigest: CashuSwift.Transaction(mintQuote: old, outputs: body.outputs).inputDigest(0)))
            return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: V3Fixture.promises(body.outputs)))
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url)
        let result = try await CashuSwift.Bolt12.mint(quote: old, from: mint, amount: 6,
            seed: V3Fixture.seed, quoteKey: key.privateKey)
        XCTAssertEqual(result.dleqResult, .valid)
        XCTAssertEqual(stub.requests.map(\.httpMethod), ["GET", "POST"])

        let changed = CashuSwift.Bolt12.MintQuote(quote: "another-quote", request: old.request, amount: nil, unit: "sat",
            expiry: nil, pubkey: key.publicKey, amountPaid: 16, amountIssued: 0)
        do {
            _ = try await CashuSwift.Bolt12.mint(quote: changed, from: mint, amount: 6,
                seed: V3Fixture.seed, quoteKey: key.privateKey)
            XCTFail("mismatched refreshed quote accepted")
        } catch CashuError.inputError { }
        XCTAssertEqual(stub.requests.map(\.httpMethod), ["GET", "POST", "GET"])
    }

    func testQuoteScriptPathMintAndRestoreUseThePersistedOutputs() async throws {
        let signer = try secp256k1.Schnorr.PrivateKey(dataRepresentation: [UInt8](repeating: 0, count: 31) + [3])
        let internalKey = try CashuSwift.Crypto.PrivateKey(dataRepresentation: [UInt8](repeating: 0, count: 31) + [6]).publicKey
        let leaf = try CashuSwift.Nutroot.Leaf.threshold(n: 1, keys: [String(bytes: signer.publicKey.dataRepresentation)]).serializedHex()
        let lockKey = try CashuSwift.Nutroot.secret(internalKey: internalKey, leaves: [leaf.bytes])
        let quote = CashuSwift.Bolt12.MintQuote(quote: "script-quote", request: "lno-test", amount: nil, unit: "sat",
            expiry: nil, pubkey: String(bytes: lockKey.dataRepresentation), amountPaid: 12, amountIssued: 4)
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/v1/restore" {
                let body = try JSONDecoder().decode(CashuSwift.RestoreRequest.self, from: XCTUnwrap(request.httpBody))
                let reversed = Array(body.outputs.reversed())
                return try JSONEncoder().encode(CashuSwift.RestoreResponse(outputs: reversed, signatures: V3Fixture.promises(reversed)))
            }
            XCTAssertEqual(request.url?.path, "/v1/mint/bolt12")
            let body = try JSONDecoder().decode(CashuSwift.SignedMintExecutionBody.self, from: XCTUnwrap(request.httpBody))
            let witness = try CashuSwift.Proof.Witness(json: body.signature)
            XCTAssertEqual(witness.leaf, leaf)
            let tx = try CashuSwift.Transaction(mintQuote: quote, outputs: body.outputs)
            try CashuSwift.Nutroot.verifyWitness(witness, secret: quote.pubkey, inputDigest: tx.inputDigest(0))
            return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: V3Fixture.promises(body.outputs)))
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url)
        let prepared = try CashuSwift.prepareMint(quote: quote, from: mint, amount: 6, seed: V3Fixture.seed)
        for counter in [-1, Int.max] {
            let invalid = try V3Fixture.mint(url: stub.url, counter: counter)
            XCTAssertThrowsError(try CashuSwift.prepareMint(quote: quote, from: invalid, amount: 6, seed: V3Fixture.seed))
        }
        let saved = try OnchainFixture.roundTrip(prepared)
        XCTAssertEqual(saved.nextCounter, 9)
        XCTAssertEqual(stub.requests.count, 0)
        let package = try CashuSwift.SigningPackage(transaction: saved.transaction(), mintQuoteInput: 0,
            internalKey: String(bytes: internalKey.dataRepresentation), tree: [leaf], leafIndex: 0)
        let signed = try package.signed(with: [signer])
        let result = try await CashuSwift.mint(prepared: saved, from: mint, signingPackage: signed)
        XCTAssertEqual(result.proofs.map(\.amount), [2, 4])
        XCTAssertEqual(result.dleqResult, .valid)
        XCTAssertTrue(result.proofs.allSatisfy { $0.spendInfo?.k != nil })
        let restored = try await CashuSwift.restoreMint(prepared: saved, from: CashuSwift.Mint(url: mint.url, keysets: []))
        XCTAssertEqual(restored.proofs, result.proofs)

        // Reusing a valid package for a different preparation must fail before submitting.
        let other = try CashuSwift.prepareMint(quote: quote, from: mint, amount: 6, seed: nil)
        do {
            _ = try await CashuSwift.mint(prepared: other, from: mint, signingPackage: signed)
            XCTFail("package for different outputs accepted")
        } catch CashuError.inputError { }
        XCTAssertEqual(stub.requests.count, 2)
        let promises = try V3Fixture.promises(saved.outputs)
        let swapped = Array(promises.reversed())
        XCTAssertThrowsError(try CashuSwift.recoverMint(promises: swapped, prepared: saved))
        var json = try OnchainFixture.json(saved)
        json["secrets"] = Array(repeating: String(repeating: "00", count: 31) + "01", count: saved.outputs.count)
        let tampered: CashuSwift.PreparedMint<CashuSwift.Bolt12.MintQuote> = try OnchainFixture.decode(json)
        XCTAssertThrowsError(try CashuSwift.recoverMint(promises: promises, prepared: tampered))
    }

    func testMintTransactionAcceptsSeveralV3KeysetsAndRejectsMixedVersions() throws {
        let quote = try OnchainFixture.mintQuote()
        let mint = try V3Fixture.mint(url: XCTUnwrap(URL(string: "https://mint.invalid")))
        let outputs = try CashuSwift.Crypto.generateOutputs(amounts: [2, 4], keysetID: mint.keysets[0].keysetID).outputs
        let secondID = "02" + String(repeating: "aa", count: 32)
        let across = [outputs[0], CashuSwift.Output(amount: 4, B_: outputs[1].B_, id: secondID)]
        XCTAssertNoThrow(try CashuSwift.Transaction(mintQuote: quote, outputs: across).transcript())
        let mixed = [outputs[0], CashuSwift.Output(amount: 4, B_: OnchainFixture.point, id: "00abcdef01234567")]
        XCTAssertThrowsError(try CashuSwift.Transaction(mintQuote: quote, outputs: mixed))
    }
}
