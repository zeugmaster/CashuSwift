import Foundation
import SwiftBLST
import secp256k1
@testable import CashuSwift

/// Local BLS mint with independent denomination keys; no external funds or network.
enum V3Fixture {
    static let seed = String(repeating: "42", count: 64)

    static func scalar(_ amount: Int) throws -> BLST.Scalar {
        try BLST.Scalar(bytes: [UInt8](repeating: 0, count: 31) + [UInt8(amount + 1)])
    }

    static func mint(url: URL, counter: Int = 7) throws -> CashuSwift.Mint {
        let keys = try Dictionary(uniqueKeysWithValues: [1, 2, 4, 8, 16, 32].map {
            (String($0), String(bytes: try scalar($0).publicKeyG2().compressedBytes))
        })
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv3(keyset: keys, unit: "sat", inputFeePPK: 0)
        let keyset: CashuSwift.Keyset = try OnchainFixture.decode([
            "id": id, "unit": "sat", "active": true, "keys": keys, "derivationCounter": counter
        ])
        return CashuSwift.Mint(url: url, keysets: [keyset])
    }

    static func promises(_ outputs: [CashuSwift.Output], amounts: [Int]? = nil) throws -> [CashuSwift.Promise] {
        try outputs.enumerated().map { i, output in
            let amount = amounts?[i] ?? output.amount
            let signed = try CashuSwift.Crypto.BLS.g1Point(fromHex: output.B_).multiplied(by: scalar(amount))
            return .init(id: output.id, amount: amount, C_: String(bytes: signed.compressedBytes), dleq: nil)
        }
    }

    static func proofs(_ amounts: [Int], mint: CashuSwift.Mint) throws -> [CashuSwift.Proof] {
        let keyset = mint.keysets[0]
        let output = try CashuSwift.Crypto.generateOutputs(amounts: amounts, keysetID: keyset.keysetID)
        return try CashuSwift.Crypto.unblindPromises(promises(output.outputs), blindingFactors: output.blindingFactors,
                                                     secrets: output.secrets, keyset: keyset)
    }
}
