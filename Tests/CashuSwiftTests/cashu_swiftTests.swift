import XCTest
@testable import CashuSwift
import SwiftData
import BIP39
import SwiftCBOR
import secp256k1
import CryptoKit

let dnsTestMint = "https://testmint.macadamia.cash"

final class cashu_swiftTests: XCTestCase {
    
    func testInvoiceAmount() throws {
        let invoice = "lnbc1u1p5tzakfpp5rmx3hpalue6tuwgsnkke8qf56eqv0v80p9d8n07r7xnt5pzyr8wqdqggdshx6r4cqzpuxqrwzqsp5u9nx53qsrd4kldd7j0j0flffz0fgsm62ujs8akdyf3clsyc2sg7q9qxpqysgqwkze9vkrxa3c8y0gfryvr4s2eapludn3tnn80slwtcgsjw8q878qcqpwnh2ftww8ypgj093kkehrqwlkmnma7c5e7n92e7qns2vlpxgp3aacr8"
        XCTAssertEqual(try CashuSwift.Bolt11.satAmountFromInvoice(pr: invoice), 100)
        XCTAssertEqual(try CashuSwift.Bolt11.satAmountFromInvoice(pr: invoice.uppercased()), 100)
    }
    
    func testSecretSerialization() throws {
        
        // test that deserialization from string works properly
        let secretString = "[\"P2PK\",{\"nonce\":\"859d4935c4907062a6297cf4e663e2835d90d97ecdd510745d32f6816323a41f\",\"data\":\"0249098aa8b9d2fbec49ff8598feb17b592b986e62319a4fa488a3dc36387157a7\",\"tags\":[[\"sigflag\",\"SIG_INPUTS\"]]}]"
        
        let data = secretString.data(using: .utf8)!
        let spendingCondition = try JSONDecoder().decode(CashuSwift.SpendingCondition.self, from: data)
        
        print(spendingCondition.debugPretty())
        
        print(try spendingCondition.serialize())
    }
    
    func testNetworkManager() async throws {
        do {
            let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 21)
            let url = URL(string: "https://testnut.cashu.space/v1/mint/quote/bolt11")!
            let quote = try await Network.post(url: url,
                                               body: mintQuoteRequest,
                                               expected: CashuSwift.Bolt11.MintQuote.self)
            print(quote)
        } catch let error as Network.Error {
            switch error {
            case .decoding(let data):
                print("Network.Error.decoding:")
                print(String(data: data, encoding: .utf8) ?? "could not ")
            case .encoding:
                print("there was an error encoding the data")
            }
        }
    }
    
    func testMintCheckReachable() async throws {
        let mintUrl = URL(string: "https://mint.macadamia.cash")!
        
        let mint = try await CashuSwift.loadMint(url: mintUrl, type: CashuSwift.Mint.self)
        
        let reachable = await mint.isReachable()
        
        // check that the mint's keysets contain at least one active one (required)
        let oneKeysetActive = mint.keysets.contains { $0.active == true }
        
        XCTAssert(reachable)
        XCTAssert(oneKeysetActive)
        
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
    
    func testMinting() async throws {
        
        let mintURL = URL(string: "https://testmint.macadamia.cash")!
        let mint = try await CashuSwift.loadMint(url: mintURL)
        let amount = 511
        let quote = try await CashuSwift.getQuote(mint: mint,
                                                  quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                   amount: amount)) as! CashuSwift.Bolt11.MintQuote
        let issued = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
        XCTAssertEqual(issued.dleqResult, .valid)
        
        let swapped = try await CashuSwift.swap(inputs: issued.proofs, with: mint, amount: 300, seed: nil, preferredReturnDistribution: nil)
        
        // verify amounts for no-fee operation
        XCTAssertEqual(swapped.change.sum, 211)
        XCTAssertEqual(swapped.new.sum, 300)
        XCTAssertEqual(swapped.inputDLEQ, .valid)
        XCTAssertEqual(swapped.outputDLEQ, .valid)
        
        // TODO: test with fee-taking mint
    }
    
    // TODO: add proper swap test
    
    func testMintingWithDetSec() async throws {
        let mnemmonic = Mnemonic()
        let seed = String(bytes: mnemmonic.seed)

        
        let url = URL(string: "https://testmint.macadamia.cash")!
        var mint = try await CashuSwift.loadMint(url: url)
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 32)
        let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

        let issued = try await CashuSwift.issue(for: q, mint: mint, seed: seed)
        
        if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
            mint.keysets[idx].derivationCounter += issued.proofs.count
        }
        
        // TODO: add thorough testing for swaps of different amounts...
    }
    
    func testSendReceive() async throws {
        
        do {
            let mnemmonic = Mnemonic()
            let seed = String(bytes: mnemmonic.seed)
            
            let url = URL(string: "https://testmint.macadamia.cash")!
            var mint = try await CashuSwift.loadMint(url: url)
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 32)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

            let issued = try await CashuSwift.issue(for: q, mint: mint, seed: seed)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: 20,
                                                       seed: seed,
                                                       memo: nil,
                                                       lockToPublicKey: nil)
            
            guard let tokenProofs = sendResult.token.proofsByMint.first?.value else {
                XCTFail("token should contain proofs.")
                return
            }
            
            XCTAssert(tokenProofs.sum == 20)
            XCTAssert(sendResult.change.sum == 12) // testmint.macadamia.cash does not have fees, easy calc
        }
        
        do {
            let mnemmonic = Mnemonic()
            let seed = String(bytes: mnemmonic.seed)
            
            let url = URL(string: "https://testnut.cashu.space")!
            var mint = try await CashuSwift.loadMint(url: url)
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 32)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

            let issued = try await CashuSwift.issue(for: q, mint: mint, seed: seed)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: 20,
                                                       seed: seed,
                                                       memo: nil,
                                                       lockToPublicKey: nil)
            
            guard let tokenProofs = sendResult.token.proofsByMint.first?.value else {
                XCTFail("token should contain proofs.")
                return
            }
            
            XCTAssert(tokenProofs.sum == 20)
