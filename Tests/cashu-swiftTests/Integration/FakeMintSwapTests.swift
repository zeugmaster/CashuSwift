//
//  FakeMintSwapTests.swift
//  CashuSwiftTests
//
//  Send/receive/swap flows against the FakeWallet success mint. Includes
//  P2PK-locked variants and DLEQ verification paths.
//

import XCTest
@testable import CashuSwift
import BIP39

final class FakeMintSwapTests: XCTestCase {

    private let mintURL = TestEndpoints.fakeSuccess

    // Deterministic keypair used for the P2PK locking tests.
    private let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
    private let pubkeyHex     = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"

    // MARK: - Basic send / receive

    func testSendKeepsMixedAmount() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 32)
        let inputFee = try CashuSwift.calculateFee(for: proofs, of: mint)
        let sendResult = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: 20,
            seed: nil,
            memo: nil,
            lockToPublicKey: nil
        )
        XCTAssertEqual(sendResult.token.proofsByMint.first?.value.sum, 20)
        XCTAssertEqual(sendResult.change.sum, proofs.sum - 20 - inputFee,
                       "Change should cover the remainder minus any input fee")
        XCTAssertEqual(sendResult.outputDLEQ, .valid)
    }

    func testSendThenReceiveRestoresFullAmount() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 32)
        let sendResult = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: 8,
            seed: nil,
            memo: nil,
            lockToPublicKey: nil
        )
        guard let sentProofs = sendResult.token.proofsByMint.first?.value else {
            XCTFail("Token should have proofs")
            return
        }
        let received = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: nil)
        // Receive performs a swap, which itself charges the keyset's input fee.
        let receiveFee = try CashuSwift.calculateFee(for: sentProofs, of: mint)
        XCTAssertEqual(received.proofs.sum, 8 - receiveFee)
        XCTAssertEqual(received.inputDLEQ, .valid)
        XCTAssertEqual(received.outputDLEQ, .valid)
    }

    // MARK: - Swap DLEQ

    func testSwapWithFullDLEQValid() async throws {
        // 12-sat denominations so each proof is large enough to swap even after the input fee.
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 24)
        XCTAssertGreaterThanOrEqual(proofs.count, 1)
        let result = try await CashuSwift.swap(inputs: [proofs[0]], with: mint, seed: nil)
        XCTAssertEqual(result.inputDLEQ, .valid)
        XCTAssertEqual(result.outputDLEQ, .valid)
    }

    func testSwapWithoutInputDLEQReportsNoData() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 24)
        XCTAssertGreaterThanOrEqual(proofs.count, 2)
        let stripped = CashuSwift.Proof(keysetID: proofs[1].keysetID,
                                        amount: proofs[1].amount,
                                        secret: proofs[1].secret,
                                        C: proofs[1].C,
                                        dleq: nil)
        let result = try await CashuSwift.swap(inputs: [stripped], with: mint, seed: nil)
        XCTAssertEqual(result.inputDLEQ, .noData)
        XCTAssertEqual(result.outputDLEQ, .valid)
    }

    func testSwapWithTamperedDLEQFails() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 24)
        XCTAssertGreaterThanOrEqual(proofs.count, 1)
        let p = proofs[0]
        let tampered = CashuSwift.DLEQ(
            e: "b31e58ac6527f34975ffab13e70a48b6d2b0d35abc4b03f0151f09ee1a9763d4",
            s: "8fbae004c59e754d71df67e392b6ae4e29293113ddc2ec86592a0431d16306d8",
            r: "a6d13fcd7a18442e6076f5e1e7c887ad5de40a019824bdfa9fe740d302e8d861"
        )
        let bad = CashuSwift.Proof(keysetID: p.keysetID,
                                   amount: p.amount,
                                   secret: p.secret,
                                   C: p.C,
                                   dleq: tampered)
        let result = try await CashuSwift.swap(inputs: [bad], with: mint, seed: nil)
        XCTAssertEqual(result.inputDLEQ, .fail)
        XCTAssertEqual(result.outputDLEQ, .valid)
    }

    // MARK: - P2PK locked send / receive

    func testCreateAndReceiveP2PKLockedToken() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 16)
        let sendResult = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: 8,
            seed: nil,
            lockToPublicKey: pubkeyHex
        )
        XCTAssertEqual(sendResult.token.proofsByMint.first?.value.sum, 8)

        let received = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: privateKeyHex)
        guard let sentProofs = sendResult.token.proofsByMint.first?.value else {
            XCTFail("Token should have proofs"); return
        }
        let receiveFee = try CashuSwift.calculateFee(for: sentProofs, of: mint)
        XCTAssertEqual(received.proofs.sum, 8 - receiveFee)
    }

    func testReceiveWithWrongKeyFails() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 2)
        let sendResult = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: 1,
            seed: nil,
            lockToPublicKey: pubkeyHex
        )
        let wrongKey = "5111111111111111111111111111111111111111111111111111111111111111"
        do {
            _ = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: wrongKey)
            XCTFail("Expected receive to throw when the unlocking key does not match")
        } catch let error as CashuError {
            if case .spendingConditionError = error { return }
            XCTFail("Expected spendingConditionError, got \(error)")
        }
    }

    func testSendRejectsZeroAmount() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 4)
        do {
            _ = try await CashuSwift.send(
                inputs: proofs,
                mint: mint,
                amount: 0,
                seed: nil,
                lockToPublicKey: pubkeyHex
            )
            XCTFail("Expected invalidAmount error")
        } catch CashuError.invalidAmount {
            // expected
        }
    }

    // MARK: - NUT-18 payment request flow

    func testPayPaymentRequest_unlocked() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 64)
        let request = CashuSwift.PaymentRequest(
            paymentId: String(UUID().uuidString.prefix(6).lowercased()),
            amount: 21,
            unit: "sat",
            singleUse: true,
            mints: [],
            description: nil,
            transports: nil,
            lockingCondition: nil
        )
        let sendResult = try await CashuSwift.send(request: request, mint: mint, inputs: proofs, memo: nil, seed: nil)
        XCTAssertEqual(sendResult.payload.totalAmount(), 21)
        XCTAssertEqual(sendResult.payload.id, request.paymentId)
    }

    func testPayPaymentRequest_p2pkLocked() async throws {
        let (mint, proofs) = try await MintTestSupport.seedProofsAtFakeMint(mintURL, amount: 64)
        let request = CashuSwift.PaymentRequest(
            paymentId: String(UUID().uuidString.prefix(6).lowercased()),
            amount: 21,
            unit: "sat",
            singleUse: true,
            mints: [],
            description: nil,
            transports: nil,
            lockingCondition: CashuSwift.NUT10Option(kind: "P2PK", data: pubkeyHex, tags: nil)
        )
        let sendResult = try await CashuSwift.send(request: request, mint: mint, inputs: proofs, memo: nil, seed: nil)
        XCTAssertEqual(sendResult.payload.totalAmount(), 21)
        // Round-trip the payload through Token to confirm it can be received with the matching key.
        let token = sendResult.payload.toToken()
        let received = try await CashuSwift.receive(token: token, of: mint, seed: nil, privateKey: privateKeyHex)
        let receiveFee = try CashuSwift.calculateFee(for: sendResult.payload.proofs, of: mint)
        XCTAssertEqual(received.proofs.sum, 21 - receiveFee)
    }
}
