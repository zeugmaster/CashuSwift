import Foundation
import secp256k1

public class Cashu {
    struct V1 {
        private init() {}
        
        static func getQuote(mint:Mint, quoteRequest:QuoteRequest) async throws -> Quote {
            var url = mint.url
            switch quoteRequest {
            case let qReq as Bolt11.RequestMintQuote:
                url.append(path: "/v1/mint/quote/bolt11")
                return try await Network.get(url: url, expected: Bolt11.MintQuote.self)
            case let qReq as Bolt11.RequestMeltQuote:
                url.append(path: "/v1/mint/melt/bolt11")
                return try await Network.get(url: url, expected: Bolt11.MeltQuote.self)
            default:
                //TODO: make non fatal
                fatalError("User tried to call getQuote using unsupported QuoteRequest type.")
            }
        }
        
        static func issue(mint:Mint, for quote:Quote) async throws -> [Proof] {
            // 1 generate deterministic blinded outputs for amount from quote
            
            // 1 a determine keyset (unit, active)
            // 1 b 
            
            // 2 make post request with Quote and blinded outputs
            
            // 3 unblind signed outputs from mint
            
            // 4 increment secret counter on keyset (???)
            
            // 5 return proofs
            
            fatalError()
        }
        
        static func send(mint:Mint, amount:Int, proofs:[Proof]) async throws -> [Proof] {
            fatalError()
        }
        
        static func receive(mint:Mint, proofs:[Proof]) async throws -> [Proof] {
            fatalError()
        }
        
        static func melt(mint:Mint, quote:Quote, proofs:[Proof]) async throws -> [Proof] {
            fatalError()
        }
    }
}
