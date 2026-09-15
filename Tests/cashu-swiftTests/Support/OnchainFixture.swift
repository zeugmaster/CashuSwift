import Foundation
import CryptoKit
import XCTest
import secp256k1
@testable import CashuSwift

// Wire baseline: cashubtc/nuts f364a04162febbb8e860a3f121cd32d3d472cb44 (NUT-30).
// Reference models: cashubtc/cdk 0739929298838708b03430c7d7dd5c52c31fc664.
// Normative fields are required even when an illustrative spec example omits them.
enum OnchainFixture {
    typealias O = CashuSwift.Onchain
    static let seed = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
    static let address = "bcrt1qtestaddressforonchainfixtures"
    static let point = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    static let outpoint = String(repeating: "ab", count: 32) + ":0"

    static func info(disabled: Bool = false, confirmations: Any = 1) throws -> CashuSwift.Mint.Info {
        let methods: [[String: Any]] = [["method": "onchain", "unit": "sat", "min_amount": 1,
                                        "max_amount": 1_000_000, "options": ["confirmations": confirmations, "future": true]]]
        return try decode(["name": "Local test mint", "nuts": [
            "4": ["methods": methods, "disabled": disabled], "5": ["methods": methods, "disabled": disabled]
        ]])
    }

    static func mint(url: URL, feePPK: Int = 0, counter: Int = 7) throws -> CashuSwift.Mint {
        let keys = Dictionary(uniqueKeysWithValues: (0...20).map { (String(1 << $0), point) })
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv2(keyset: keys, unit: "sat", inputFeePPK: feePPK, finalExpiry: nil)
        let keyset: CashuSwift.Keyset = try decode(["id": id, "unit": "sat", "active": true, "keys": keys,
                                                  "input_fee_ppk": feePPK, "derivationCounter": counter])
        return CashuSwift.Mint(url: url, keysets: [keyset])
    }

    static func mintQuote(paid: Int = 12, issued: Int = 0, updated: Int = 100, id: String = "mint-1") throws -> O.MintQuote {
        try O.MintQuote(quote: id, request: address, unit: "sat", expiry: nil,
                        pubkey: O.quoteLockingKey(seed: seed, counter: 0).publicKey,
                        amountPaid: paid, amountIssued: issued, updatedAt: updated)
    }

    static func fees(reserve: Int = 4) throws -> [O.FeeOption] {
        try [.init(feeIndex: 7, feeReserve: reserve, estimatedBlocks: 6),
             .init(feeIndex: 2, feeReserve: reserve + 4, estimatedBlocks: 1)]
    }

    static func meltQuote(state: CashuSwift.QuoteState = .unpaid, selected: Int? = nil,
                          amount: Int = 8, reserve: Int = 4, expiry: Int = 4_000_000_000,
                          outpoint: String? = nil, change: [CashuSwift.Promise]? = nil) throws -> O.MeltQuote {
        try .init(quote: "melt-1", request: address, amount: amount, unit: "sat", state: state,
                  expiry: expiry, feeOptions: fees(reserve: reserve), selectedFeeIndex: selected,
                  outpoint: outpoint, change: change)
    }

    static func proofs(_ amounts: [Int], mint: CashuSwift.Mint) throws -> [CashuSwift.Proof] {
        let id = try XCTUnwrap(mint.keysets.first).keysetID
        return amounts.enumerated().map { i, amount in
            .init(keysetID: id, amount: amount, secret: "test-proof-\(i)", C: point)
        }
    }

    /// Test mint with private key 1. Generate DLEQ with an independent challenge encoding.
    static func promises(_ outputs: [CashuSwift.Output], amounts: [Int]? = nil) throws -> [CashuSwift.Promise] {
        try outputs.enumerated().map { i, output in
            let nonce = try secp256k1.Signing.PrivateKey(dataRepresentation: [UInt8](repeating: 0, count: 31) + [42])
            let b = try secp256k1.Signing.PublicKey(dataRepresentation: output.B_.bytes, format: .compressed)
            let a = try secp256k1.Signing.PublicKey(dataRepresentation: point.bytes, format: .compressed)
            let r2 = try b.multiply(nonce.dataRepresentation.bytes)
            let challengeText = [nonce.publicKey, r2, a, b].map {
                $0.uncompressedRepresentation.map { String(format: "%02x", $0) }.joined()
            }.joined()
            let e = Data(SHA256.hash(data: Data(challengeText.utf8)))
            let s = try nonce.add(Array(e))
            return .init(id: output.id, amount: amounts?[i] ?? output.amount, C_: output.B_,
                         dleq: .init(e: String(bytes: e), s: String(bytes: s.dataRepresentation), r: nil))
        }
    }

    static func decode<T: Decodable>(_ object: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}

func assertOnchainError<E: Swift.Error & Equatable>(_ expected: E, file: StaticString = #filePath, line: UInt = #line,
                                                   operation: () async throws -> Void) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch { XCTAssertEqual(error as? E, expected, file: file, line: line) }
}
