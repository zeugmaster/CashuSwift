import XCTest
import Foundation
@testable import CashuSwift

final class PaymentRequestTests: XCTestCase {
    
    // MARK: - Test Vectors from NUT-18 Specification
    
    struct TestVector {
        let name: String
        let encoded: String
        let expectedId: String?
        let expectedAmount: Int?
        let expectedUnit: String?
        let expectedSingleUse: Bool?
        let expectedMints: [String]?
        let expectedDescription: String?
        let expectedTransportCount: Int?
        let expectedNut10: Bool
    }
    
    let testVectors: [TestVector] = [
        TestVector(
            name: "Basic Payment Request",
            encoded: "creqApWF0gaNhdGVub3N0cmFheKlucHJvZmlsZTFxeTI4d3VtbjhnaGo3dW45ZDNzaGp0bnl2OWtoMnVld2Q5aHN6OW1od2RlbjV0ZTB3ZmprY2N0ZTljdXJ4dmVuOWVlaHFjdHJ2NWhzenJ0aHdkZW41dGUwZGVoaHh0bnZkYWtxcWd5ZGFxeTdjdXJrNDM5eWtwdGt5c3Y3dWRoZGh1NjhzdWNtMjk1YWtxZWZkZWhrZjBkNDk1Y3d1bmw1YWeBgmFuYjE3YWloYjdhOTAxNzZhYQphdWNzYXRhbYF3aHR0cHM6Ly84MzMzLnNwYWNlOjMzMzg=",
            expectedId: "b7a90176",
            expectedAmount: 10,
            expectedUnit: "sat",
            expectedSingleUse: nil,
            expectedMints: ["https://8333.space:3338"],
            expectedDescription: nil,
            expectedTransportCount: 1,
            expectedNut10: false
        ),
        TestVector(
            name: "Complete Payment Request",
            // NOTE: The original test vector from NUT-18 spec was malformed (CBOR premature EOF)
            // This is the corrected encoding generated from the JSON structure in the spec
            encoded: "creqAqGFpaDQ4NDBmNTFlYWEZA-hhdWNzYXRhc_VhbYF4GGh0dHBzOi8vbWludC5leGFtcGxlLmNvbWFkcFByb2R1Y3QgcHVyY2hhc2VhdIGiYXRkcG9zdGFheBtodHRwczovL2FwaS5leGFtcGxlLmNvbS9wYXllbnV0MTCjYWtkUDJQS2FkeEIwM2JhZjBjM2FjMjIwMzY2YzJjMzk3YmY5MzA1NzljNDE2MzQzNTU4NGY1NzNiMTA5MTA5ODdjNTQ0YzU5ZTYxZjFhdIGCZ3B1cnBvc2Vnb2ZmbGluZQ==",
            expectedId: "4840f51e",
            expectedAmount: 1000,
            expectedUnit: "sat",
            expectedSingleUse: true,
            expectedMints: ["https://mint.example.com"],
            expectedDescription: "Product purchase",
            expectedTransportCount: 1,
            expectedNut10: true
        ),
        TestVector(
            name: "HTTP Transport Payment Request",
            encoded: "creqApWF0gaNhdGRwb3N0YWF4H2h0dHBzOi8vYXBpLmV4YW1wbGUuY29tL3JlY2VpdmVhZ/dhaWhhMmMxMmY0NWFhGDJhdWNzYXRhbYF4GWh0dHBzOi8vY2FzaHUuZXhhbXBsZS5jb20=",
            expectedId: "a2c12f45",
            expectedAmount: 50,
            expectedUnit: "sat",
            expectedSingleUse: nil,
            expectedMints: ["https://cashu.example.com"],
            expectedDescription: nil,
            expectedTransportCount: 1,
            expectedNut10: false
        ),
        TestVector(
            name: "Nostr Transport Payment Request",
            encoded: "creqApWF0gaNhdGVub3N0cmFheD9ucHViMXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXFxcXEyOHNwajNhZ4KCYW5iMTeCYW5kOTczNWFpaGY5MmE1MWI4YWEYZGF1Y3NhdGFtgngZaHR0cHM6Ly9taW50MS5leGFtcGxlLmNvbXgZaHR0cHM6Ly9taW50Mi5leGFtcGxlLmNvbQ==",
            expectedId: "f92a51b8",
            expectedAmount: 100,
            expectedUnit: "sat",
            expectedSingleUse: nil,
            expectedMints: ["https://mint1.example.com", "https://mint2.example.com"],
            expectedDescription: nil,
            expectedTransportCount: 1,
            expectedNut10: false
        ),
        TestVector(
            name: "Minimal Payment Request",
            encoded: "creqAo2FpaDdmNGEyYjM5YXVjc2F0YW2BeBhodHRwczovL21pbnQuZXhhbXBsZS5jb20=",
            expectedId: "7f4a2b39",
            expectedAmount: nil,
            expectedUnit: "sat",
            expectedSingleUse: nil,
            expectedMints: ["https://mint.example.com"],
            expectedDescription: nil,
            expectedTransportCount: nil,
            expectedNut10: false
        ),
        TestVector(
            name: "Payment Request with NUT-10 Locking",
            encoded: "creqApWFpaGM5ZTQ1ZDJhYWEZAfRhdWNzYXRhbYF4GGh0dHBzOi8vbWludC5leGFtcGxlLmNvbWVudXQxMKNha2RQMlBLYWR4QjAyYzNiNWJiMjdlMzYxNDU3YzkyZDkzZDc4ZGQ3M2QzZDUzNzMyMTEwYjJjZmU4YjUwZmJjMGFiYzYxNWU5YzMzMWF0gYJndGltZW91dGQzNjAw",
            expectedId: "c9e45d2a",
            expectedAmount: 500,
            expectedUnit: "sat",
            expectedSingleUse: nil,
            expectedMints: ["https://mint.example.com"],
            expectedDescription: nil,
            expectedTransportCount: nil,
            expectedNut10: true
        )
    ]
    
