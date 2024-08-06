import Foundation
import secp256k1

extension Mint {
    
    // MARK: - GET QUOTE
    
    func getQuote(quoteRequest:QuoteRequest) async throws -> Quote {
        var url = self.url
        
        guard self.keysets.contains(where: { $0.unit == quoteRequest.unit }) else {
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
    
    // MARK: - ISSUE
    
    /// After paying the quote amount to the mint, use this function to issue the actual ecash as a list of `Proof`s \n
    /// Leaving `seed` empty will give you proofs from non-deterministic outputs which cannot be recreated from a seed phrase backup
    func issue(for quote:Quote,
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
            distribution = Cashu.splitIntoBase2Numbers(requestDetail.amount)
        }
        
        guard var keyset = self.keysets.first(where: { $0.active == true &&
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
        
        // TODO: PARSE COMMON ERRORS
        // TODO: CHECK FOR DUPLICATE OUTPUT ERROR, RETRY ACC TO `duplicateRetry`
        let promises = try await Network.post(url: self.url.appending(path: "/v1/mint/bolt11"),
                                              body: mintRequest,
                                              expected: Bolt11.MintResponse.self)
                    
        let proofs = try Crypto.unblindPromises(promises.signatures,
                                                blindingFactors: outputs.blindingFactors,
                                                secrets: outputs.secrets,
                                                keyset: keyset)
                    
        keyset.derivationCounter += outputs.outputs.count
        
        return proofs
    }
    
    // MARK: - SEND
    
    func send(amount:Int, proofs:[Proof], seed:String? = nil) async throws -> (token:Token, change:[Proof]) {
        fatalError()
    }
    
    // MARK: - RECEIVE
    
    func receive(token:Token, seed:String? = nil) async throws -> [Proof] {
        fatalError()
    }
    
    // MARK: - MELT
    
    func melt(quote:Quote, proofs:[Proof]) async throws -> [Proof] {
        fatalError()
    }
    
    // MARK: - SWAP
    
    func swap(proofs:[Proof], 
              amount:Int? = nil,
              seed:String? = nil,
              preferredReturnDistribution:[Int]? = nil) async throws -> (new:[Proof],
                                                                         change:[Proof]) {
        let fee = try calculateFee(for: proofs)
        let proofSum = proofs.reduce(0) { $0 + $1.amount }
        let amount = amount ?? (proofSum-fee)
        
        let amountAfterFee = amount - fee
        
        print("fee: \(fee), \nproofSum:\(proofSum), \namounr:\(amount), \namountAfterFee:\(amountAfterFee)")
        
        guard proofSum >= amountAfterFee else {
            fatalError("target swap amount is larger than sum of proof amounts")
        }
        
        // the number of units from potentially mutliple keysets across input proofs must be 1:
        // less than 1 would mean no matching keyset/unit
        // more than one would imply multiple unit input proofs, which is not supported
        var units:Set<String> = []
        for proof in proofs {
            if let keysetForID = self.keysets.first(where: { $0.id == proof.id }) {
                units.insert(keysetForID.unit)
            } else {
                // found a proof that belongs to a keyset not from this mint
                fatalError("proofs from keysets that do not belong to this mint")
            }
        }
        
        guard units.count == 1 else {
            fatalError("mixed unit inputs or other problem with composition of inputs")
        }
        
        guard var activeKeyset = activeKeysetForUnit(units.first!) else {
            fatalError("no active keyset could be found for unit \(String(describing: units.first))")
        }
        
        // TODO: implement true output selection
        // TODO: INCLUDE FEE CALCULATION
        
        let swapDistribution = Cashu.splitIntoBase2Numbers(amountAfterFee)
        let changeDistribution = Cashu.splitIntoBase2Numbers(proofSum - amount)
        
        let combinedDistribution = (swapDistribution + changeDistribution).sorted()
        
        let deterministicFactors:(String, Int)?
        if let seed {
            deterministicFactors = (seed, activeKeyset.derivationCounter)
        } else {
            deterministicFactors = nil
        }
        
        let (outputs, bfs, secrets) = try Crypto.generateOutputs(amounts: combinedDistribution,
                                                             keysetID: activeKeyset.id,
                                                             deterministicFactors: deterministicFactors)
        
        // increment detset counter here (?)
        // FIXME: UGLY
        guard let new = self.keysets.firstIndex(where: { $0.id == activeKeyset.id }) else {
            fatalError()
        }
        activeKeyset.derivationCounter += outputs.count
        self.keysets[new] = activeKeyset
        
        let swapRequest = SwapRequest(inputs: proofs, outputs: outputs)
        let swapResponse = try await Network.post(url: self.url.appending(path: "/v1/swap"),
                                                  body: swapRequest,
                                                  expected: SwapResponse.self)
        
        var newProofs = try Crypto.unblindPromises(swapResponse.signatures,
                                                   blindingFactors: bfs,
                                                   secrets: secrets,
                                                   keyset: activeKeyset)
        var sendProofs = [Proof]()
        for n in swapDistribution {
            if let index = newProofs.firstIndex(where: {$0.amount == n}) {
                sendProofs.append(newProofs[index])
                newProofs.remove(at: index)
            }
        }
        
        return (sendProofs, newProofs)
    }
    
    // MARK: - RESTORE
    
    func restore(with seed:String, batchSize:Int = 10) async throws -> [Proof] {
        fatalError()
    }
    
    // MARK: - MISC
    
    func activeKeysetForUnit(_ unit:String) -> Keyset? {
        self.keysets.first(where: {
            $0.active == true &&
            $0.unit == unit
        })
    }
}

public enum Cashu {
    
}

extension Array where Element == Mint {
    func restore(with seed:String, batchSize:Int = 10) async throws -> [Proof] {
        // call mint.restore on each of the mints
        fatalError()
    }
    
    func getQuote(request:QuoteRequest) async throws -> [Quote] {
        // intended for melt quote request before MPP
        fatalError()
    }
    
    func melt(quote:Quote, proofs:[Proof]) async throws -> [Proof] {
        // intended for multi nut payment (MPP)
        // check input proofs against mint info and keysets
        // make sure quote is Bolt11
        fatalError()
    }
}