//            XCTAssert(sendResult.change.sum == 12) // testmint.macadamia.cash does not have fees, easy calc
            
            // TODO: make sure the appropriate amount in change comes back
            print(sendResult.change.sum)
        }
        
        sleep(1)
        
        // check derivation counters for edge cases like proofs.sum == amount + fee
        do {
            let mnemmonic = Mnemonic()
            let seed = String(bytes: mnemmonic.seed)
            
            let target = 31
            
            let url = URL(string: "https://testnut.cashu.space")!
            var mint = try await CashuSwift.loadMint(url: url)
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 32)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

            let issued = try await CashuSwift.issue(for: q, mint: mint, seed: seed)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: target,
                                                       seed: seed,
                                                       memo: nil,
                                                       lockToPublicKey: nil)
            
            guard let tokenProofs = sendResult.token.proofsByMint.first?.value else {
                XCTFail("token should contain proofs.")
                return
            }
            
            XCTAssert(tokenProofs.sum == target)
            XCTAssert(sendResult.change.isEmpty) // 32 minted, 31 sent, 1 fee
            XCTAssertEqual(sendResult.counterIncrease?.increase, 5)
        }
        
        sleep(1)
        
        do {
            let mnemmonic = Mnemonic()
            let seed = String(bytes: mnemmonic.seed)
            
            let target = 50
            
            let url = URL(string: "https://testnut.cashu.space")!
            var mint = try await CashuSwift.loadMint(url: url)
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 127)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

            let issued = try await CashuSwift.issue(for: q, mint: mint, seed: seed)
            
            print("------")
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: target,
                                                       seed: seed,
                                                       memo: nil,
                                                       lockToPublicKey: nil)
            
            guard let tokenProofs = sendResult.token.proofsByMint.first?.value else {
                XCTFail("token should contain proofs.")
                return
            }
            
            XCTAssert(tokenProofs.sum == target)
            XCTAssertEqual(sendResult.counterIncrease?.increase, 6)
        }
        
        sleep(1)
        
        do {
            let target = 31
            
            let url = URL(string: "https://testnut.cashu.space")!
            var mint = try await CashuSwift.loadMint(url: url)
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 63)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

            let issued = try await CashuSwift.issue(for: q, mint: mint, seed: nil)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: target,
                                                       seed: nil,
                                                       memo: nil,
                                                       lockToPublicKey: nil)
            
            guard let tokenProofs = sendResult.token.proofsByMint.first?.value else {
                XCTFail("token should contain proofs.")
                return
            }
            
            XCTAssert(tokenProofs.sum == target)
            XCTAssertEqual(sendResult.counterIncrease?.increase, 0)
        }
    }
    
    func testMelt() async throws {
        let url = URL(string: "http://localhost:3339")!
        let mint = try await CashuSwift.loadMint(url: url, type: CashuSwift.Mint.self)
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 128)
        let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        
        let issueResult = try await CashuSwift.issue(for: q, mint: mint, seed: nil)
        
        let q2 = try await CashuSwift.getQuote(mint:mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 64)) as! CashuSwift.Bolt11.MintQuote
        
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", request: q2.request, options: nil)
        let quote = try await CashuSwift.getQuote(mint:mint, quoteRequest: quoteRequest) as! CashuSwift.Bolt11.MeltQuote
        
        let meltResult = try await CashuSwift.melt(quote: quote, mint: mint, proofs: issueResult.proofs)
        // meltResult.change is a list of proofs if you overpay on the melt quote
        // meltResult.quote.state == .paid if the Bolt11 lightning payment successful
        print(CashuSwift.sum(meltResult.change ?? []))
        
        XCTAssertEqual(meltResult.quote.state, .paid)
    }
    
    func testMeltExt() async throws {
//        let url = URL(string: "https://mint.macadamia.cash")!
//        let mint = try await CashuSwift.loadMint(url: url, type: CashuSwift.Mint.self)
//        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 128)
//        let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr)
//        
//        print(q)
//        sleep(20)
//        let proofs = try await CashuSwift.issue(for: q, on: mint)
//        
//        let q2 = try await CashuSwift.getQuote(mint:mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 64)) as! CashuSwift.Bolt11.MintQuote
//        
//        
//        let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", request: q2.request, options: nil)
//        let meltQ = try await CashuSwift.getQuote(mint:mint, quoteRequest: meltQuoteRequest)
//        
//        let result = try await CashuSwift.melt(mint: mint, quote: meltQ, proofs: proofs)
//        // result.change is a list of proofs if you overpay on the melt quote
//        // result.paid == true if the Bolt11 lightning payment successful
//        print(CashuSwift.sum(result.change))
//        
//        XCTAssert(result.paid)
    }
    
    // TODO: MELT TEST WITH REGTEST MOCK MINTS
    
    func testBlankOutputCalculation() {
        let overpayed = 1000
        let n = calculateNumberOfBlankOutputs(overpayed)
        XCTAssert(n == 10)
    }
    
    func testDeliberateOverpay() async throws {
        let url = URL(string: "http://localhost:3339")!
        let mint = try await CashuSwift.loadMint(url: url)
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 128)
        let q = try await CashuSwift.getQuote(mint:mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote

        print(q)
//        sleep(30)

        let issueResult = try await CashuSwift.issue(for: q, mint: mint, seed: nil)

        let q2 = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 64)) as! CashuSwift.Bolt11.MintQuote
        let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", request: q2.request, options: nil)
        let meltQ = try await CashuSwift.getQuote(mint: mint, quoteRequest: meltQuoteRequest) as! CashuSwift.Bolt11.MeltQuote
        let meltResult = try await CashuSwift.melt(quote: meltQ, mint:mint, proofs: issueResult.proofs)
        
        // TODO: VERIFY RESULTS
    }
    
    func testTokenStateCheck() async throws {
        let mint = try await CashuSwift.loadMint(url: URL(string: "http://localhost:3339")!)
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 400)
        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: quoteRequest) as! CashuSwift.Bolt11.MintQuote
        
        let issueResult = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
        
        let sendResult = try await CashuSwift.send(inputs: issueResult.proofs, mint: mint, seed: nil)
        
        _ = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: nil)
        
        let states = try await CashuSwift.check(issueResult.proofs, mint: mint)
        XCTAssert(states.allSatisfy({ $0 == .spent }))
    }
    
    func testRestore() async throws {
        let mnemmonic = Mnemonic()
        let seed = String(bytes: mnemmonic.seed)
        
        let burnMnemonic = Mnemonic()
        let burnSeed = String(bytes: burnMnemonic.seed)
        
        // MARK: NEEDS TO BE TESTED WITH NO-FEE MINT
        var mint = try await CashuSwift.loadMint(url: URL(string: "https://testmint.macadamia.cash")!)
        
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 2047)

        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: quoteRequest) as! CashuSwift.Bolt11.MintQuote
        
        var issueResult = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
        
        if let index = mint.keysets.firstIndex(where: { $0.keysetID == issueResult.proofs.first?.keysetID }) {
            var keyset = mint.keysets[index]
            keyset.derivationCounter += issueResult.proofs.count
            mint.keysets[index] = keyset
        }
        
        let swapped = try await CashuSwift.swap(inputs: Array(issueResult.proofs.prefix(2)), with: mint, amount: nil, seed: burnSeed, preferredReturnDistribution: nil)
        
        guard let restoredProofs = try await CashuSwift.restore(mint:mint, with: seed).first?.proofs as? [CashuSwift.Proof] else {
            XCTFail("failed due to type casting error")
            return
        }
        
        XCTAssertEqual(Array(issueResult.proofs.dropFirst(2)), restoredProofs)
        XCTAssertEqual(Array(issueResult.proofs.dropFirst(2)).sum, restoredProofs.sum)
        
        let (_, dleqValid) = try await CashuSwift.restore(from: mint, with: seed)
        XCTAssertTrue(dleqValid)
    }
    
    func testFeeCalculation() async throws {
        let mint = try await CashuSwift.loadMint(url: URL(string: "http://localhost:3339")!)
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 511)
        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: quoteRequest) as! CashuSwift.Bolt11.MintQuote
        
        let issueResult = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
        
        let fees = try CashuSwift.calculateFee(for: issueResult.proofs, of: mint)
        print("Number of inputs \(issueResult.proofs.count), fees: \(fees)")
        
        let swapped = try await CashuSwift.swap(inputs: issueResult.proofs, with: mint, amount: 400, seed: nil, preferredReturnDistribution: nil)
        let swappedNewSum = swapped.new.reduce(0) { $0 + $1.amount }
        let swappedChangeSum = swapped.change.reduce(0) { $0 + $1.amount }
        print("Number of outputs \(swapped.new.count),  new sum: \(swappedNewSum), change sum:\(swappedChangeSum)")
    }
    
    func testUnblind() throws {
        let C_ = try CashuSwift.Crypto.PublicKey(dataRepresentation: "031c14eed30e32a060030bc9784ed34db7de91ce188ea0cce6f48a84b47ddbd875".bytes, format: .compressed)
        let r = try CashuSwift.Crypto.PrivateKey(dataRepresentation: "c551bd0a48e3a069d8a02dc8b1783923da0d9af015f575c0a521237e10316580".bytes)
        // we only test for the amount 1 and the corresponding mint public key
        let A = try CashuSwift.Crypto.PublicKey(dataRepresentation: "02221e05e446782ba13bb41a8b74ac344a4829cf8417d8e7d32c0152a64755bfae".bytes, format: .compressed)
        
        let proof = try CashuSwift.Crypto.unblind(C_: C_, r: r, A: A)
        
        XCTAssertEqual(proof.stringRepresentation, "0218b90f0de65ae3447624fc8895c31302e61cef56dbca927717cb501cf591ce32")
    }
    
    typealias Proof = CashuSwift.Proof
    
    func testProofSelection() async throws {
        
        let mint = try await CashuSwift.loadMint(url: URL(string: "http://localhost:3339")!)
        
        let keysetID = CashuSwift.activeKeysetForUnit("sat", mint: mint)!.keysetID

        let proofs =   [Proof(keysetID: keysetID, amount: 1, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 1, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 8, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 4, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 32, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 2, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 16, secret: "", C: ""),
                        Proof(keysetID: keysetID, amount: 128, secret: "", C: "")]
        
        let selection1 = CashuSwift.pick(proofs, amount: 50, mint: mint)
        print(selection1 ?? "nil")
        
        let selection2 = CashuSwift.pick(proofs, amount: 1, mint: mint)
        print(selection2 ?? "nil")
        
        let selection3 = CashuSwift.pick(proofs, amount: proofs.sum, mint: mint)
        print(selection3 ?? "nil")
        
        let invalidSelection = CashuSwift.pick(proofs, amount: proofs.sum, mint: mint, ignoreFees: true)
        print(invalidSelection ?? "nil")
        
        let invalidSelection2 = CashuSwift.pick(proofs, amount: 3000, mint: mint)
        print(invalidSelection2 ?? "nil")
        
        let selection4 = CashuSwift.pick(proofs, amount: 165, mint: mint)
        print(selection4 ?? "nil")
    }
    
    func testInfoLoad() async throws {
        let url = URL(string: "https://mint.macadamia.cash")!
        let mint = try await CashuSwift.loadMint(url: url)
        
        let info = try await CashuSwift.loadMintInfo(from: mint)
        
        print(info.debugPretty())
        
        print(mint.keysets.allSatisfy({ $0.validID }))
    }
    
    func testErrorHandling() async throws {
        
        let url = URL(string: "https://mint.macadamia.cash")!
        let mint = try await CashuSwift.loadMint(url: url)
        
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 42)
            let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            _ = try await CashuSwift.issue(for: q, mint: mint, seed: nil)
            XCTFail("issuing on unpaid quote should not succeed. is mint fakewallet_brr = true?")
        } catch let error as CashuError {
            XCTAssertEqual(error, .quoteNotPaid)
        } catch {
            XCTFail("unexpected type of error")
        }
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
    
    func testTokenV4Serde() async throws {
       
        let url = URL(string: "https://testnut.cashu.space")!
        let mint = try await CashuSwift.loadMint(url: url)
        
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 21)
        
        let q1 = try await CashuSwift.getQuote(mint: mint,
                                               quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        let issueResult1 = try await CashuSwift.issue(for: q1, mint: mint, seed: nil)
        
        let token1 = CashuSwift.Token(proofs: [mint.url.absoluteString: issueResult1.proofs],
                                     unit: qr.unit,
                                     memo: "bingo bango")
        
        let codable = try JSONEncoder().encode(token1)
        let decodable = try JSONDecoder().decode(CashuSwift.Token.self, from: codable)
        
        XCTAssertEqual(token1, decodable)
        
        print(try token1.serialize(to: .V3))
        
        let q2 = try await CashuSwift.getQuote(mint: mint,
                                               quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        let issueResult2 = try await CashuSwift.issue(for: q2, mint: mint, seed: nil)
        
        let token2 = CashuSwift.Token(proofs: [mint.url.absoluteString: issueResult2.proofs],
                                      unit: qr.unit,
                                      memo: "bob's your uncle")
        
        print(try token2.serialize(to: .V4))
    }
    
    // MARK: - REVERSE
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
    
    func testSwapDLEQCheck() async throws {
        let mint = try await CashuSwift.loadMint(url: URL(string: dnsTestMint)!)
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 3)
        
        let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        
        let mintResult = try await CashuSwift.issue(for: mintQuote, mint: mint, seed: nil, preferredDistribution: [1, 1, 1])
        
//        let swap1 = try await CashuSwift.swap(with: mint, inputs: [mintResult.proofs[0]], seed: nil)
        let swap1 = try await CashuSwift.swap(inputs: [mintResult.proofs[0]], with: mint, seed: nil)
        XCTAssertEqual(swap1.inputDLEQ, .valid)
        XCTAssertEqual(swap1.outputDLEQ, .valid)
        
        // Deliberately omitting DLEQ data to ensure check is still passing but prints warning...
        let p2 = mintResult.proofs[1]
        let inputWithoutDLEQfields = Proof(keysetID: p2.keysetID, amount: p2.amount, secret: p2.secret, C: p2.C, dleq: nil)
        let swap2 = try await CashuSwift.swap(inputs: [inputWithoutDLEQfields], with: mint, seed: nil)
        XCTAssertEqual(swap2.inputDLEQ, .noData)
        XCTAssertEqual(swap2.outputDLEQ, .valid)
        
        let r = "a6d13fcd7a18442e6076f5e1e7c887ad5de40a019824bdfa9fe740d302e8d861"
        let e = "b31e58ac6527f34975ffab13e70a48b6d2b0d35abc4b03f0151f09ee1a9763d4"
        let s = "8fbae004c59e754d71df67e392b6ae4e29293113ddc2ec86592a0431d16306d8"
        let wrongDLEQ = CashuSwift.DLEQ(e: e, s: s, r: r)
        
        let p3 = mintResult.proofs[2]
        let inputRandomDLEQdata = Proof(keysetID: p3.keysetID, amount: p3.amount, secret: p3.secret, C: p3.C, dleq: wrongDLEQ)
        let swap3 = try await CashuSwift.swap(inputs: [inputRandomDLEQdata], with: mint, seed: nil)
        XCTAssertEqual(swap3.inputDLEQ, .fail)
        XCTAssertEqual(swap3.outputDLEQ, .valid)
    }
    
    func testTokenDeserializationWithDLEQ() throws {
        let token = try "cashuBo2FteBtodHRwczovL3Rlc3RudXQuY2FzaHUuc3BhY2VhdWNzYXRhdIGiYWlIAJofKTJT5B5hcIGkYWEBYXN4QDcyMGVhMjcwYTQ4NDk0YThhNzMwM2E2YjczZTk5NDM1MTU1ZGFjMzFmYjIyYjg5YjllZjFmZGFlMzNjNmIzODVhY1ghAh9iiqwq9POuxIxSW8APMCT3Mw9d5bQv0uTZvUQow9V5YWSjYWVYIGMAHPJTvIcRDgIYcks-1CgWGCipn8QPxmrBvQRxA-RaYXNYICF1NnjVfZDs30T0TXUIORPbaNKkbYUI8vhUPJCxwCy6YXJYIE7keXw6yoxTzpgT_qGKJvWVrDP4NcCPAMlSMPY37LpO".deserializeToken()
        print(token.debugPretty())
    }
    
    func testMintStateCheck() async throws {
        let mintBrrrrr = try await CashuSwift.loadMint(url: URL(string: dnsTestMint)!)
        let mintStingy = try await CashuSwift.loadMint(url: URL(string: "https://mint.macadamia.cash")!)
        
        let mintRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 42)
        
        var q1 = try await CashuSwift.getQuote(mint: mintBrrrrr, quoteRequest: mintRequest)
        var q2 = try await CashuSwift.getQuote(mint: mintStingy, quoteRequest: mintRequest)
        
        sleep(2)
        
        q1 = try await CashuSwift.mintQuoteState(for: q1.quote, mint: mintBrrrrr)
        q2 = try await CashuSwift.mintQuoteState(for: q2.quote, mint: mintStingy)
        
        XCTAssertEqual(q1.state, .paid)
        XCTAssertEqual(q2.state, .unpaid)
    }
    
    func testSchnorrPubkey() throws {
        let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
        let pubkeyHex = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"
        
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyHex.bytes)
        XCTAssertEqual(String(bytes: privateKey.publicKey.dataRepresentation), pubkeyHex)
    }
    
    func testCreateLockedToken() async throws {
        
        let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
        let pubkeyHex = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"
        
        let mint = try await CashuSwift.loadMint(url: URL(string: dnsTestMint)!)
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 2)
        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        let proofs = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
        print(proofs.proofs)
        
        let sendResult = try await CashuSwift.send(inputs: proofs.proofs,
                                                   mint: mint,
                                                   amount: 1,
                                                   seed: nil,
                                                   lockToPublicKey: pubkeyHex)
        print(sendResult.token.debugPretty())
        print(try sendResult.token.serialize(to: .V4))
        
        let received = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: privateKeyHex)
        print(received.proofs)
    }
    
    func testSendReceiveLocked() async throws {
        let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
        let pubkeyHex = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"
        
        let mnemmonic = Mnemonic()
        let seed = String(bytes: mnemmonic.seed)

        
        var mint = try await CashuSwift.loadMint(url: URL(string: "https://testnut.cashu.space")!)
        
//         test with simple 2 - 1 proof send, nondet
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 31)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let proofs = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
            
            let sendResult = try await CashuSwift.send(inputs: proofs.proofs,
                                                       mint: mint,
                                                       amount: 15,
                                                       seed: nil,
                                                       lockToPublicKey: pubkeyHex)
            print("change sum: \(sendResult.change.sum)")
            print("token sum: \(String(describing: sendResult.token.proofsByMint.first?.value.sum))")