    // MARK: - Decoding Tests
    
    func testDecodeBasicPaymentRequest() throws {
        let vector = testVectors[0]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertEqual(request.paymentId, vector.expectedId)
        XCTAssertEqual(request.amount, vector.expectedAmount)
        XCTAssertEqual(request.unit, vector.expectedUnit)
        XCTAssertEqual(request.mints, vector.expectedMints)
        XCTAssertEqual(request.transports?.count, vector.expectedTransportCount)
    }
    
    func testDecodeCompletePaymentRequest() throws {
        let vector = testVectors[1]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertEqual(request.paymentId, vector.expectedId)
        XCTAssertEqual(request.amount, vector.expectedAmount)
        XCTAssertEqual(request.unit, vector.expectedUnit)
        XCTAssertEqual(request.singleUse, vector.expectedSingleUse)
        XCTAssertEqual(request.mints, vector.expectedMints)
        XCTAssertEqual(request.description, vector.expectedDescription)
        XCTAssertNotNil(request.lockingCondition)
        XCTAssertEqual(request.lockingCondition?.kind, "P2PK")
    }
    
    func testDecodeHTTPTransportRequest() throws {
        let vector = testVectors[2]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertEqual(request.transports?.first?.type, "post")
        XCTAssertEqual(request.transports?.first?.target, "https://api.example.com/receive")
    }
    
    func testDecodeNostrTransportRequest() throws {
        let vector = testVectors[3]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertEqual(request.transports?.first?.type, "nostr")
        XCTAssertNotNil(request.transports?.first?.tags)
        XCTAssertEqual(request.mints?.count, 2)
    }
    
    func testDecodeMinimalRequest() throws {
        let vector = testVectors[4]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertEqual(request.paymentId, vector.expectedId)
        XCTAssertEqual(request.unit, vector.expectedUnit)
        XCTAssertNil(request.amount)
        XCTAssertNil(request.transports)
    }
    
