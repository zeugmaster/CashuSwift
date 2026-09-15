import XCTest
@testable import CashuSwift

final class OnchainModelTests: XCTestCase {
    typealias F = OnchainFixture
    typealias O = CashuSwift.Onchain

    func testMintWireSchemaAndAccounting() throws {
        let quote = try F.mintQuote(paid: Int.max, issued: Int.max - 2)
        XCTAssertEqual(quote.mintableAmount, 2)
        XCTAssertNil(quote.amount)
        XCTAssertNil(quote.state)
        var json = try F.json(quote)
        XCTAssertEqual(json["updated_at"] as? Int, 100)
        XCTAssertNil(json["amount"])
        XCTAssertNil(json["state"])
        json["future"] = ["anything": true]
        let decoded: O.MintQuote = try F.decode(json)
        XCTAssertEqual(decoded.mintableAmount, 2)
        for field in ["method", "updated_at", "amount_paid", "amount_issued", "pubkey"] {
            var missing = json
            missing.removeValue(forKey: field)
            XCTAssertThrowsError(try F.decode(missing) as O.MintQuote, field)
        }
        for (paid, issued) in [(-1, 0), (0, -1), (0, 1), (Int.max, Int.min)] {
            XCTAssertThrowsError(try F.mintQuote(paid: paid, issued: issued))
        }
        json["amount_paid"] = NSNumber(value: UInt64.max)
        XCTAssertThrowsError(try F.decode(json) as O.MintQuote)
        json["amount_paid"] = 1.5
        XCTAssertThrowsError(try F.decode(json) as O.MintQuote)
    }

    func testStaleMergeAndIdentityBinding() throws {
        let current = try F.mintQuote(paid: 20, issued: 12, updated: 20)
        XCTAssertEqual(try current.merging(F.mintQuote(updated: 10)).amountPaid, 20)
        XCTAssertThrowsError(try current.merging(F.mintQuote(updated: 20)))
        XCTAssertThrowsError(try current.merging(F.mintQuote(updated: 21)))
        XCTAssertThrowsError(try current.merging(F.mintQuote(id: "other")))
        XCTAssertEqual(try current.merging(F.mintQuote(paid: 30, issued: 20, updated: 21)).mintableAmount, 10)
    }

    func testFeeChoiceIsAnIdentifierAndNotSerialized() throws {
        let quote = try F.meltQuote()
        XCTAssertThrowsError(try quote.requiredInputAmount(inputFee: 0))
        let selected = try quote.selectingFee(index: 7)
        XCTAssertEqual(try selected.requiredInputAmount(inputFee: 1), 13)
        XCTAssertNil(selected.selectedFeeIndex)
        XCTAssertEqual(selected.requestedFeeIndex, 7)
        XCTAssertThrowsError(try quote.selectingFee(index: 0))
        let decoded = try F.roundTrip(selected)
        XCTAssertNil(decoded.requestedFeeIndex)
        XCTAssertThrowsError(try decoded.requiredInputAmount(inputFee: 0))
        let executed = try F.meltQuote(state: .pending, selected: 7)
        XCTAssertEqual(try executed.requiredInputAmount(inputFee: 1), 13)
        XCTAssertThrowsError(try executed.selectingFee(index: 2))
    }

    func testRejectMalformedMeltQuotes() throws {
        let json = try F.json(F.meltQuote())
        let mutations: [(String, Any)] = [
            ("method", "bolt11"), ("state", "ISSUED"), ("state", "PAID"), ("amount", 0),
            ("amount", -1), ("fee_options", []), ("selected_fee_index", 9), ("outpoint", "abc:0"),
            ("request", "bitcoin:bc1qexample"), ("quote", "../info"), ("quote", "%2Finfo")
        ]
        for (key, value) in mutations {
            var invalid = json
            invalid[key] = value
            XCTAssertThrowsError(try F.decode(invalid) as O.MeltQuote, key)
        }
        var duplicate = json
        duplicate["fee_options"] = [try F.json(F.fees()[0]), try F.json(F.fees()[0])]
        XCTAssertThrowsError(try F.decode(duplicate) as O.MeltQuote)
        XCTAssertThrowsError(try O.FeeOption(feeIndex: -1, feeReserve: 0, estimatedBlocks: 1))
        XCTAssertThrowsError(try O.FeeOption(feeIndex: 0, feeReserve: -1, estimatedBlocks: 1))
        XCTAssertThrowsError(try O.FeeOption(feeIndex: 0, feeReserve: 0, estimatedBlocks: 0))
    }

    func testArithmeticAndAvailability() throws {
        let quote = try F.meltQuote(amount: Int.max).selectingFee(index: 7)
        XCTAssertThrowsError(try quote.requiredInputAmount(inputFee: 0))
        XCTAssertThrowsError(try F.meltQuote().selectingFee(index: 7).requiredInputAmount(inputFee: -1))
        let info = try F.info()
        XCTAssertTrue(info.supports(method: .onchain, unit: "sat", direction: .mint))
        let settings = try O.settings(in: info, unit: "sat", direction: .mint)
        XCTAssertEqual(settings.confirmations, 1)
        XCTAssertThrowsError(try settings.validate(amount: 0))
        XCTAssertThrowsError(try settings.validate(amount: 1_000_001))
        XCTAssertThrowsError(try O.settings(in: F.info(disabled: true), unit: "sat", direction: .melt))
        XCTAssertThrowsError(try O.settings(in: info, unit: "usd", direction: .mint))
        XCTAssertThrowsError(try O.settings(in: F.info(confirmations: 1.5), unit: "sat", direction: .mint))
        XCTAssertThrowsError(try O.settings(in: F.info(confirmations: -1), unit: "sat", direction: .mint))
        XCTAssertThrowsError(try O.quoteLockingKey(seed: F.seed, counter: UInt32.max))
    }

    func testCDKUnbroadcastOutpointCompatibility() throws {
        var json = try F.json(F.meltQuote(state: .pending, selected: 7))
        json["outpoint"] = ""
        let quote: O.MeltQuote = try F.decode(json)
        XCTAssertNil(quote.outpoint)
        XCTAssertEqual(quote.state, .pending)
        json["outpoint"] = "not-a-transaction"
        XCTAssertThrowsError(try F.decode(json) as O.MeltQuote)
    }
}
