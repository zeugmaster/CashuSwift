//
//  UnitTests.swift
//  CashuSwiftTests
//
//  Pure unit tests — no network. Tests cryptographic primitives, serialization,
//  split logic, deterministic-secret derivation, and other behaviour that
//  doesn't require a live mint.
//

import XCTest
@testable import CashuSwift
import BIP39
import SwiftCBOR
import secp256k1
import CryptoKit

final class UnitTests: XCTestCase {

    func testInvoiceAmount() throws {
        let invoice = "lnbc1u1p5tzakfpp5rmx3hpalue6tuwgsnkke8qf56eqv0v80p9d8n07r7xnt5pzyr8wqdqggdshx6r4cqzpuxqrwzqsp5u9nx53qsrd4kldd7j0j0flffz0fgsm62ujs8akdyf3clsyc2sg7q9qxpqysgqwkze9vkrxa3c8y0gfryvr4s2eapludn3tnn80slwtcgsjw8q878qcqpwnh2ftww8ypgj093kkehrqwlkmnma7c5e7n92e7qns2vlpxgp3aacr8"
        XCTAssertEqual(try CashuSwift.Bolt11.satAmount(from: invoice), 100)
        XCTAssertEqual(try CashuSwift.Bolt11.satAmount(from: invoice.uppercased()), 100)
    }

    func testDecodeLightningRequestBolt11() throws {
        let invoice = "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"

        let decoded = try CashuSwift.decodeLightningRequest("lightning:\(invoice)")

        guard case let .bolt11Invoice(bolt11) = decoded else {
            return XCTFail("Expected a BOLT11 invoice")
        }
        XCTAssertEqual(bolt11.amountMillisatoshis, 250_000_000)
        XCTAssertEqual(bolt11.invoiceDescription, "1 cup coffee")
    }

    func testDecodeLightningRequestBolt12Offer() throws {
        let nodeID = Data([0x02] + Array(repeating: 0x11, count: 32))
        let offerBytes = bolt12TLV([
            (8, Data([0x03, 0xe8])),
            (10, Data("coffee".utf8)),
            (22, nodeID)
        ])
        let encoded = encodeBolt12(hrp: "lno", bytes: offerBytes)

        let decoded = try CashuSwift.decodeLightningRequest(encoded)

        guard case let .bolt12Offer(offer) = decoded else {
            return XCTFail("Expected a BOLT12 offer")
        }
        XCTAssertEqual(offer.amount, 1_000)
        XCTAssertEqual(offer.description, "coffee")
        XCTAssertEqual(offer.issuerID, nodeID)
    }

    func testSecretSerialization() throws {
        
        // test that deserialization from string works properly
        let secretString = "[\"P2PK\",{\"nonce\":\"859d4935c4907062a6297cf4e663e2835d90d97ecdd510745d32f6816323a41f\",\"data\":\"0249098aa8b9d2fbec49ff8598feb17b592b986e62319a4fa488a3dc36387157a7\",\"tags\":[[\"sigflag\",\"SIG_INPUTS\"]]}]"
        
        let data = secretString.data(using: .utf8)!
        let spendingCondition = try JSONDecoder().decode(CashuSwift.SpendingCondition.self, from: data)
        
        print(spendingCondition.debugPretty())
        
        print(try spendingCondition.serialize())
    }