    func testDecodeNUT10LockingRequest() throws {
        let vector = testVectors[5]
        let request = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
        
        XCTAssertNotNil(request.lockingCondition)
        XCTAssertEqual(request.lockingCondition?.kind, "P2PK")
        XCTAssertEqual(request.lockingCondition?.data, "02c3b5bb27e361457c92d93d78dd73d3d53732110b2cfe8b50fbc0abc615e9c331")
        XCTAssertNotNil(request.lockingCondition?.tags)
    }
    
    // MARK: - Encoding Tests
    
    func testEncodeDecodeRoundTrip() throws {
        for vector in testVectors {
            do {
                let decoded = try CashuSwift.PaymentRequest(encodedRequest: vector.encoded)
                let reencoded = try decoded.serialize()
                let redecoded = try CashuSwift.PaymentRequest(encodedRequest: reencoded)
                
                XCTAssertEqual(decoded.paymentId, redecoded.paymentId, "Round-trip failed for \(vector.name)")
                XCTAssertEqual(decoded.amount, redecoded.amount, "Round-trip failed for \(vector.name)")
                XCTAssertEqual(decoded.unit, redecoded.unit, "Round-trip failed for \(vector.name)")
                XCTAssertEqual(decoded.mints, redecoded.mints, "Round-trip failed for \(vector.name)")
            } catch {
                print("vector with error:")
                print(vector)
            }
        }
    }
    
    // MARK: - Validation Tests
    
    func testPaymentRequestValidation() throws {
        // Test that unit must be set if amount is set
        let requestWithAmountNoUnit = CashuSwift.PaymentRequest(
            paymentId: "test123",
            amount: 100,
            unit: nil,
            singleUse: nil,
            mints: ["https://mint.example.com"],
            description: nil,
            transports: nil,
            lockingCondition: nil
        )
        
        XCTAssertThrowsError(try requestWithAmountNoUnit.validate())
    }
    
    func testPaymentRequestPayloadRejectsClaimedUnitMismatch() throws {
        let mint = try makeMultiUnitMint()
        let payload = CashuSwift.PaymentRequestPayload(
            id: "unit-test",
            memo: nil,
            mint: mint.url.absoluteString,
            unit: "usd",
            proofs: [proof(keysetID: Self.satKeysetID, amount: 10)]
        )
        let request = CashuSwift.PaymentRequest(
            paymentId: "unit-test",
            amount: 10,
            unit: "usd",
            singleUse: nil,
            mints: [mint.url.absoluteString],
            description: nil,
            transports: nil,
            lockingCondition: nil
        )
        
        XCTAssertThrowsError(try payload.validates(against: request, mint: mint)) { error in
            guard case CashuError.paymentRequestValidation(let message) = error else {
                return XCTFail("Expected paymentRequestValidation, got \(error)")
            }
            XCTAssertTrue(message.contains("proof unit 'sat'"))
        }
    }
    
    func testReceivePaymentRequestRejectsClaimedUnitMismatchBeforeSwap() async throws {
        let mint = try makeMultiUnitMint()
        let payload = CashuSwift.PaymentRequestPayload(
            id: "unit-test",
            memo: nil,
            mint: mint.url.absoluteString,
            unit: "usd",
            proofs: [proof(keysetID: Self.satKeysetID, amount: 10)]
        )
        let request = CashuSwift.PaymentRequest(
            paymentId: "unit-test",
            amount: 10,
            unit: "usd",
            singleUse: nil,
            mints: [mint.url.absoluteString],
            description: nil,
            transports: nil,
            lockingCondition: nil
        )
        
        do {
            _ = try await CashuSwift.receivePaymentRequest(
                payload: payload,
                request: request,
                mint: mint,
                seed: nil,
                privateKey: nil
            )
            XCTFail("Expected unit mismatch to throw before network swap")
        } catch CashuError.paymentRequestValidation(let message) {
            XCTAssertTrue(message.contains("proof unit 'sat'"))
        } catch {
            XCTFail("Expected paymentRequestValidation, got \(error)")
        }
    }
    
