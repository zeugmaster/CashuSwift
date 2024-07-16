import Foundation
import secp256k1

public enum Cashu {
    enum V1 {
        
        static func getQuote(mint:Mint, quoteRequest:QuoteRequest) async throws -> Quote {
            var url = mint.url
            
            guard mint.keysets.contains(where: { $0.unit == quoteRequest.unit }) else {
                fatalError("the mint does not have a keyset that supports this unit")
            }
            
            switch quoteRequest {
            case let quoteRequest as Bolt11.RequestMintQuote:
                url.append(path: "/v1/mint/quote/bolt11")
                var result = try await Network.post(url: url, 
                                                    body: quoteRequest,
                                                    expected: Bolt11.MintQuote.self)
                result.requestDetail = quoteRequest
                return result
            case let quoteRequest as Bolt11.RequestMeltQuote:
                url.append(path: "/v1/melt/quote/bolt11")
                return try await Network.post(url: url, 
                                              body:quoteRequest,
                                              expected: Bolt11.MeltQuote.self)
            default:
                fatalError("User tried to call getQuote using unsupported QuoteRequest type.")
            }
        }
        
        /// After paying the quote amount to the mint, use this function to issue the actual ecash as a list of `Proof`s \n
        /// Leaving `seed` empty will give you proofs from non-deterministic outputs which cannot be recreated from a seed phrase backup
        static func issue(mint:Mint, 
                          for quote:Quote,
                          seed:String? = nil,
                          duplicateRetry:Int = 0,
                          preferredDistribution:[Int]? = nil) async throws -> [Proof] {
            
            guard let quote = quote as? Bolt11.MintQuote else {
                fatalError("Quote to issue proofs for was not a Bolt11.MintQuote")
            }
            
            guard let requestDetail = quote.requestDetail else {
                fatalError("You need to set requestDetail associated with the quote.")
            }
            
            var distribution:[Int]
            
            if let preferredDistribution = preferredDistribution {
                guard preferredDistribution.reduce(0, +) == requestDetail.amount else {
                    fatalError("Specified preferred distribution does not add up to the same amount as the quote.")
                }
                distribution = preferredDistribution
            } else {
                distribution = splitIntoBase2Numbers(requestDetail.amount)
            }
            
            guard var keyset = mint.keysets.first(where: { $0.active == true &&
                                                           $0.unit == requestDetail.unit }) else {
                fatalError("Could not determine an ACTIVE keyset for this unit")
            }
            
            // tuple for outputs, blindingfactors, secrets
            // swift does not allow uninitialized tuple declaration
            var outputs = (outputs:[Output](), blindingFactors:[""], secrets:[""])
            if let seed = seed {
                outputs = try Crypto.generateOutputs(amounts: distribution,
                                                     keysetID: keyset.id,
                                                     deterministicFactors: (seed: seed,
                                                                            counter: keyset.derivationCounter))
            } else {
                outputs = try Crypto.generateOutputs(amounts: distribution,
                                                     keysetID: keyset.id)
            }
            
            let mintRequest = Bolt11.MintRequest(quote: quote.quote, outputs: outputs.outputs)
            
            //TODO: PARSE COMMON ERRORS
            let promises = try await Network.post(url: mint.url.appending(path: "/v1/mint/bolt11"),
                                                  body: mintRequest,
                                                  expected: Bolt11.MintResponse.self)
            
            let proofs = try Crypto.unblindPromises(promises: promises.signatures,
                                                    blindingFactors: outputs.blindingFactors,
                                                    secrets: outputs.secrets,
                                                    keyset: keyset)
            
            keyset.derivationCounter += outputs.outputs.count
            
            return proofs
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

