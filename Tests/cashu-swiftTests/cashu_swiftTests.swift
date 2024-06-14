import XCTest
@testable import cashu_swift
import secp256k1

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
            let url = URL(string: "https://mint.macadamia.cash/v1/mint/quote/bolt11")!
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
}