    func testH2C() throws {
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000000".bytes)
            let point = try CashuSwift.Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "024cce997d3b518f739663b757deaec95bcd9473c30a14ac2fd04023a739d1a725")
        }
        
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000001".bytes)
            let point = try CashuSwift.Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "022e7158e11c9506f1aa4248bf531298daa7febd6194f003edcd9b93ade6253acf")
        }
        
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000002".bytes)
            let point = try CashuSwift.Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "026cdbe15362df59cd1dd3c9c11de8aedac2106eca69236ecd9fbe117af897be4f")
        }
    }

    func testBlinding() throws {
        
        do {
            // let x = try "d341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6".bytes
            let r = try CashuSwift.Crypto.PrivateKey(dataRepresentation: "0000000000000000000000000000000000000000000000000000000000000001".bytes)
            let Y = try CashuSwift.Crypto.secureHashToCurve(message: "test_message")
            let B_ = try Y.combine([r.publicKey])
            XCTAssertEqual(B_.stringRepresentation, "025cc16fe33b953e2ace39653efb3e7a7049711ae1d8a2f7a9108753f1cdea742b")
        }
    }

    func testSigning() throws {
        do {
            let B_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply("0000000000000000000000000000000000000000000000000000000000000001".bytes)
            XCTAssertEqual(C_.stringRepresentation, "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2")
        }
        
        do {
            let B_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".bytes)
            XCTAssertEqual(C_.stringRepresentation, "0398bc70ce8184d27ba89834d19f5199c84443c31131e48d3c1214db24247d005d")
        }
        
        do {
            let k = try "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".bytes
            let B_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply(k)
            XCTAssertEqual(C_.stringRepresentation, "0398bc70ce8184d27ba89834d19f5199c84443c31131e48d3c1214db24247d005d")
        }
    }

    func testDetSec() throws {
        let mnemmonic = try Mnemonic(phrase: "half depart obvious quality work element tank gorilla view sugar picture humble".components(separatedBy: " "))
        let seed = String(bytes: mnemmonic.seed)
        let keysetID = "009a1f293253e41e"
        
        
        let output = try CashuSwift.Crypto.generateOutputs(amounts: [1,1,1,1,1], keysetID: keysetID, deterministicFactors: (seed: seed, counter: 0))
        
        let secretsSet: Set<String> = [
            "485875df74771877439ac06339e284c3acfcd9be7abf3bc20b516faeadfe77ae",
            "8f2b39e8e594a4056eb1e6dbb4b0c38ef13b1b2c751f64f810ec04ee35b77270",
            "bc628c79accd2364fd31511216a0fab62afd4a18ff77a20deded7b858c9860c8",
            "59284fd1650ea9fa17db2b3acf59ecd0f2d52ec3261dd4152785813ff27a33bf",
            "576c23393a8b31cc8da6688d9c9a96394ec74b40fdaf1f693a6bb84284334ea0"
        ]
        
        let blindingFactors: Set<String> = [
            "ad00d431add9c673e843d4c2bf9a778a5f402b985b8da2d5550bf39cda41d679",
            "967d5232515e10b81ff226ecf5a9e2e2aff92d66ebc3edf0987eb56357fd6248",
            "b20f47bb6ae083659f3aa986bfa0435c55c6d93f687d51a01f26862d9b9a4899",
            "fb5fca398eb0b1deb955a2988b5ac77d32956155f1c002a373535211a2dfdc29",
            "5f09bfbfe27c439a597719321e061e2e40aad4a36768bb2bcc3de547c9644bf9"
        ]
        
        XCTAssertEqual(Set(output.secrets), secretsSet)
        XCTAssertEqual(Set(output.blindingFactors), blindingFactors)
    }

    func testBlankOutputCalculation() {
        let overpayed = 1000
        let n = calculateNumberOfBlankOutputs(overpayed)
        XCTAssert(n == 10)
    }

    func testUnblind() throws {
        let C_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: "031c14eed30e32a060030bc9784ed34db7de91ce188ea0cce6f48a84b47ddbd875".bytes, format: .compressed)
        let r = try CashuSwift.Crypto.PrivateKey(dataRepresentation: "c551bd0a48e3a069d8a02dc8b1783923da0d9af015f575c0a521237e10316580".bytes)
        // we only test for the amount 1 and the corresponding mint public key
        let A = try CashuSwift.Crypto.PublicKey(dataRepresentation: "02221e05e446782ba13bb41a8b74ac344a4829cf8417d8e7d32c0152a64755bfae".bytes, format: .compressed)
        
        let proof = try CashuSwift.Crypto.unblind(C_: C_, r: r, A: A)
        
        XCTAssertEqual(proof.stringRepresentation, "0218b90f0de65ae3447624fc8895c31302e61cef56dbca927717cb501cf591ce32")
    }

    func testSafeDeserializationFail() throws {
        
        let tokenV3 = try """
                    cashuAeyJtZW1vIjoiIiwidW5pdCI6InNhdCIsInRva2VuIjpbeyJtaW50IjoiaHR0cHM6XC9cL\
                    21pbnQubWFjYWRhbWlhLmNhc2giLCJwcm9vZnMiOlt7ImFtb3VudCI6OCwiaWQiOiIwMDhiMmRjZ\
                    jIzY2I2ZjJjIiwic2VjcmV0IjoiNDBjMjIzOThjOTY2YjU3NGJiZDQ0MzFlODkzOTE0ZjkyOGY3Z\
                    mY2OWMyNTVhNjE2NjFlNWRjOTcyMGFiYzg3MCIsIkMiOiIwMmI1Y2IwMjY1ZTU0NDkzYWExZGUyO\
                    TVjZjFjNjQyYzJkMmIyNDA3MTk3ZjA1NWE3YWRlNzM4NWYyOTgzZDEwNzAifSx7ImlkIjoiMDA4Yj\
                    JkY2YyM2NiNmYyYyIsInNlY3JldCI6IjhiODdjZTIzNzU0MzhiODU2NDIxYzIxYjhhMzNiMjk0MDE\
                    5YTAzY2I0NzYwNzU3MjVmZmVjZDJiMTc4NDY5NGUiLCJhbW91bnQiOjQsIkMiOiIwMjNlNTEwMjFl\
                    MjRiMGNiMTg2YjRlYWQ4Y2ZmYjBlMTU2MGUyNjAyYTA4MDYxODE0ZTlkYzE5MzA0MjY5ZWI2M2Yif\
                    Sx7ImlkIjoiMDA4YjJkY2YyM2NiNmYyYyIsInNlY3JldCI6IjFlNWU0NGM1MTI5ZWVhMmNiYjc1Mj\
                    ljM2RjNzk2MTA3ODYzMTNjM2QzOGFiOGY2MGUyZTRlNzRkM2JiZTBhYTkiLCJhbW91bnQiOjIsIkM\
                    iOiIwMjZiMTY5MDYxOTcyNjcxMzk1Yjc0ODc4NzgyN2JiYTc2OTg3MjhlYjBlNjk2NzIxNTI2N2M5\
                    ZjM2MTFkYWZjMjQifSx7InNlY3JldCI6IjE1OTBlYmNlMTAxZWVmN2YzMzRlNThhZTAwNDYyZTY0N\
                    jA2ZWQ1NzY0ZmFkOGQwZmJkYmU0NzJlZGE5ZjE0MjYiLCJpZCI6IjAwOGIyZGNmMjNjYjZmMmMiLC\
                    JhbW91bnQiOjEsIkMiOiIwMjE1YzFlYWY0YzBhN2ViNzIyOGMxZWNjM2MzNzMzYTQ1Yjk3ZGJlZmY\
                    5ZTliOGIzNDExMzljYmRhNmM3YjliYjMifV19XX0=
                    """.deserializeToken()

        let tokenV4 = try """
                    cashuBo2FteBtodHRwczovL3Rlc3RudXQuY2FzaHUuc3BhY2VhdWNzYXRhdIGiYWlIAJofKTJT5B5hc\
                    IOjYWEQYXN4QGYxZGI3ZTQ3YjAzYmY1YTE3NjRjYjBkZmU0OGNhZGYxZjMxN2ZiMWUxOTJmZTc5MTQ1\
                    ZWUyNzQyZjZjMzE5NTlhY1ghA5wwM6EZSyElJ2Gb4nPM0XLWDewGLwLOfdIMqvQMFhKEo2FhBGFzeEB\
                    jOWE0ZmE0ZWQ5YTVlMmJiY2RjMGViNDJhNjkwZTk5YmVkYTM4ODU4ZmU0NzJhNjY0YjlmMjY4YjZhND\
                    YzNWJjYWNYIQKAloVdh0Zf6Lm-mTWvtAXKwEUvEi5OKody4OglWEWrv6NhYQFhc3hAYWIyNjU5MTdmM\
                    DdjODk1ZTVkMjg3ODViNzcwNTRmMjgxYWQyYTViZjMyMzgxYTYwYjE4MDAyNDM4YTVkMzE1MGFjWCEC\
                    JMe6T-xGSiYctU_igSY3prkJe065rrj7CxrLvnJASlY
                    """.deserializeToken()
        
        
        _ = try tokenV4.serialize(to: .V3)
        _ = try tokenV3.serialize(to: .V4)
        
    }

    func testTokenV4Decoding() throws {
        let reverse = "cashuBo2FteBtodHRwczovL3Rlc3RudXQuY2FzaHUuc3BhY2VhdWNzYXRhdIGiYWlIAJofKTJT5B5hcIOjYWEBYXN4QGE0Y2ZlMDM0NjEwYTMzNjk0NTcyNGQ4YjBkYjI4MWI5OGU0ODcwYTQ4MjRkYTA1ZmJhMGMxYzFmMjllNzUzNDFhY1ghAmK6bNpHFRHv4zSvY2Ro8atT7E75W2xhIwKx8fU99sfTo2FhBGFzeEA4MTZjMzQ0NjhmNjQ4ZDJlZmUyOWIwMTA5YjQxZjYzYzQ1OTQ5Y2YwYTE4YWQ5NjAwNmI3ZmIzNjU4OTViZDFmYWNYIQPGS7r49FNNltGz4oKaV198KWbdShHGy58X-apdipr6XqNhYRBhc3hAYWMxZDg0ZTFhNmY5MTNhMjg2ZjI4NjNhZmY3NDA4NWVkMjI5YjI0MzkwNWFkOTdkYjVmNTIzODE5MmIzYjE4MGFjWCED6vxDZwReE7zZ_Wj6DeBBZQhlCWESMWZu3J2EZ5m16no"
        
        print(try reverse.deserializeToken())
        
        // this token contains a non hex keyset id and should not be possible to serialize to V4
        let v3 = "cashuAeyJ1bml0Ijoic2F0IiwidG9rZW4iOlt7Im1pbnQiOiJodHRwczpcL1wvODMzMy5zcGFjZTozMzM4IiwicHJvb2ZzIjpbeyJDIjoiMDM0MDUyNTg3Yjc0NzkxZWQyOTk2NDU5MGM3ZDBmM2ExZmRkOTAyOTI4MDBiNGI0MDJkMjY3NzRjZTljMjYzYjEwIiwiaWQiOiJJMnlOK2lSWWZrelQiLCJhbW91bnQiOjQsInNlY3JldCI6IjNjMTc3OThlMmRmMmQ0Y2E1MmQwODNjZWRiMDhmNjYwZGViYWU2NDk0Y2Y1ZWVkNDZhNzU1NWFkNWFiNDUyNGYifSx7ImlkIjoiSTJ5TitpUllma3pUIiwiQyI6IjAzZjBlNjQ3YWI0NzdhOTY4YzMwMTAxY2ZjMWJhY2VmNzQ5YmNmNjliY2MyN2Y5NGQzZTYzNzE3OWE3ZmY4NWE1YSIsInNlY3JldCI6IjYxY2NmN2M2Mjg0YzA1ODMxNzdlN2I5ZDAwN2ExY2U5Yzg1NDJlMWY4N2YxMGVhZmUzMGE5ZmM5ZWZiNzUwZWQiLCJhbW91bnQiOjJ9LHsiYW1vdW50Ijo0LCJDIjoiMDNmMzYwNDhjMmFjOWUzNjgyZWE2MDEwMGViNTVkN2I3Yzk5OWZhMjMzNjI5YjcyYWNiOGI3YjExNzk4OGFiZTMyIiwic2VjcmV0IjoiMTc1MmJjYTU3ZmJjMGI3MmVjN2U1MWI0ODMwNGYxZDU4NjI2NmY3OTNmNjIzY2YzYWUwNDNiZGY5NDljM2JmNCIsImlkIjoiSTJ5TitpUllma3pUIn1dfV0sIm1lbW8iOiJBbWVyaWNhbiBDcmFzaGl0byJ9"
        let token = try v3.deserializeToken()
        XCTAssertThrowsError(try token.serialize(to: .V4)) { error in
            if let specificError = error as? CashuError {
                XCTAssertEqual(specificError, .tokenEncoding(""))
            } else {
                XCTFail("error type mismatch")
            }
        }
    }

    func testCreateRandomPubkey() {
        let priv = try! secp256k1.Signing.PrivateKey()
        print(String(bytes: priv.publicKey.dataRepresentation))
    }

    func testDLEQverification() throws {
        
        let A = try secp256k1.Signing.PublicKey(dataRepresentation: "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798".bytes, format: .compressed)
        
        do {
            let B_ = try secp256k1.Signing.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try secp256k1.Signing.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let e = try Data("9818e061ee51d5c8edc3342369a554998ff7b4381c8652d724cdf46429be73d9".bytes)
            let s = try Data("9818e061ee51d5c8edc3342369a554998ff7b4381c8652d724cdf46429be73da".bytes)
            
            let result = try CashuSwift.Crypto.verifyDLEQ(A: A, B_: B_, C_: C_, e: e, s: s)
            
            XCTAssertTrue(result)
        }
        
        do {
            let C = try secp256k1.Signing.PublicKey(dataRepresentation: "024369d2d22a80ecf78f3937da9d5f30c1b9f74f0c32684d583cca0fa6a61cdcfc".bytes, format: .compressed)
            let x = "daf4dd00a2b68a0858a80450f52c8a7d2ccf87d375e43e216e0c571f089f63e9"
            let r = try Data("a6d13fcd7a18442e6076f5e1e7c887ad5de40a019824bdfa9fe740d302e8d861".bytes)
            let e = try Data("b31e58ac6527f34975ffab13e70a48b6d2b0d35abc4b03f0151f09ee1a9763d4".bytes)
            let s = try Data("8fbae004c59e754d71df67e392b6ae4e29293113ddc2ec86592a0431d16306d8".bytes)
            
            let result = try CashuSwift.Crypto.verifyDLEQ(A: A, C: C, x: x, e: e, s: s, r: r)
            
            XCTAssertTrue(result)
        }
    }

    func testHashConcat() throws {
        let k = try secp256k1.Signing.PublicKey(dataRepresentation: "020000000000000000000000000000000000000000000000000000000000000001".bytes, format: .compressed)
        let C_ = try secp256k1.Signing.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
        
        let hash = CashuSwift.Crypto.hashConcat([k, k, k, C_])
        
        XCTAssertEqual(String(bytes: hash), "a4dc034b74338c28c6bc3ea49731f2a24440fc7c4affc08b31a93fc9fbe6401e")
        
        print(String(bytes: hash))
    }

    func testTokenDeserializationWithDLEQ() throws {
        let token = try "cashuBo2FteBtodHRwczovL3Rlc3RudXQuY2FzaHUuc3BhY2VhdWNzYXRhdIGiYWlIAJofKTJT5B5hcIGkYWEBYXN4QDcyMGVhMjcwYTQ4NDk0YThhNzMwM2E2YjczZTk5NDM1MTU1ZGFjMzFmYjIyYjg5YjllZjFmZGFlMzNjNmIzODVhY1ghAh9iiqwq9POuxIxSW8APMCT3Mw9d5bQv0uTZvUQow9V5YWSjYWVYIGMAHPJTvIcRDgIYcks-1CgWGCipn8QPxmrBvQRxA-RaYXNYICF1NnjVfZDs30T0TXUIORPbaNKkbYUI8vhUPJCxwCy6YXJYIE7keXw6yoxTzpgT_qGKJvWVrDP4NcCPAMlSMPY37LpO".deserializeToken()
        print(token.debugPretty())
    }

    func testSchnorrPubkey() throws {
        let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
        let pubkeyHex = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"
        
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyHex.bytes)
        XCTAssertEqual(String(bytes: privateKey.publicKey.dataRepresentation), pubkeyHex)
    }

    func testSplit() throws {
        print(try CashuSwift.split(for: 100, target: 50, fee: 2))
        print(try CashuSwift.split(for: 100, target: nil, fee: 2))
//        print(try CashuSwift.split(for: 50, target: 50, fee: 2))
        print(try CashuSwift.split(for: 100, target: 70, fee: 3))
        print(try CashuSwift.split(for: 10, target: 0, fee: 2))
        
        print(try CashuSwift.split(for: 100, target: 70, fee: 0))
        print(try CashuSwift.split(for: 10, target: 0, fee: 0))
        print(try CashuSwift.split(for: 100, target: nil, fee: 0))
        
    }

    func testKDFerrorBIP32() throws {
        let path = "m/129372'/0'/1536791888'/36'/0"
        let seed = "5f911180b9d710a730a277a651d1bc347eef5546953fe99470ebdde467c54ae0d264ca3ee2d75f19a248c391ce7495c313cc0302c6b8bfff6d921c6dab282bda"
        
        let key = try CashuSwift.Crypto.childPrivateKeyForDerivationPath(seed: seed,
                                                                         derivationPath: path)
        
        print(String(bytes: key.dataRepresentation))
        print(key.dataRepresentation.count)
    }

    func testP2PKLockFlag() throws {
        do {
            let tokenString = "cashuBo2FteCJodHRwczovL21pbnQubWluaWJpdHMuY2FzaC9CaXRjb2luYXVjc2F0YXSBomFpSABQBVDwSUFGYXCDpGFhAWFzeKtbIlAyUEsiLHsibm9uY2UiOiIxNTYzYjAxNWFhMWExMGY5MjA2ODhkZjQ5MmU4NGEzMTU5YmNmYjNiZWQ3NGI5YTVmNzA5ZDg4NWU1Yzk3ODZkIiwiZGF0YSI6IjAyNmE5NDZmZTkwMTE4ZjNmZGRkMzY5Mjg4MjNiOWU4YTI4NzVhYTQwOTI3Nzk4ZTBjN2I0MjUwOGMzNGQ2YzE1YiIsInRhZ3MiOltdfV1hY1ghAw365nOqGOfDub_8AUYm1QJu8LWln66ruDtSLtp4xFj8YWSjYWVYID8BMGYMwhScw0EQvjA2yYSITheMVfS77n7MNrPvmyR8YXNYIE9nh8ywBmJRXaS_vb-dpEIKhwDyOoHfopaWIjmsQhxPYXJYIFbjBm-ad11LiyAXkUfkX8QfuTeRAiSsdZDhEwEhuw2apGFhBGFzeKtbIlAyUEsiLHsibm9uY2UiOiJlNGRiODQ1MWE1Y2U5NWRkZmZhYTRkMzE1NDQyNjM2OTM4OTZlZTAyYTlkMzI5OGU1NzhkZGU2ZThlNzc2YTI2IiwiZGF0YSI6IjAyNmE5NDZmZTkwMTE4ZjNmZGRkMzY5Mjg4MjNiOWU4YTI4NzVhYTQwOTI3Nzk4ZTBjN2I0MjUwOGMzNGQ2YzE1YiIsInRhZ3MiOltdfV1hY1ghAn8_CnK10PuYisnbg9gONTtcPRBF14jDw6RusrUvRhPQYWSjYWVYIFpM8r8WT_ars_9-wFR5TmNwtGnFvW_X_1BIpmJQ9PosYXNYIBDX9fChYt0FlOaJcOYsRzgop5XJq-oWO8BW9c_gXKXQYXJYIAOq8DjkHe31RD0S3R_rzz-DvtfIiCp_app2fMJAsTr0pGFhEGFzeKtbIlAyUEsiLHsibm9uY2UiOiI0ZGVlOGNjMTU1ZjZlNGMwYjcxZGJhMDNlYTJlNjBiNWNhZTkyZDA2OTg1YTIxOGE2NzMwOWQyNzI4NDk3MDZkIiwiZGF0YSI6IjAyNmE5NDZmZTkwMTE4ZjNmZGRkMzY5Mjg4MjNiOWU4YTI4NzVhYTQwOTI3Nzk4ZTBjN2I0MjUwOGMzNGQ2YzE1YiIsInRhZ3MiOltdfV1hY1ghAw4xsGxfzAI7ruO0bCbJzSm4kwGZ3plkVr0zXmVrVt8oYWSjYWVYIPxnfAG8rkWdI0Tj47uTED5_EWmafo7h0gexeJ698iWdYXNYIMZ6vK5DowOAz7ZTtd-7idu_-vTIRff39gdlEoFTsGJXYXJYIEp4MQADP75qAKnuelp2tz9xrxv8Q0Ut5k9XBFe6hcR9"
            
            let decoded = try tokenString.deserializeToken()
            
            XCTAssert(decoded.isP2PKLocked)
        }
        
        do {
            let tokenString = "cashuBo2FteCJodHRwczovL21pbnQubWluaWJpdHMuY2FzaC9CaXRjb2luYXVjc2F0YXSBomFpSABQBVDwSUFGYXCHpGFhEGFzeEAwOTRjNzY5ZDNkYjNkMmVhYWUzZTBhNWZkOWU3NjA2MDg4NjFjYTNmZTE0NmExM2VkNjQ5MTU1OTAzNGY5Y2U4YWNYIQOkEcJFJjFtwBL8i7igvQJSaZ4_fBdbdMo-Tml98TonqGFko2FlWCAKzWNTxVwFidtVnpCKZZnXUUVOQm56pEbwEbByahB7_WFzWCC5rMVIuF4qpV8al9BssEG2GoeFI27RzGX9M2lHX47OzWFyWCBYRtsevUFJr1zUeqhT1bWQ-Edd5HZtK2p9mLf-ftq6r6RhYQhhc3hAZDgzOGE2OGIyZmFkMTkyMzQyYTQ1M2ZiYTI2YWQyZDhhMzQ3ZjBkZTcwZjkxMGEyY2NhYWY1NzhlNjI3ODEyOWFjWCEDqTFZ86z-CKOVckBduJWnO_02SciW6p4La-R59lXXxLZhZKNhZVggSnZGAJpF5TLPB4HMGRQkr8ifMa1SN463RMCkZHDaXBthc1ggjQ9nfiiOqMa8pSs5TRLKFydXur0-YX6kWqARU98XFthhclgg6u2DTWt2M-PBRpKW-TXAUz7cnoEMXApxhsSk2L6tNpykYWEIYXN4QDgwNDk5YmYxM2RjYjViMmZkNDhiYjljYmQwY2VjMjk3ZGNiY2IwN2Q4YmE5YWY3YTA3NDZlODg0ZTFkN2U2YTNhY1ghAwX7tPjL5U07Sxv0awnazUynhZ3jDG6f7w09SekLxtv8YWSjYWVYICZyoK-J18Rb_ZFxc1H4xQwoqRzgdke663gPs9UtFCexYXNYIG9rD1q44ZlUpl3RA4Lgr-pDnIUuz5N77-71Rv3E8LFNYXJYIAJOwAUB52HNDzOz1trrQ9bEiO7eqxXLQMWDIbtelvIKpGFhBGFzeEA3YmU3YWRhZmEwMTZlNmIwZGE4YWVmMDk3MWRlZGVhNjVhMDU1YjA4ZGQzMTQ5NmExYWIwNWY1NTZjNTY3MzJjYWNYIQMACvfo9ER55AG9FgTYanqlhS_wcWS5ixt1i5v7DYxVYGFko2FlWCBHJV_43ehQK9ZisYU7FEAowJKuWIyj-G3Pj4GLuxWj02FzWCBsiF7BjVmH1EljPWT-HEZMoREp0_FwUYh1oS3GZMPzMGFyWCBhbp3UJ7uj_I7RSYJlYKFSAfEytN2xNPAdrudWoKPfQ6RhYQJhc3hANDI4YTFiOGE2MzFkZTNlYzdlODQ2OWRmYmZmZDdmNmVmMWE2ZDA2NTE5ZDdjMGMzY2NjZGQzNTc0NjY5NjczOWFjWCECccXN7E-Kz8R5Y9yGtTNP-89IAMljeP2bA-MdSC35uNFhZKNhZVggQz1VqguMxFUfok_9_AWjqa6eoji4sYrf4XRe91U9pvphc1gg-w9BExJBY_ugkE3KOSwP--jyaBQxd8rCSKbC1pN0CmFhclggWDJKewPS2FvVVmitD_x7GSYls5Kv-vhEaNrG0buYxaakYWECYXN4QDZmMDAyNmRiZjZmZDFhNTNhMTNiZDJmZWE3YmYyMTc1Y2IzYmM1ODg0NTY5ZDVhZjA4ODRmMGY3OWM2ODQ3ZjFhY1ghAlJxpEDm0GksC-E6-ci9FxBoaXtT4QLbhvfKb_ZO-WNiYWSjYWVYIF_yro1m3v4VZQQh4LP-8kSuDD0ouBzt8qYuuavwTXMtYXNYIOPEbgWTBiqRawrNDv7xvcPxUvoPPUTNcYnL2jVFp-LuYXJYIBJWonsvYqOht2OheMhMaXk240HJP1LnELtYK8KqaNyfpGFhAmFzeEAwMDg5NzNjZjFjODM1YmNiNWRiYmM5Y2UyY2FlZmNlZTdhNDlkMjg4MzhkMGNkYTAxNjQ3N2Y1NTQ2ZDM3MzUzYWNYIQIfEBfu_O0rPEuii4jH2j54WCYlLOAKlOpzreojxVAlKWFko2FlWCCpT6C8oBhjxYwBBo0HLufmMo9_DE30b5bhZlDAzBeIVmFzWCCr7DaJn93W3l6G2kyjkosmKHof77VR06BiIP91arSaAGFyWCBVyVeNA05XjhJpGsYMltrhYH2TPOZdfSBJNrMrkgr0vA"
            
            let decoded = try tokenString.deserializeToken()
            
            XCTAssert(!decoded.isP2PKLocked)
        }
    }

    func testKeysetV2idCalculation() throws {
        // Test with official NUT-02 test vector 1
        let keys = [
            "1": "03a40f20667ed53513075dc51e715ff2046cad64eb68960632269ba7f0210e38bc",
            "2": "03fd4ce5a16b65576145949e6f99f445f8249fee17c606b688b504a849cdc452de",
            "4": "02648eccfa4c026960966276fa5a4cae46ce0fd432211a4f449bf84f13aa5f8303",
            "8": "02fdfd6796bfeac490cbee12f778f867f0a2c68f6508d17c649759ea0dc3547528"
          ]
        let unit = "sat"
        let inputFeePPK = 100
        let finalExpiry = 2059210353
        
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv2(keyset: keys,
                                                              unit: unit,
                                                              inputFeePPK: inputFeePPK,
                                                              finalExpiry: finalExpiry)
        
        // Expected from official test vector 1
        XCTAssertEqual(id, "015ba18a8adcd02e715a58358eb618da4a4b3791151a4bee5e968bb88406ccf76a")
    }

    func testV1deterministicSecretDerivation() throws {
        
        let mnemonic = try Mnemonic(phrase: "half depart obvious quality work element tank gorilla view sugar picture humble".components(separatedBy: " "))
        let seed = mnemonic.seed
        
        let keysetID = "012e23479a0029432eaad0d2040c09be53bab592d5cbf1d55e0dd26c9495951b30"
        
        let outputs = try  CashuSwift.Crypto.generateOutputs(amounts: [1,1,1,1,1],
                                                             keysetID: keysetID,
                                                             deterministicFactors: (String(bytes: seed), 0))
        
        let expectedSecrets = [
            "ba250bf927b1df5dd0a07c543be783a4349a7f99904acd3406548402d3484118",
            "3a6423fe56abd5e74ec9d22a91ee110cd2ce45a7039901439d62e5534d3438c1",
            "843484a75b78850096fac5b513e62854f11d57491cf775a6fd2edf4e583ae8c0",
            "3600608d5cf8197374f060cfbcff134d2cd1fb57eea68cbcf2fa6917c58911b6",
            "717fce9cc6f9ea060d20dd4e0230af4d63f3894cc49dd062fd99d033ea1ac1dd"
        ]
        
        let expBF = [
            "4f8b32a54aed811b692a665ed296b4c1fc2f37a8be4006379e95063a76693745",
            "c4b8412ee644067007423480c9e556385b71ffdff0f340bc16a95c0534fe0e01",
            "ceff40983441c40acaf77d2a8ddffd5c1c84391fb9fd0dc4607c186daab1c829",
            "41ad26b840fb62d29b2318a82f1d9cd40dc0f1e58183cc57562f360a32fdfad6",
            "fb986a9c76758593b0e2d1a5172ade977c858d87111a220e16c292a9347abf81"
          ]
        
        XCTAssertEqual(expectedSecrets, outputs.secrets)
        XCTAssertEqual(expBF, outputs.blindingFactors)
    }

    private func bolt12TLV(_ records: [(UInt64, Data)]) -> Data {
        var result = Data()
        for (type, value) in records {
            result.append(bigSize(type))
            result.append(bigSize(UInt64(value.count)))
            result.append(value)
        }
        return result
    }

    private func bigSize(_ value: UInt64) -> Data {
        if value < 0xfd {
            return Data([UInt8(value)])
        }
        if value <= 0xffff {
            return Data([0xfd, UInt8(value >> 8), UInt8(value)])
        }
        if value <= 0xffff_ffff {
            return Data([0xfe, UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)])
        }
        return Data([
            0xff,
            UInt8(value >> 56),
            UInt8(value >> 48),
            UInt8(value >> 40),
            UInt8(value >> 32),
            UInt8(value >> 24),
            UInt8(value >> 16),
            UInt8(value >> 8),
            UInt8(value)
        ])
    }

    private func encodeBolt12(hrp: String, bytes: Data) -> String {
        let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let words = convertBits(data: Array(bytes), fromBits: 8, toBits: 5, pad: true)
        return hrp + "1" + String(words.map { charset[Int($0)] })
    }

    private func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8] {
        var accumulator: UInt32 = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = UInt32((1 << toBits) - 1)

        for value in data {
            accumulator = (accumulator << fromBits) | UInt32(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
        }

        if pad, bits > 0 {
            result.append(UInt8((accumulator << (toBits - bits)) & maxValue))
        }

        return result
    }

}
