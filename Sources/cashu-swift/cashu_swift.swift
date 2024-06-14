import Foundation
import secp256k1

public class Cashu {
    static func getQuote(mint:Mint, quoteRequest:QuoteRequest) async throws -> Quote {
        fatalError()
    }
    
    static func issue(mint:Mint, for quote:Quote) async throws -> [Proof] {
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