//            _ = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: privateKeyHex)
            
        }
        
        sleep(1)
        
        // many inputs, send all, nondet
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 63)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let proofs = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
            
            let sendResult = try await CashuSwift.send(inputs: proofs.proofs,
                                                       mint: mint,
                                                       seed: nil,
                                                       lockToPublicKey: pubkeyHex)
            print("change sum: \(sendResult.change.sum)")
            print("token sum: \(String(describing: sendResult.token.proofsByMint.first?.value.sum))")
            _ = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: privateKeyHex)
        }
        
        sleep(1)
        
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 63)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let proofs = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
            
            _ = try await CashuSwift.send(inputs: proofs.proofs,
                                                       mint: mint,
                                                       amount: 0,
                                                       seed: nil,
                                                       lockToPublicKey: pubkeyHex)
            
        } catch let error as CashuError {
            XCTAssert(error == CashuError.invalidAmount)
        }
        
        sleep(1)
        
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 63)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let proofs = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
            
            let sendResult = try await CashuSwift.send(inputs: proofs.proofs,
                                                       mint: mint,
                                                       amount: 21,
                                                       seed: nil,
                                                       lockToPublicKey: pubkeyHex)
            
            let sendLocked = try await CashuSwift.send(inputs: sendResult.token.proofsByMint.first!.value,
                                                       mint: mint,
                                                       seed: nil)
            XCTAssertEqual(sendLocked.outputDLEQ, .valid)
            
        } catch let error as CashuError {
            XCTAssert(error == CashuError.spendingConditionError(""))
        }
        
        sleep(1)
        
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 335)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let issued = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
            
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: 15,
                                                       seed: seed,
                                                       lockToPublicKey: pubkeyHex)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                let increase = /*(sendResult.token.proofsByMint.first?.value.count ?? 0) +*/ sendResult.change.count // with P2PK only change is deterministic
                mint.keysets[idx].derivationCounter += increase
            }
            
            print("change sum: \(sendResult.change.sum)")
            print("token sum: \(String(describing: sendResult.token.proofsByMint.first?.value.sum))")
            let receive = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: seed, privateKey: privateKeyHex)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                let increase = receive.proofs.count // with P2PK only change is deterministic
                mint.keysets[idx].derivationCounter += increase
            }
        }
        
        sleep(1)
        
        do {
            let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 335)
            let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
            let issued = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
            
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                mint.keysets[idx].derivationCounter += issued.proofs.count
            }
            
            let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                       mint: mint,
                                                       amount: 15,
                                                       seed: seed,
                                                       lockToPublicKey: nil)
            
            if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                let increase = (sendResult.token.proofsByMint.first?.value.count ?? 0) + sendResult.change.count // with P2PK only change is deterministic
                mint.keysets[idx].derivationCounter += increase
            }
            
            print(try sendResult.token.serialize(to: .V4))
            
            print("change sum: \(sendResult.change.sum)")
            print("token sum: \(String(describing: sendResult.token.proofsByMint.first?.value.sum))")
            let received = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: seed, privateKey: privateKeyHex)
            XCTAssertEqual(received.outputDLEQ, .valid)
            XCTAssertEqual(received.inputDLEQ, .valid)
        }
    }
    
    func testLocalLockedSendReceive() async throws {
        let privateKeyHex = "e95f2010be31354aa13e5b93c4694a8c32fbccaa76274592a32e922bbd8253ac"
        let pubkeyHex = "03f9f5b9805b23d62652180f40aadd8a37702afc0ba0f5a64f7bb761577fe3974e"
        
        let mnemmonic = Mnemonic()
        let seed = String(bytes: mnemmonic.seed)
        
        let url = URL(string: "http://localhost:3338")!
        var mint = try await CashuSwift.loadMint(url: url)
        
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 334)
        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        
        let issued = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
        
        if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
            mint.keysets[idx].derivationCounter += issued.proofs.count
        }
        
        let sendResult = try await CashuSwift.send(inputs: issued.proofs,
                                                   mint: mint,
                                                   amount: 201,
                                                   seed: seed,
                                                   memo: nil,
                                                   lockToPublicKey: pubkeyHex)
        
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
    
    func testKeysetValidation() async throws {
        // Load mint from testmint.macadamia.cash
        let mintURL = URL(string: "https://testmint.macadamia.cash")!
        var mint = try await CashuSwift.loadMint(url: mintURL)
        
        // First validation: all keysets should have valid IDs
        let initialValidation = mint.keysets.allSatisfy({ $0.validID })
        XCTAssertTrue(initialValidation, "All keysets should have valid IDs when freshly loaded from mint")
        
        print("Initial validation passed: all \(mint.keysets.count) keysets have valid IDs")
        
        // Modify one keyset slightly by changing one of its keys
        guard var firstKeyset = mint.keysets.first else {
            XCTFail("Mint should have at least one keyset")
            return
        }
        
        let originalKeyset = firstKeyset
        print("Original keyset ID: \(firstKeyset.keysetID)")
        print("Original keyset has \(firstKeyset.keys.count) keys")
        
        // Find the first key and modify it slightly
        guard let firstKeyPair = firstKeyset.keys.first else {
            XCTFail("Keyset should have at least one key")
            return
        }
        
        let originalKey = firstKeyPair.value
        
        // Modify the last character of the key to make it invalid
        var modifiedKey = originalKey
        if let lastChar = modifiedKey.last {
            // Change the last character to make the key invalid
            modifiedKey = String(modifiedKey.dropLast()) + (lastChar == "a" ? "b" : "a")
        }
        
        print("Modified key from: \(originalKey)")
        print("Modified key to:   \(modifiedKey)")
        
        // Update the keyset with the modified key
        firstKeyset.keys[firstKeyPair.key] = modifiedKey
        
        // Replace the first keyset in the mint
        mint.keysets[0] = firstKeyset
        
        // Second validation: the modified keyset should now have an invalid ID
        let modifiedKeysetValidation = mint.keysets[0].validID
        XCTAssertFalse(modifiedKeysetValidation, "Modified keyset should have invalid ID")
        
        // Verify that the rest of the keysets are still valid
        let otherKeysetsValidation = mint.keysets.dropFirst().allSatisfy({ $0.validID })
        XCTAssertTrue(otherKeysetsValidation, "Other keysets should still have valid IDs")
        
        print("Validation test passed: modified keyset now has invalid ID")
        print("Modified keyset validID: \(modifiedKeysetValidation)")
        
        // Restore the original keyset to verify the check works both ways
        mint.keysets[0] = originalKeyset
        let restoredValidation = mint.keysets[0].validID
        XCTAssertTrue(restoredValidation, "Restored keyset should have valid ID again")
        
        print("Restoration test passed: original keyset has valid ID again")
    }
    
    func testMintingDLEQ() async throws {
        let url = URL(string: "http://localhost:3338")!
        let mint = try await CashuSwift.loadMint(url: url)
        
        let req = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 21)
        guard let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: req) as? CashuSwift.Bolt11.MintQuote else {
            XCTFail()
            return
        }
        
        let result = try await CashuSwift.issue(for: q, mint: mint, seed: nil)
        
        XCTAssertEqual(result.dleqResult, .valid)
    }
    
    func testKDFerrorBIP32() throws {
        let path = "m/129372'/0'/1536791888'/36'/0"
        let seed = "5f911180b9d710a730a277a651d1bc347eef5546953fe99470ebdde467c54ae0d264ca3ee2d75f19a248c391ce7495c313cc0302c6b8bfff6d921c6dab282bda"
        
        let key = try CashuSwift.Crypto.childPrivateKeyForDerivationPath(seed: seed,
                                                                         derivationPath: path)
        
        print(String(bytes: key.dataRepresentation))
        print(key.dataRepresentation.count)
    }
    
    func testRestoreLargeBatch() async throws {
        let seed = String(bytes: Mnemonic().seed)
        let mint = try await CashuSwift.loadMint(url: URL(string: "http://localhost:3338")!)
        
        let distribution = Array(repeating: 1, count: 200)
        
        let req = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: distribution.reduce(0, +))
        guard let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: req) as? CashuSwift.Bolt11.MintQuote else {
            XCTFail()
            return
        }
        
        let result = try await CashuSwift.issue(for: q, mint: mint, seed: seed, preferredDistribution: distribution)
        
        print("minted \(result.proofs.count) proofs")
        
        let restore = try await CashuSwift.restore(from: mint, with: seed, batchSize: 300)
        XCTAssertEqual(restore.result.first?.proofs.count, result.proofs.count)
    }
    
    func testMeltChangeAmounts() async throws {
        
        do {
            let url = URL(string: "https://testnut.cashu.space")!
            var mint = try await CashuSwift.loadMint(url: url)
            
            do {
                let request = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 512)
                let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as! CashuSwift.Bolt11.MintQuote
                let issue = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
                
                let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                                           amount: 300)) as! CashuSwift.Bolt11.MintQuote
                
                let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                                                                           request: mintQuote.request, options: nil)) as! CashuSwift.Bolt11.MeltQuote
                
                let changeOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                        proofs: issue.proofs,
                                                                        mint: mint,
                                                                        unit: "sat",
                                                                        seed: nil)
                
                let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                           mint: mint,
                                                           proofs: issue.proofs,
                                                           blankOutputs: changeOutputs)
                
                let inputFee = try CashuSwift.calculateFee(for: issue.proofs, of: mint)
                
                XCTAssertEqual(meltResult.change!.sum, 512 - 300 - meltQuote.feeReserve - inputFee)
            }
            
            do {
                let mnemmonic = Mnemonic()
                let seed = String(bytes: mnemmonic.seed)
                
                let request = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 512)
                let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as! CashuSwift.Bolt11.MintQuote
                let issue = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
                
                if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                    mint.keysets[idx].derivationCounter += issue.proofs.count
                }
                
                let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                                           amount: 300)) as! CashuSwift.Bolt11.MintQuote
                
                let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                                                                           request: mintQuote.request, options: nil)) as! CashuSwift.Bolt11.MeltQuote
                
                let changeOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                        proofs: issue.proofs,
                                                                        mint: mint,
                                                                        unit: "sat",
                                                                        seed: seed)
                
                let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                           mint: mint,
                                                           proofs: issue.proofs,
                                                           blankOutputs: changeOutputs)
                
                let inputFee = try CashuSwift.calculateFee(for: issue.proofs, of: mint)
                
                XCTAssertEqual(meltResult.change!.sum, 512 - 300 - meltQuote.feeReserve - inputFee)
            }
        }
        
        do {
            let url = URL(string: "https://testmint.macadamia.cash")!
            var mint = try await CashuSwift.loadMint(url: url)
            
            do {
                let request = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 512)
                let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as! CashuSwift.Bolt11.MintQuote
                let issue = try await CashuSwift.issue(for: quote, mint: mint, seed: nil)
                
                let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                                           amount: 300)) as! CashuSwift.Bolt11.MintQuote
                
                let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                                                                           request: mintQuote.request, options: nil)) as! CashuSwift.Bolt11.MeltQuote
                
                let changeOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                        proofs: issue.proofs,
                                                                        mint: mint,
                                                                        unit: "sat",
                                                                        seed: nil)
                
                let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                           mint: mint,
                                                           proofs: issue.proofs,
                                                           blankOutputs: changeOutputs)
                
                let inputFee = try CashuSwift.calculateFee(for: issue.proofs, of: mint)
                
                XCTAssertEqual(meltResult.change!.sum, 512 - 300 - meltQuote.feeReserve - inputFee)
            }
            
            do {
                let mnemmonic = Mnemonic()
                let seed = String(bytes: mnemmonic.seed)
                
                let request = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 53223)
                let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as! CashuSwift.Bolt11.MintQuote
                let issue = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
                
                if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                    mint.keysets[idx].derivationCounter += issue.proofs.count
                }
                
                let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                                           amount: 300)) as! CashuSwift.Bolt11.MintQuote
                
                let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                                                                           request: mintQuote.request, options: nil)) as! CashuSwift.Bolt11.MeltQuote
                
                let changeOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                        proofs: issue.proofs,
                                                                        mint: mint,
                                                                        unit: "sat",
                                                                        seed: seed)
                
                let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                           mint: mint,
                                                           proofs: issue.proofs,
                                                           blankOutputs: changeOutputs)
                
                let inputFee = try CashuSwift.calculateFee(for: issue.proofs, of: mint)
                
                XCTAssertEqual(meltResult.change!.sum, 53223 - 300 - meltQuote.feeReserve - inputFee)
            }
            
            do {
                let mnemmonic = Mnemonic()
                let seed = String(bytes: mnemmonic.seed)
                
                let request = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 53223)
                let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as! CashuSwift.Bolt11.MintQuote
                let issue = try await CashuSwift.issue(for: quote, mint: mint, seed: seed)
                
                if let idx = mint.keysets.firstIndex(where: { $0.keysetID == CashuSwift.activeKeysetForUnit("sat", mint: mint)?.keysetID }) {
                    mint.keysets[idx].derivationCounter += issue.proofs.count
                }
                
                let mintQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                                                           amount: 300)) as! CashuSwift.Bolt11.MintQuote
                
                let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                                                                           request: mintQuote.request, options: nil)) as! CashuSwift.Bolt11.MeltQuote
                
                let changeOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                        proofs: issue.proofs,
                                                                        mint: mint,
                                                                        unit: "sat",
                                                                        seed: seed)
                
                let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                           mint: mint,
                                                           proofs: issue.proofs,
                                                           blankOutputs: changeOutputs)
                
                let inputFee = try CashuSwift.calculateFee(for: issue.proofs, of: mint)
                
                XCTAssertEqual(meltResult.change!.sum, 53223 - 300 - meltQuote.feeReserve - inputFee)
            }
        }
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
    
    func testKeysetV2idCalculation() async throws {
        let keys = [
            "1": "03a40f20667ed53513075dc51e715ff2046cad64eb68960632269ba7f0210e38bc",
            "2": "03fd4ce5a16b65576145949e6f99f445f8249fee17c606b688b504a849cdc452de",
            "4": "02648eccfa4c026960966276fa5a4cae46ce0fd432211a4f449bf84f13aa5f8303",
            "8": "02fdfd6796bfeac490cbee12f778f867f0a2c68f6508d17c649759ea0dc3547528"
          ]
        let unit = "sat"
        let finalExpiry = 2059210353
        
        let id = try CashuSwift.Keyset.calculateHexKeysetIDv2(keyset: keys, unit: unit, finalExpiry: finalExpiry)
        
        XCTAssertEqual(id, "01adc013fa9d85171586660abab27579888611659d357bc86bc09cb26eee8bc035")
        
        let url = URL(string: "https://v2.fake.thesimplekid.dev")!
        
        let mint = try await CashuSwift.loadMint(url: url)
        XCTAssert(mint.keysets.allSatisfy(\.validID))
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
    
    func testKeysetV2ids() async throws {
        let url = URL(string: "https://nut.v2.mint.ucash.space")!
        var mint = try await CashuSwift.loadMint(url: url)
        
        mint.keysets.removeAll(where: { $0.keysetID.count < 20 })
        
        print(mint.keysets.debugPretty())
        
        let qr = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 123)
        let q = try await CashuSwift.getQuote(mint: mint, quoteRequest: qr) as! CashuSwift.Bolt11.MintQuote
        
        // 
        sleep(5)
        
        let issued = try await CashuSwift.issue(for: q, mint: mint, seed: nil)
        
        let sendResult = try await CashuSwift.send(inputs: issued.proofs, mint: mint, amount: 100, seed: nil, memo: nil, lockToPublicKey: nil)
        
        print(sendResult.token.debugPretty())
        print(sendResult.send.debugPretty())
        
        let receiveResult = try await CashuSwift.receive(token: sendResult.token, of: mint, seed: nil, privateKey: nil)
        print(receiveResult.debugPretty())
    }
}
