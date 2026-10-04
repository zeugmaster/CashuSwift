import Foundation
import XCTest
@testable import CashuSwift

/// Opt in with Tests/OnchainRegtest/run.sh. Enabled tests fail on unavailable services.
final class OnchainRegtestTests: XCTestCase {
    typealias O = CashuSwift.Onchain

    func testDepositsPartialIssuanceWithdrawalAndResume() async throws {
        guard ProcessInfo.processInfo.environment["CASHUSWIFT_ONCHAIN_REGTEST"] == "1" else {
            throw XCTSkip("Run Tests/OnchainRegtest/run.sh to enable the pinned regtest services.")
        }
        let chain = try await rpc("getblockchaininfo")
        XCTAssertEqual((chain as? [String: Any])?["chain"] as? String, "regtest")
        guard (chain as? [String: Any])?["chain"] as? String == "regtest" else { throw O.Error.invalidContext }
        _ = try await rpc("createwallet", ["cashuswift-tests"])
        let miningResponse = try await rpc("getnewaddress")
        let miningAddress = try XCTUnwrap(miningResponse as? String)
        _ = try await rpc("generatetoaddress", [101, miningAddress])

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:19338"))
        var info: CashuSwift.Mint.Info?
        for _ in 0..<60 {
            do { info = try await Network.strictGet(url: url.appending(path: "v1/info"), expected: CashuSwift.Mint.Info.self); break }
            catch { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        let metadata = try XCTUnwrap(info, "Regtest mint did not start")
        XCTAssertEqual(try O.settings(in: metadata, unit: "sat", direction: .mint).confirmations, 2)
        var mint = try await CashuSwift.loadMint(url: url)
        let key = try O.quoteLockingKey(seed: OnchainFixture.seed, counter: 0)
        var quote = try await O.requestMintQuote(.init(unit: "sat", pubkey: key.publicKey), from: mint, info: metadata)
        XCTAssertTrue(quote.request.hasPrefix("bcrt1"))
        XCTAssertEqual(quote.mintableAmount, 0)

        // Two sub-minimum UTXOs must not be aggregated into a creditable deposit.
        _ = try await rpc("sendtoaddress", [quote.request, "0.000006"])
        _ = try await rpc("sendtoaddress", [quote.request, "0.000006"])
        _ = try await rpc("sendtoaddress", [quote.request, "0.0002"])
        _ = try await rpc("generatetoaddress", [1, miningAddress])
        try await Task.sleep(nanoseconds: 3_000_000_000)
        quote = try await O.mintQuoteState(quote, from: mint)
        XCTAssertEqual(quote.amountPaid, 0, "Deposit must wait for two confirmations")
        _ = try await rpc("generatetoaddress", [1, miningAddress])
        quote = try await waitForPaid(quote, amount: 20_000, mint: mint)

        var proofs = [CashuSwift.Proof]()
        for amount in [8_000, 12_000] {
            let prepared = try O.prepareMint(quote: quote, from: mint, amount: amount, seed: OnchainFixture.seed,
                                            quoteKey: key.privateKey, info: metadata)
            let saved = try OnchainFixture.roundTrip(prepared)
            let result = try await O.mint(context: saved, from: mint)
            proofs += try XCTUnwrap(result.recovery.proofs, "Mint signatures must pass DLEQ")
            if let range = saved.material.counterRange,
               let i = mint.keysets.firstIndex(where: { $0.keysetID == range.keysetID }) {
                mint.keysets[i].derivationCounter = range.next
            }
            quote = try await O.mintQuoteState(quote, from: mint)
        }
        XCTAssertEqual(quote.mintableAmount, 0)
        _ = try await rpc("sendtoaddress", [quote.request, "0.0001"])
        _ = try await rpc("generatetoaddress", [2, miningAddress])
        quote = try await waitForPaid(quote, amount: 30_000, mint: mint)
        XCTAssertEqual(quote.mintableAmount, 10_000)

        let recipientResponse = try await rpc("getnewaddress")
        let recipient = try XCTUnwrap(recipientResponse as? String)
        let meltQuote = try await O.requestMeltQuote(.init(unit: "sat", request: recipient, amount: 5_000),
                                                   from: mint, info: metadata)
        XCTAssertGreaterThan(meltQuote.feeOptions.count, 1)
        // Choose a non-default tier and persist it separately from the response.
        let feeIndex = try XCTUnwrap(meltQuote.feeOptions.last).feeIndex
        let target = try meltQuote.selectingFee(index: feeIndex).requiredInputAmount(inputFee: 0)
        let selection = try CashuSwift.selectProofs(proofs, targetAmount: target, mint: mint, unit: "sat", purpose: .melt)
        let prepared = try O.prepareMelt(quote: meltQuote, feeIndex: feeIndex, from: mint,
                                        proofs: selection.selected, seed: OnchainFixture.seed, info: metadata)
        let saved = try OnchainFixture.roundTrip(prepared)
        let pending = try await O.melt(context: saved, from: mint)
        XCTAssertEqual(pending.quote.state, .pending)
        var result = pending
        var broadcastTxID: String?
        for _ in 0..<60 {
            result = try await O.meltState(context: saved, from: mint)
            // CDK 0.18 exposes outpoint only at settlement. Check actual broadcast
            // in this otherwise empty regtest mempool before mining confirmations.
            let mempool = try await rpc("getrawmempool")
            if let txID = (mempool as? [String])?.first { broadcastTxID = txID; break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let txID = try XCTUnwrap(broadcastTxID, "Mint must broadcast the withdrawal")
        XCTAssertEqual(result.quote.state, .pending)
        _ = try await rpc("generatetoaddress", [2, miningAddress])
        for _ in 0..<60 {
            result = try await O.meltState(context: saved, from: mint)
            if result.quote.state == .paid { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTAssertEqual(result.quote.state, .paid)
        XCTAssertTrue(result.quote.outpoint?.hasPrefix(txID + ":") == true)
        let change = try XCTUnwrap(result.changeRecovery.proofs)
        let replay = try await O.meltState(context: saved, from: mint)
        XCTAssertEqual(replay.changeRecovery.proofs?.map(\.secret), change.map(\.secret))
        let received = try await rpc("getreceivedbyaddress", [recipient, 2])
        XCTAssertEqual((received as? NSNumber)?.decimalValue, Decimal(string: "0.00005"))
    }

    private func waitForPaid(_ original: O.MintQuote, amount: Int, mint: CashuSwift.Mint) async throws -> O.MintQuote {
        var quote = original
        for _ in 0..<60 {
            quote = try await O.mintQuoteState(quote, from: mint)
            if quote.amountPaid == amount { return quote }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("Expected confirmed quote balance \(amount), received \(quote.amountPaid)")
        throw O.Error.invalidResponse
    }

    private func rpc(_ method: String, _ params: [Any] = []) async throws -> Any {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:19443"))
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Basic " + Data("regtest:regtest".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              json["error"] == nil || json["error"] is NSNull else {
            XCTFail("Regtest RPC \(method) failed: \(json["error"] ?? "HTTP error")")
            throw O.Error.invalidResponse
        }
        return try XCTUnwrap(json["result"])
    }
}
