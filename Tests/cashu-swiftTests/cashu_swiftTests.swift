import XCTest
@testable import cashu_swift
import secp256k1
import BIP39

final class cashu_swiftTests: XCTestCase {
    
    func testEncoding() throws {
        
        let proof1 = Proof(id: "009a1f293253e41e",
                           amount: 2,
                           secret: "407915bc212be61a77e3e6d2aeb4c727980bda51cd06a6afc29e2861768a7837",
                           C: "02bc9097997d81afb2cc7346b5e4345a9346bd2a506eb7958598a72f0cf85163ea")
        let proof2 = Proof(id: proof1.id,
                           amount: 8,
                           secret: "fe15109314e61d7756b0f8ee0f23a624acaa3f4e042f61433c728c7057b931be",
                           C: "029e8e5050b890a7d6c0968db16bc1d5d5fa040ea1de284f6ec69d61299f671059")
        
        let proofContainer = ProofContainer(mint: "https://8333.space:8333",
                                            proofs: [proof1, proof2])
        
        let token = Token(token: [proofContainer], memo: "Thank you.", version: .V3, unit: "sat")
        
        print(token.prettyJSON())
        
        let testToken = try token.serialize()
        
        XCTAssertEqual(token, try testToken.deserializeToken())
    }
    
    func testSecretSerialization() throws {
        
        // test that deserialization from string works properly
        let secretString = "[\"P2PK\",{\"nonce\":\"859d4935c4907062a6297cf4e663e2835d90d97ecdd510745d32f6816323a41f\",\"data\":\"0249098aa8b9d2fbec49ff8598feb17b592b986e62319a4fa488a3dc36387157a7\",\"tags\":[[\"sigflag\",\"SIG_INPUTS\"]]}]"
        
        let tag = SpendingCondition.Tag.sigflag(values: ["SIG_INPUTS"])
        let sc = SpendingCondition(nonce: "859d4935c4907062a6297cf4e663e2835d90d97ecdd510745d32f6816323a41f",
                                   data: "0249098aa8b9d2fbec49ff8598feb17b592b986e62319a4fa488a3dc36387157a7",
                                   tags: [tag])
        
        let secret = Secret.P2PK(sc: sc)
        XCTAssertEqual(try Secret.deserialize(string: secretString), secret)
        
        // test that objects can properly be compared using `Equatable` protocol
        let secret1:Secret
        let secret2:Secret
        
        do {
            let tag1 = SpendingCondition.Tag.pubkeys(values: ["1XXXXXXXXX", "2XXXXXXXXX"])
            let tag2 = SpendingCondition.Tag.locktime(values: [10, 100, 1000])
            let sc = SpendingCondition(nonce: "nonce", data: "data", tags: [tag1, tag2])
            secret1 = Secret.P2PK(sc: sc)
        }
        do {
            let tag1 = SpendingCondition.Tag.pubkeys(values: ["1XXXXXXXXX", "2XXXXXXXXX"])
            let tag2 = SpendingCondition.Tag.locktime(values: [10, 100, 1000])
            let sc = SpendingCondition(nonce: "nonce", data: "data", tags: [tag2, tag1])
            secret2 = Secret.P2PK(sc: sc)
        }
        XCTAssertEqual(secret1, secret2)
    }
    
    func testNetworkManager() async throws {
        do {
            let mintQuoteRequest = Bolt11.RequestMintQuote(unit: "sat", amount: 21)
            let url = URL(string: "https://testnut.cashu.space/v1/mint/quote/bolt11")!
            let quote = try await Network.post(url: url,
                                               body: mintQuoteRequest,
                                               expected: Bolt11.MintQuote.self)
            print(quote)
        } catch let error as Network.Error {
            switch error {
            case .decoding(let data):
                print("Network.Error.decoding:")
                print(String(data: data, encoding: .utf8) ?? "could not ")
            case .encoding:
                print("there was an error encoding the data")
            default:
                print(error)
                throw error
            }
        }
    }
    
    func testMintCheckReachable() async throws {
        let mintUrl = URL(string: "https://mint.macadamia.cash")!
        
        let mintInfo = try await Network.get(url: mintUrl.appending(path: "/v1/info"), expected: MintInfo.self)
        
        let keysetList = try await Network.get(url: mintUrl.appending(path: "/v1/keys"), expected: KeysetList.self)
        let keysetStateList = try await Network.get(url: mintUrl.appending(path: "/v1/keysets"), expected: KeysetList.self)
        
        let combined = keysetList.keysets.map { keyset in
            var updated = keyset
            updated.active = keysetStateList.keysets.first(where: { $0.id == keyset.id })!.active
            return updated
        }
        
        let mint = Mint(url: mintUrl,
                        allKeysets: combined,
                        info: mintInfo,
                        nickname: "Macadamia Mint")
        
        let reachable = await mint.isReachable()
        
        // check that the mint's keysets contain at least one active one (required)
        let oneKeysetActive = combined.contains { $0.active == true }
        
        XCTAssert(reachable)
        XCTAssert(oneKeysetActive)
        
    }
    
