import XCTest
@testable import CashuSwift

final class QuoteOfferTests: XCTestCase {

    /// The example from the NUT-XX spec.
    static let specVector = "cquoteAp2FteBhodHRwczovL21pbnQuZXhhbXBsZS5jb21hb2RtaW50YWhmYnJhbmNoYXVjb3JhYWEZAfRhdHgkMDE5OGMwZWYtM2YxMS03MDAwLWEzZjctMmY0YjZlMmQ5YzFhYWRsQ2FzaCBkZXBvc2l0"

    func testDecodeSpecVector() throws {
        let offer = try CashuSwift.QuoteOffer(encodedOffer: Self.specVector)

        XCTAssertEqual(offer.mintURL, "https://mint.example.com")
        XCTAssertEqual(offer.operation, .mint)
        XCTAssertEqual(offer.method.rawValue, "branch")
        XCTAssertEqual(offer.unit, "ora")
        XCTAssertEqual(offer.amount, 500)
        XCTAssertEqual(offer.ticket, "0198c0ef-3f11-7000-a3f7-2f4b6e2d9c1a")
        XCTAssertEqual(offer.offerDescription, "Cash deposit")
        XCTAssertNil(offer.expiry)
    }

    func testEncodeSpecVectorByteExact() throws {
        let offer = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: CashuSwift.PaymentMethodID(rawValue: "branch"),
            unit: "ora",
            ticket: "0198c0ef-3f11-7000-a3f7-2f4b6e2d9c1a",
            amount: 500,
            offerDescription: "Cash deposit"
        )
        XCTAssertEqual(try offer.serialize(), Self.specVector)
    }

    func testEncodeDecodeRoundTripAllFields() throws {
        let offer = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .melt,
            method: CashuSwift.PaymentMethodID(rawValue: "branch"),
            unit: "ora",
            ticket: "0198c0ef-3f11-7000-a3f7-2f4b6e2d9c1a",
            amount: 1234,
            offerDescription: "Cash withdrawal",
            expiry: 1_900_000_000
        )
        let decoded = try CashuSwift.QuoteOffer(encodedOffer: try offer.serialize())
        XCTAssertEqual(decoded, offer)
    }

    func testEncodeDecodeRoundTripMinimalFields() throws {
        let offer = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .melt,
            method: CashuSwift.PaymentMethodID(rawValue: "branch"),
            unit: "ora",
            ticket: "abc"
        )
        let decoded = try CashuSwift.QuoteOffer(encodedOffer: try offer.serialize())
        XCTAssertEqual(decoded, offer)
        XCTAssertNil(decoded.amount)
        XCTAssertNil(decoded.offerDescription)
        XCTAssertNil(decoded.expiry)
    }

    func testDecodeRejectsInvalidInput() {
        // wrong prefix
        XCTAssertThrowsError(try CashuSwift.QuoteOffer(encodedOffer: "creqA" + Self.specVector.dropFirst(7)))
        // wrong version
        XCTAssertThrowsError(try CashuSwift.QuoteOffer(encodedOffer: "cquoteB" + Self.specVector.dropFirst(7)))
        // invalid CBOR payload
        XCTAssertThrowsError(try CashuSwift.QuoteOffer(encodedOffer: "cquoteAAAAA"))
        // valid CBOR but missing required fields ({} -> A0)
        XCTAssertThrowsError(try CashuSwift.QuoteOffer(encodedOffer: "cquoteAoA"))
    }

    func testExpiry() {
        let expired = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: "branch",
            unit: "ora",
            ticket: "t",
            amount: 1,
            expiry: 1_000_000
        )
        XCTAssertTrue(expired.isExpired())
        XCTAssertFalse(expired.isExpired(at: Date(timeIntervalSince1970: 999_999)))

        let unbounded = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: "branch",
            unit: "ora",
            ticket: "t",
            amount: 1
        )
        XCTAssertFalse(unbounded.isExpired())
    }

    // MARK: - Claim validation

    private func makeMint() throws -> CashuSwift.Mint {
        let json = """
        {
          "id": "005b109edf5a8bd6",
          "unit": "ora",
          "active": true,
          "input_fee_ppk": 0,
          "keys": {
            "1": "021111111111111111111111111111111111111111111111111111111111111111"
          }
        }
        """
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(json.utf8))
        return CashuSwift.Mint(url: URL(string: "https://mint.example.com")!, keysets: [keyset])
    }

    func testClaimValidation() async throws {
        let mint = try makeMint()
        let mintOffer = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: "branch",
            unit: "ora",
            ticket: "ticket-1",
            amount: 500
        )

        // melt claim on a mint offer
        do {
            _ = try await CashuSwift.QuoteOffers.requestMeltQuote(offer: mintOffer, from: mint)
            XCTFail("expected error")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteOfferValidation(""))
        }

        // mint claim without pubkey
        do {
            _ = try await CashuSwift.QuoteOffers.requestMintQuote(offer: mintOffer, pubkey: "", from: mint)
            XCTFail("expected error")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteOfferRequiresPubkey)
        }

        // expired offer
        let expired = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: "branch",
            unit: "ora",
            ticket: "ticket-2",
            amount: 500,
            expiry: 1_000_000
        )
        do {
            _ = try await CashuSwift.QuoteOffers.requestMintQuote(offer: expired, pubkey: "02aa", from: mint)
            XCTFail("expected error")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteOfferExpired)
        }

        // mint offer without amount
        let amountless = CashuSwift.QuoteOffer(
            mintURL: "https://mint.example.com",
            operation: .mint,
            method: "branch",
            unit: "ora",
            ticket: "ticket-3"
        )
        do {
            _ = try await CashuSwift.QuoteOffers.requestMintQuote(offer: amountless, pubkey: "02aa", from: mint)
            XCTFail("expected error")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteOfferValidation(""))
        }
    }

    // MARK: - Error code mapping

    func testOfferErrorCodeMapping() {
        XCTAssertEqual(
            Network.filterErrorMessage(#"{"detail":"ticket unknown","code":20010}"#) as? CashuError,
            .offerTicketUnknownOrExpired
        )
        XCTAssertEqual(
            Network.filterErrorMessage(#"{"detail":"ticket claimed","code":20011}"#) as? CashuError,
            .offerTicketAlreadyClaimed
        )
        // the loose nutshell "2001" workaround must not swallow the offer codes
        XCTAssertEqual(
            Network.filterErrorMessage(#"{"detail":"quote not paid","code":20001}"#) as? CashuError,
            .quoteNotPaid
        )
    }

    // MARK: - NUT-20

    func testNut20MessageAggregation() throws {
        let outputs = [
            CashuSwift.Output(amount: 1, B_: "02aabb", id: "005b109edf5a8bd6"),
            CashuSwift.Output(amount: 256, B_: "ccdd", id: "005b109edf5a8bd6"),
        ]
        let msg = try CashuSwift.Crypto.nut20MessageToSign(quoteID: "q1", outputs: outputs)

        var expected = [UInt8]("Cashu_MintQuoteSig_v1".utf8)
        expected += [0, 0, 0, 2] + [UInt8]("q1".utf8)          // len32("q1") || "q1"
        expected += [0, 0, 0, 1, 0x01]                          // amount 1 -> 0x01
        expected += [0, 0, 0, 3, 0x02, 0xAA, 0xBB]              // B_ raw bytes
        expected += [0, 0, 0, 2, 0x01, 0x00]                    // amount 256 -> 0x0100
        expected += [0, 0, 0, 2, 0xCC, 0xDD]
        XCTAssertEqual([UInt8](msg), expected)
    }

    func testNut20LegacyMessageAggregation() {
        let outputs = [
            CashuSwift.Output(amount: 1, B_: "02AABB", id: "005b109edf5a8bd6"),
            CashuSwift.Output(amount: 256, B_: "ccdd", id: "005b109edf5a8bd6"),
        ]
        let msg = CashuSwift.Crypto.nut20LegacyMessageToSign(quoteID: "q1", outputs: outputs)
        XCTAssertEqual(msg, Data("q102aabbccdd".utf8))
    }

    func testNut20KeyDerivationAndSignature() throws {
        let seed = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

        let key0 = try CashuSwift.QuoteOffers.quoteLockingKey(seed: seed, counter: 0)
        let key0Again = try CashuSwift.QuoteOffers.quoteLockingKey(seed: seed, counter: 0)
        let key1 = try CashuSwift.QuoteOffers.quoteLockingKey(seed: seed, counter: 1)

        // deterministic and counter-separated
        XCTAssertEqual(key0.privateKey, key0Again.privateKey)
        XCTAssertEqual(key0.publicKey, key0Again.publicKey)
        XCTAssertNotEqual(key0.privateKey, key1.privateKey)

        // compressed secp256k1 pubkey, hex-encoded
        XCTAssertEqual(key0.publicKey.count, 66)
        XCTAssertTrue(key0.publicKey.hasPrefix("02") || key0.publicKey.hasPrefix("03"))

        let outputs = [CashuSwift.Output(amount: 8, B_: "02aabb", id: "005b109edf5a8bd6")]
        let signature = try CashuSwift.Crypto.nut20Signature(
            quoteID: "9d745270-1405-46de-b5c5-e2762b4f5e00",
            outputs: outputs,
            privateKey: key0.privateKey
        )
        // 64-byte BIP340 Schnorr signature, hex-encoded
        XCTAssertEqual(signature.count, 128)
    }
}