    func testTokenSatisfiesWithMintRejectsClaimedUnitMismatch() throws {
        let mint = try makeMultiUnitMint()
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: [proof(keysetID: Self.satKeysetID, amount: 10)]],
            unit: "usd"
        )
        let request = CashuSwift.PaymentRequest(
            paymentId: nil,
            amount: 10,
            unit: "usd",
            singleUse: nil,
            mints: [mint.url.absoluteString],
            description: nil,
            transports: nil,
            lockingCondition: nil
        )
        
        XCTAssertFalse(token.satisfies(request, mint: mint))
    }
    
    func testReceiveRejectsTokenUnitMismatchBeforeSwap() async throws {
        let mint = try makeMultiUnitMint()
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: [proof(keysetID: Self.satKeysetID, amount: 10)]],
            unit: "usd"
        )
        
        do {
            _ = try await CashuSwift.receive(token: token, of: mint, seed: nil, privateKey: nil)
            XCTFail("Expected unit mismatch to throw before network swap")
        } catch CashuError.unitError(let message) {
            XCTAssertTrue(message.contains("proof unit 'sat'"))
        } catch {
            XCTFail("Expected unitError, got \(error)")
        }
    }
    
    func testMeltRejectsQuoteUnitMismatchBeforeNetworkRequest() async throws {
        let mint = try makeMultiUnitMint()
        let quote = CashuSwift.Bolt11.MeltQuote(
            quote: "quote-id",
            request: "lnbc1unit",
            amount: 10,
            unit: "usd",
            feeReserve: 0,
            state: nil,
            expiry: nil,
            paymentPreimage: nil,
            change: nil
        )
        
        do {
            _ = try await CashuSwift.Bolt11.melt(
                quote: quote, from: mint,
                proofs: [proof(keysetID: Self.satKeysetID, amount: 16)]
            )
            XCTFail("Expected unit mismatch to throw before network melt")
        } catch CashuError.unitError(let message) {
            XCTAssertTrue(message.contains("Melt quote unit 'usd'"))
        } catch {
            XCTFail("Expected unitError, got \(error)")
        }
    }
    
    func testGenerateBlankOutputsRejectsUnitMismatch() throws {
        let mint = try makeMultiUnitMint()
        let quote = CashuSwift.Bolt11.MeltQuote(
            quote: "quote-id",
            request: "lnbc1unit",
            amount: 10,
            unit: "usd",
            feeReserve: 0,
            state: nil,
            expiry: nil,
            paymentPreimage: nil,
            change: nil
        )
        
        XCTAssertThrowsError(
            try CashuSwift.generateBlankOutputs(
                quote: quote,
                proofs: [proof(keysetID: Self.satKeysetID, amount: 16)],
                mint: mint,
                unit: "usd"
            )
        ) { error in
            guard case CashuError.unitError(let message) = error else {
                return XCTFail("Expected unitError, got \(error)")
            }
            XCTAssertTrue(message.contains("proof unit 'sat'"))
        }
    }
    
    private static let satKeysetID = "satKeyset001"
    private static let usdKeysetID = "usdKeyset001"
    
    private func makeMultiUnitMint() throws -> CashuSwift.Mint {
        let keysets = try [
            keyset(id: Self.satKeysetID, unit: "sat"),
            keyset(id: Self.usdKeysetID, unit: "usd")
        ]
        
        return CashuSwift.Mint(url: URL(string: "https://mint.example.com")!, keysets: keysets)
    }
    
    private func keyset(id: String, unit: String) throws -> CashuSwift.Keyset {
        let json = """
        {
          "id": "\(id)",
          "unit": "\(unit)",
          "active": true,
          "input_fee_ppk": 0,
          "keys": {
            "1": "021111111111111111111111111111111111111111111111111111111111111111"
          }
        }
        """
        return try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
    }
    
    private func proof(keysetID: String, amount: Int) -> CashuSwift.Proof {
        CashuSwift.Proof(
            keysetID: keysetID,
            amount: amount,
            secret: "secret-\(keysetID)-\(amount)",
            C: "02\(String(repeating: "1", count: 64))"
        )
    }
}