    func testH2C() throws {
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000000".bytes)
            let point = try Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "024cce997d3b518f739663b757deaec95bcd9473c30a14ac2fd04023a739d1a725")
        }
        
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000001".bytes)
            let point = try Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "022e7158e11c9506f1aa4248bf531298daa7febd6194f003edcd9b93ade6253acf")
        }
        
        do {
            let data = Data(try "0000000000000000000000000000000000000000000000000000000000000002".bytes)
            let point = try Crypto.secureHashToCurve(message: String(data: data, encoding: .utf8)!)
            XCTAssertEqual(point.stringRepresentation, "026cdbe15362df59cd1dd3c9c11de8aedac2106eca69236ecd9fbe117af897be4f")
        }
    }
    
    func testBlinding() throws {
        
        do {
            // let x = try "d341ee4871f1f889041e63cf0d3823c713eea6aff01e80f1719f08f9e5be98f6".bytes
            let r = try Crypto.PrivateKey(dataRepresentation: "0000000000000000000000000000000000000000000000000000000000000001".bytes)
            let Y = try Crypto.secureHashToCurve(message: "test_message")
            let B_ = try Y.combine([r.publicKey])
            XCTAssertEqual(B_.stringRepresentation, "025cc16fe33b953e2ace39653efb3e7a7049711ae1d8a2f7a9108753f1cdea742b")
        }
    }
    
    func testSigning() throws {
        do {
            let B_ = try Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply("0000000000000000000000000000000000000000000000000000000000000001".bytes)
            XCTAssertEqual(C_.stringRepresentation, "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2")
        }
        
        do {
            let B_ = try Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply("7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".bytes)
            XCTAssertEqual(C_.stringRepresentation, "0398bc70ce8184d27ba89834d19f5199c84443c31131e48d3c1214db24247d005d")
        }
        
        do {
            let k = try "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f".bytes
            let B_ = try Crypto.PublicKey(dataRepresentation: "02a9acc1e48c25eeeb9289b5031cc57da9fe72f3fe2861d264bdc074209b107ba2".bytes, format: .compressed)
            let C_ = try B_.multiply(k)
            XCTAssertEqual(C_.stringRepresentation, "0398bc70ce8184d27ba89834d19f5199c84443c31131e48d3c1214db24247d005d")
        }
    }
    
    func testDetSec() throws {
        let mnemmonic = try Mnemonic(phrase: "half depart obvious quality work element tank gorilla view sugar picture humble".components(separatedBy: " "))
        let seed = String(bytes: mnemmonic.seed)
        let keysetID = "009a1f293253e41e"
        
        
        let output = try Crypto.generateOutputs(amounts: [1,1,1,1,1], keysetID: keysetID, deterministicFactors: (seed: seed, counter: 0))
        
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
    
    
    /*
     testmint private keys
     
     1:     ab0008c5492a498eaf7cc5b13e3bdbca63bdefdde66c96bf3cf42b464bb2d35e
     2:     b06a292cff5991f6c8626e5c51cf92d478f76db9b2ad3ebba75f6159a547d6dc
     4:     27cba57886176546e45c160162ef6d583ea7a1f242e48a59e25d7053dd0aa7b6
     8:     822ac56f939e58f2295c77453cb46530265bdb351b02597fb0994669a07782fa
     16:    e4ea226bfeaef183fa2d0861669dd48c7d5a8208efacf06c24f84708929ce999
     32:    aa355eb85a63e80926f9d808ab1419db5a3682361749e8e754a8c488e22e9ada
     */
    
    func testMinting() async throws {
        
        let mintURL = URL(string: "https://testmint.macadamia.cash")!
        
        let mintInfo = try await Network.get(url: mintURL.appending(path: "/v1/info"), expected: MintInfo.self)
        
        let keysetList = try await Network.get(url: mintURL.appending(path: "/v1/keys"), expected: KeysetList.self)
        let keysetStateList = try await Network.get(url: mintURL.appending(path: "/v1/keysets"), expected: KeysetList.self)
        
        let combined = keysetList.keysets.map { keyset in
            var updated = keyset
            updated.active = keysetStateList.keysets.first(where: { $0.id == keyset.id })!.active
            return updated
        }
        
        let mint = Mint(url: mintURL,
                        allKeysets: combined,
                        info: mintInfo,
                        nickname: "mint")
        
        let reachable = await mint.isReachable()
        
        assert(reachable)
        
        let amount = 1
        
        let quote = try await Cashu.V1.getQuote(mint: mint,
                                                quoteRequest: Bolt11.RequestMintQuote(unit: "sat",
                                                                                      amount: amount))
        
        let proofs = try await Cashu.V1.issue(mint: mint, for: quote)
        
        let token = Token(token: [ProofContainer(mint: mint.url.absoluteString, proofs: proofs)])
        token.version = .V3
        token.unit = "sat"
        
        print(try token.serialize())
        print("keyset derivation counter: \(mint.keysets.map({$0.derivationCounter}))")
    }
    
    func testUnblind() throws {
        let C_ = try Crypto.PublicKey(dataRepresentation: "026ec253e4a3f43b44f33b78823e0a6a515bbe3cf3e99eda93c584eb858235576a".bytes, format: .compressed)
        let r = try Crypto.PrivateKey(dataRepresentation: "ab8b2ff87672e4918cc431b02c057c260ef7935396026c6e3fd21dacef6dae2a".bytes)
        let A = "02c8092ec2daa7eb3bf6dd3efc4e87bb5c2755c014c8fc9dc4d023938df16f5ca3"
        let keyset = Keyset(id: "", keys: ["1":A])
        
        let proofs = try Crypto.unblindPromises(promises: [Promise(id: "", amount: 1, C_: C_.stringRepresentation)],
                                            blindingFactors: [r.stringRepresentation],
                                            secrets: [""],
                                            keyset: keyset)
        
        //TODO: NEEDS REFERENCE VECTOR FOR COMPARISON
    }
    
    func testNegateKey() throws {
        let k = try Crypto.PublicKey(dataRepresentation: "0299c661b9032754db2812d7fe7d50d693e56fc4799d0b87a328e3e4e47640adbf".bytes, format: .compressed)
        print(k.stringRepresentation)
        print("original key: \(k.stringRepresentation), negated: \(Crypto.negatePublicKey(key: k).stringRepresentation)")
    }
}
