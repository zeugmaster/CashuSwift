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
        
//        print("Test token serialized: \(testToken)")
        
        XCTAssertEqual(token, try testToken.deserializeToken())
        
        
    }
    
    func testSecretSerialization() {
        let tag = SpendingCondition.Tag.n_sigs(values: [1, 2])
        let tag2 = SpendingCondition.Tag.sigflag(values: ["one", "two", "three"])
        let tags = [tag, tag2]
        let sc = SpendingCondition(nonce: "test_nonce", data: "test_data", tags: tags)
        let secret = Secret.HTLC(sc: sc)
        
        print(secret.serialize())
//        let data = try! JSONEncoder().encode(sc)
//        let s = String(data: data, encoding: .utf8)
        
//        print(s!)
        
//        let reverse = try! JSONDecoder().decode(SpendingCondition.self, from: data)
        
//        print(reverse)
    }
}
