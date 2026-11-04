import Foundation
import XCTest
import secp256k1
@testable import CashuSwift

final class OnchainV3Tests: XCTestCase {
    typealias O = CashuSwift.Onchain
    typealias F = OnchainFixture

    func testOnchainMintSignsIssuedAmountAndRecoversWithoutDLEQAfterRotation() async throws {
        let key = try CashuSwift.quoteLockingKey(seed: V3Fixture.seed, mintPubkey: F.point, counter: 0)
        let quote = try O.MintQuote(quote: "v3-mint", request: F.address, unit: "sat", expiry: nil,
            pubkey: key.publicKey, amountPaid: 12, amountIssued: 4, updatedAt: 100)
        let stub = try MintHTTPStub { request in
            XCTAssertEqual(request.url?.path, "/v1/mint/onchain")
            let body = try JSONDecoder().decode(CashuSwift.SignedMintExecutionBody.self, from: XCTUnwrap(request.httpBody))
            let tx = try CashuSwift.Transaction(mintQuote: quote, outputs: body.outputs)
            XCTAssertTrue(CashuSwift.Crypto.schnorrVerify(digest: try tx.inputDigest(0),
                signatureHex: body.signature, publicKey: try quote.pubkey.bytes))
            return try JSONEncoder().encode(CashuSwift.MintExecutionResponse(signatures: V3Fixture.promises(body.outputs)))
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url, counter: Int(UInt32.max) + 1)
        let context = try O.prepareMint(quote: quote, from: mint, amount: 6, seed: V3Fixture.seed,
                                        quoteKey: key.privateKey, info: F.info())
        let saved = try F.roundTrip(context)
        XCTAssertEqual(saved.material.counterRange?.next, Int(UInt32.max) + 3)
        let result = try await O.mint(context: saved, from: mint)
        let proofs = try XCTUnwrap(result.recovery.proofs)
        XCTAssertEqual(proofs.map(\.amount), [2, 4])
        XCTAssertTrue(proofs.allSatisfy { $0.dleq == nil && $0.spendInfo?.k != nil })
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)
        XCTAssertEqual(O.recoverMint(promises: result.promises, context: saved).recovery.proofs, proofs)

        var json = try F.json(saved)
        var quoteJSON = try XCTUnwrap(json["quote"] as? [String: Any])
        quoteJSON["amount_issued"] = 5
        json["quote"] = quoteJSON
        let changed: O.MintContext = try F.decode(json)
        await assertOnchainError(O.Error.invalidContext) { _ = try await O.mint(context: changed, from: mint) }
        XCTAssertEqual(stub.requests.count, 1)

        let malformed = result.promises.map {
            CashuSwift.Promise(id: $0.id, amount: $0.amount, C_: $0.C_, dleq: .init(e: "00", s: "00", r: nil))
        }
        XCTAssertNil(O.recoverMint(promises: malformed, context: saved).recovery.proofs)
    }

    func testOnchainMeltBindsSelectedFeeAndRecoversBLSChangeAfterRotation() async throws {
        var context: O.MeltContext?
        let stub = try MintHTTPStub { request in
            let saved = try XCTUnwrap(context)
            if request.httpMethod == "POST" {
                let body = try JSONDecoder().decode(O.MeltExecutionBody.self, from: XCTUnwrap(request.httpBody))
                XCTAssertEqual(body.feeIndex, 7)
                let tx = CashuSwift.Transaction(inputs: body.inputs.map { .proof($0) },
                    outputs: (body.outputs ?? []).map { .blinded($0) } + [.meltQuote(id: saved.quote.quote, amount: 12)])
                for (i, proof) in body.inputs.enumerated() {
                    XCTAssertNil(proof.spendInfo)
                    XCTAssertNil(proof.dleq)
                    let witness = try CashuSwift.Proof.Witness(json: XCTUnwrap(proof.witness))
                    try CashuSwift.Nutroot.verifyWitness(witness, secret: proof.secret, inputDigest: tx.inputDigest(i))
                }
                return try JSONEncoder().encode(F.meltQuote(state: .pending))
            }
            let promises = try V3Fixture.promises(Array(saved.material.outputs.prefix(2)), amounts: [2, 4])
            return try JSONEncoder().encode(F.meltQuote(state: .paid, selected: 7, outpoint: F.outpoint, change: promises))
        }
        defer { stub.remove() }
        let mint = try V3Fixture.mint(url: stub.url)
        context = try O.prepareMelt(quote: F.meltQuote(), feeIndex: 7, from: mint,
                                    proofs: V3Fixture.proofs([16], mint: mint), seed: V3Fixture.seed, info: F.info())
        let saved = try F.roundTrip(XCTUnwrap(context))
        XCTAssertNil(saved.inputs[0].spendInfo)
        let pending = try await O.melt(context: saved, from: mint)
        XCTAssertEqual(pending.quote.state, .pending)
        let paid = try await O.meltState(context: saved, from: CashuSwift.Mint(url: mint.url, keysets: []))
        XCTAssertEqual(paid.quote.state, .paid)
        let proofs = try XCTUnwrap(paid.changeRecovery.proofs)
        XCTAssertEqual(proofs.map(\.amount), [2, 4])
        XCTAssertEqual(try CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint), .valid)

        var json = try F.json(saved)
        json["feeIndex"] = 2
        let changed: O.MeltContext = try F.decode(json)
        do {
            _ = try await O.melt(context: changed, from: mint)
            XCTFail("a witness authorized a different fee selection")
        } catch CashuError.spendingConditionError { }
        XCTAssertEqual(stub.requests.count, 2)
    }
}
