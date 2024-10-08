import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension Mint {
    
    // MARK: - GET QUOTE
    /// Get a quote for minting or melting tokens from the mint
    public func getQuote(quoteRequest:QuoteRequest) async throws -> Quote {
        var url = self.url
        
        guard self.keysets.contains(where: { $0.unit == quoteRequest.unit }) else {
            throw CashuError.noKeysetForUnit("No keyset on mint \(url.absoluteString) for unit \(quoteRequest.unit.uppercased()).")
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
            throw CashuError.typeMismatch("User tried to call getQuote using unsupported QuoteRequest type.")
        }
    }
    
    // MARK: - ISSUE
    
    /// After paying the quote amount to the mint, use this function to issue the actual ecash as a list of [`String`]s
    /// Leaving `seed` empty will give you proofs from non-deterministic outputs which cannot be recreated from a seed phrase backup
    public func issue(for quote:Quote,
                      seed:String? = nil,
                      preferredDistribution:[Int]? = nil) async throws -> [Proof] {
        
        guard let quote = quote as? Bolt11.MintQuote else {
            throw CashuError.typeMismatch("Quote to issue proofs for was not a Bolt11.MintQuote")
        }
        
        guard let requestDetail = quote.requestDetail else {
            throw CashuError.missingRequestDetail("You need to set requestDetail associated with the quote.")
        }
        
        var distribution:[Int]
        
        if let preferredDistribution = preferredDistribution {
            guard preferredDistribution.reduce(0, +) == requestDetail.amount else {
                throw CashuError.preferredDistributionMismatch("Specified preferred distribution does not add up to the same amount as the quote.")
            }
            distribution = preferredDistribution
        } else {
            distribution = Cashu.splitIntoBase2Numbers(requestDetail.amount)
        }
        
        guard let keyset = self.keysets.first(where: { $0.active == true &&
                                                       $0.unit == requestDetail.unit }) else {
            throw CashuError.noActiveKeysetForUnit("Could not determine an ACTIVE keyset for this unit \(requestDetail.unit.uppercased())")
        }
        
        // tuple for outputs, blindingfactors, secrets
        // swift does not allow uninitialized tuple declaration
        var outputs = (outputs:[Output](), blindingFactors:[""], secrets:[""])
        if let seed = seed {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: keyset.keysetID,
                                                 deterministicFactors: (seed: seed,
                                                                        counter: keyset.derivationCounter))
            keyset.derivationCounter += outputs.outputs.count
        } else {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: keyset.keysetID)
        }
        
        let mintRequest = Bolt11.MintRequest(quote: quote.quote, outputs: outputs.outputs)
        
        // TODO: PARSE COMMON ERRORS
        // TODO: CHECK FOR DUPLICATE OUTPUT ERROR, RETRY ACC TO `skipDuplicateOutputs`
        let promises = try await Network.post(url: self.url.appending(path: "/v1/mint/bolt11"),
                                              body: mintRequest,
                                              expected: Bolt11.MintResponse.self)
                    
        let proofs = try Crypto.unblindPromises(promises.signatures,
                                                blindingFactors: outputs.blindingFactors,
                                                secrets: outputs.secrets,
                                                keyset: keyset)
        
        return proofs
    }
    
    // MARK: - SEND
    
    public func send(proofs:[Proof],
                     amount:Int? = nil,
                     seed:String? = nil,
                     memo:String? = nil) async throws -> (token:Token,
                                                        change:[Proof]) {
        
        let amount = amount ?? proofs.sum
        
        guard amount <= proofs.sum else {
            throw CashuError.insufficientInputs("amount must not be larger than input proofs")
        }
        
        let sendProofs:[Proof]
        let changeProofs:[Proof]
        
        if let selection = proofs.select(amount: amount) {
            sendProofs = selection.selected
            changeProofs = selection.rest
        } else {
            let swapped = try await swap(proofs: proofs, amount: amount)
            sendProofs = swapped.new
            changeProofs = swapped.change
        }
        
        let units = try units(for: sendProofs)
        guard units.count == 1 else {
            throw CashuError.unitError("units needs to contain exactly ONE entry, more means multi unit, less means none found - no bueno")
        }
        
        let proofContainer = ProofContainer(mint: self.url.absoluteString, proofs: sendProofs)
        let token = Token(token: [proofContainer], memo: memo, unit: units.first)
        
        return (token, changeProofs)
    }
    
    // MARK: - RECEIVE
    // TODO: NEEDS TO BE ABLE TO HANDLE P2PK LOCKED ECASH
    public func receive(token:Token,
                        seed:String? = nil) async throws -> [Proof] {
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.token.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.token.first!.mint != self.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.token.first?.proofs,
                try self.units(for: inputProofs).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        return try await self.swap(proofs: inputProofs).new
    }
    
    // MARK: - MELT
    // should block until the the payment is made OR timeout reached
    public func melt(quote:Quote,
                     proofs:[Proof],
                     seed:String? = nil) async throws -> (paid:Bool, change:[Proof]) {
        
        guard let quote = quote as? Bolt11.MeltQuote else {
            throw CashuError.typeMismatch("you need to pass a Bolt11 melt quote to this function, nothing else is supported yet.")
        }
        
        let lightningFee:Int = quote.feeReserve
        let inputFee:Int = try self.calculateFee(for: proofs)
        let targetAmount = quote.amount + lightningFee + inputFee
        
        guard proofs.sum >= targetAmount else {
            throw CashuError.insufficientInputs("Input sum does cover total amount needed: \(targetAmount)")
        }
        
        logger.debug("Attempting melt with quote amount: \(quote.amount), lightning fee reserve: \(lightningFee), input fee: \(inputFee).")
        
        let meltRequest:Bolt11.MeltRequest
        var change = [Proof]()
        
        guard let units = try? units(for: proofs), units.count == 1 else {
            throw CashuError.unitError("Could not determine singular unit for input proofs.")
        }
        
        guard let keyset = activeKeysetForUnit(units.first!) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit \(units)")
        }
        
        var deterministicFactors:(seed:String, counter:Int)? = nil
        
        if let seed {
            deterministicFactors = (seed, keyset.derivationCounter)
        }
        
        let overpayed = proofs.sum - quote.amount - inputFee
        let blankDistribution = Array(repeating: 0, count: calculateNumberOfBlankOutputs(overpayed))
        
        let (blankOutputs, blindingFactors, secrets) = try Crypto.generateOutputs(amounts: blankDistribution,
                                                                                  keysetID: keyset.keysetID,
                                                                                  deterministicFactors: deterministicFactors)
        keyset.derivationCounter += blankOutputs.count
        
        if blankOutputs.isEmpty {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: proofs, outputs: nil)
        } else {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: proofs, outputs: blankOutputs)
        }
        
        
        // TODO: HANDLE TIMEOUT MORE EXPLICITLY
        
        let meltResponse:Bolt11.MeltQuote
        
        
        meltResponse = try await Network.post(url: self.url.appending(path: "/v1/melt/bolt11"),
                                              body: meltRequest,
                                              expected: Bolt11.MeltQuote.self)
        
        if let promises = meltResponse.change {
            guard promises.count <= blankOutputs.count else {
                throw Crypto.Error.unblinding("could not unblind blank outputs for fee return")
            }
            
            change = try Crypto.unblindPromises(promises,
                                                blindingFactors: Array(blindingFactors.prefix(promises.count)),
                                                secrets: Array(secrets.prefix(promises.count)),
                                                keyset: keyset)
        }
        
        if let paid = meltResponse.paid {
            return (paid, change)
        } else if let state = meltResponse.state {
            switch state {
            case .paid:
                return (true, change)
            case .unpaid:
                return (false, change)
            case .pending:
                return (false, change)
            }
        } else {
            fatalError("could not find quote state information in response.")
        }
    }
    
    // MARK: - SWAP
    public func swap(proofs:[Proof],
                     amount:Int? = nil,
                     seed:String? = nil,
                     preferredReturnDistribution:[Int]? = nil) async throws -> (new:[Proof],
                                                                         change:[Proof]) {
        let fee = try calculateFee(for: proofs)
        let proofSum = proofs.sum
        
        let returnAmount:Int
        let changeAmount:Int
        
        if let amount {
            if proofSum >= amount + fee {
                returnAmount = amount
                changeAmount = proofSum - returnAmount - fee
            } else {
                throw CashuError.insufficientInputs("sum of proofs (\(proofSum)) is less than amount (\(amount)) + fees (\(fee))")
            }
        } else {
            returnAmount = proofSum - fee
            changeAmount = 0
        }
        
        // the number of units from potentially mutliple keysets across input proofs must be 1:
        // less than 1 would mean no matching keyset/unit
        // more than one would imply multiple unit input proofs, which is not supported
        
        let units = try units(for: proofs)
        
        guard units.count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        guard let activeKeyset = activeKeysetForUnit(units.first!) else {
            throw CashuError.noActiveKeysetForUnit("no active keyset could be found for unit \(String(describing: units.first))")
        }
        
        // TODO: implement true output selection
        
        let swapDistribution = Cashu.splitIntoBase2Numbers(returnAmount)
        let changeDistribution:[Int]
        
        if let preferredReturnDistribution {
            // TODO: CHECK THAT AMOUNTS ARE ONLY VALID INTEGERS
            guard preferredReturnDistribution.reduce(0, +) == changeAmount else {
                throw CashuError.preferredDistributionMismatch("preferredReturnDistribution does not add up to expected change amount")
            }
            changeDistribution = preferredReturnDistribution
        } else {
            changeDistribution = Cashu.splitIntoBase2Numbers(changeAmount)
        }
        
        let combinedDistribution = (swapDistribution + changeDistribution).sorted()
        
        let deterministicFactors:(String, Int)?
        if let seed {
            deterministicFactors = (seed, activeKeyset.derivationCounter)
            activeKeyset.derivationCounter += combinedDistribution.count
        } else {
            deterministicFactors = nil
        }
        
        let (outputs, bfs, secrets) = try Crypto.generateOutputs(amounts: combinedDistribution,
                                                                 keysetID: activeKeyset.keysetID,
                                                                 deterministicFactors: deterministicFactors)
        
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
    // TODO: should increase batch size, default 10 is way to small
    public func restore(with seed:String,
                        batchSize:Int = 10) async throws -> [Proof] {
        // no need to check validity of seed as function would otherwise crash during first det sec generation
        var restoredProofs = [Proof]()
        for keyset in self.keysets {
            logger.info("Attempting restore for keyset: \(keyset.keysetID) of mint: \(self.url.absoluteString)")
            let (proofs, _, lastMatchCounter) = try await restoreForKeyset(keyset, with: seed, batchSize: batchSize)
            print("last match counter: \(String(describing: lastMatchCounter))")
            
            // if we dont have any restorable proofs on this keyset, move on to the next
            if proofs.isEmpty {
                logger.debug("No ecash to restore for keyset \(keyset.keysetID).")
                continue
            }
            
            // FIXME: ugly
            keyset.derivationCounter = lastMatchCounter + 1
            
            let states = try await check(proofs)// ignores pending but should not
            guard states.count == proofs.count else {
                throw CashuError.restoreError("unable to filter for unspent ecash during restore")
            }
            var spendableProofs = [Proof]()
            for i in 0..<states.count {
                if states[i] == .unspent { spendableProofs.append(proofs[i]) }
            }
            
            restoredProofs.append(contentsOf: spendableProofs)
            logger.info("Found \(spendableProofs.count) spendable proofs for keyset \(keyset.keysetID)")
        }
        return restoredProofs
    }
    
    func restoreForKeyset(_ keyset:Keyset, 
                          with seed:String,
                          batchSize:Int) async throws -> (proofs:[Proof],
                                                          totalRestored:Int,
                                                          lastMatchCounter:Int) {
        var proofs = [Proof]()
        var emtpyResponses = 0
        var currentCounter = 0
        var batchLastMatchIndex = 0
        let emptyRuns = 2
        while emtpyResponses < emptyRuns {
            let (outputs,
                 blindingFactors,
                 secrets) = try Crypto.generateOutputs(amounts: Array(repeating: 1, count: batchSize),
                                                       keysetID: keyset.keysetID,
                                                       deterministicFactors: (seed: seed,
                                                                              counter: currentCounter))
            
            
            let request = RestoreRequest(outputs: outputs)
            let response = try await Network.post(url: self.url.appending(path: "/v1/restore"),
                                                  body: request,
                                                  expected: RestoreResponse.self)
            
            currentCounter += batchSize
            
            if response.signatures.isEmpty {
                emtpyResponses += 1
                continue
            } else {
                //reset counter to ensure they are CONSECUTIVE empty responses
                emtpyResponses = 0
                batchLastMatchIndex = outputs.lastIndex(where: { oldOutput in
                    response.outputs.contains(where: {newOut in oldOutput.B_ == newOut.B_})
                }) ?? 0
            }
            var rs = [String]()
            var xs = [String]()
            for i in 0..<outputs.count {
                if response.outputs.contains(where: {$0.B_ == outputs[i].B_}) {
                    rs.append(blindingFactors[i])
                    xs.append(secrets[i])
                }
            }
            
            let batchProofs = try Crypto.unblindPromises(response.signatures,
                                                        blindingFactors: blindingFactors,
                                                        secrets: secrets,
                                                        keyset: keyset)
            proofs.append(contentsOf: batchProofs)
        }
        currentCounter -= (emptyRuns + 1) * batchSize
        currentCounter += batchLastMatchIndex
        if currentCounter < 0 { currentCounter = 0 }
        return (proofs, proofs.count, currentCounter)
    }
    
    public func check(_ proofs:[Proof]) async throws -> [Proof.ProofState] {
        guard try units(for: proofs).count == 1 else {
            throw CashuError.unitError("mixed input units to .chack() function.")
        }
        
        let ys = try proofs.map { proof in
            try Crypto.secureHashToCurve(message: proof.secret).stringRepresentation
        }
        
        let request = Proof.StateCheckRequest(Ys: ys)
        let response = try await Network.post(url: self.url.appending(path: "/v1/checkstate"),
                                              body: request,
                                              expected: Proof.StateCheckResponse.self)
        return response.states.map { entry in
            entry.state
        }
    }
    
    public func update() async throws {
        // load keysets, iterate over ids and active flag
        let remoteKeysetList = try await Network.get(url: self.url.appending(path: "/v1/keysets"),
                                                     expected: KeysetList.self)
        
        let remoteIDs = remoteKeysetList.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        let localIDs = self.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        logger.debug("Updating local representation of mint \(self.url)...")
        
        if remoteIDs != localIDs {
            logger.debug("List of keysets changed.")
            var keysetsWithKeys = [Keyset]()
            for keyset in remoteKeysetList.keysets {
                let new = keyset
                new.keys = try await Network.get(url: self.url.appending(path: "/v1/keys/\(keyset.keysetID.makeURLSafe())"),
                                                    expected: KeysetList.self).keysets[0].keys
                keysetsWithKeys.append(new)
            }
            self.keysets = keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
        }
        
        // TODO: UPDATE INFO AS WELL
    }
    
    // MARK: - MISC
    
    func activeKeysetForUnit(_ unit:String) -> Keyset? {
        self.keysets.first(where: {
            $0.active == true &&
            $0.unit == unit
        })
    }
    
    func units(for proofs:[Proof]) throws -> Set<String> {
        guard !self.keysets.isEmpty, !proofs.isEmpty else {
            fatalError("empty inputs to function .check() proofs: \(proofs.count), keysete\(self.keysets.count)")
        }
        
        var units:Set<String> = []
        for proof in proofs {
            if let keysetForID = self.keysets.first(where: { $0.keysetID == proof.keysetID }) {
                units.insert(keysetForID.unit)
            } else {
                // found a proof that belongs to a keyset not from this mint
                throw CashuError.unitError("proofs from keyset \(proof.keysetID)  do not belong to mint \(self.url.absoluteString)")
            }
        }
        return units
    }
}

public enum Cashu {
    
}

extension Array where Element == Mint {
    
    // docs: deprecated and only for redeeming legace V3 multi mint token
    public func receive(token:Token,
                        seed:String? = nil) async throws -> [Proof] {
        
        guard token.token.count != self.count else {
            logger.error("Number of mints in list does not match number of mints in token.")
            throw CashuError.invalidToken
        }
        
        // strictly make sure that mint URLs match
        guard token.token.allSatisfy({ token in
            self.contains(where: { token.mint == $0.url.absoluteString })
        }) else {
            logger.error("URLs from token do not match mint list.")
            throw CashuError.invalidToken
        }
        
        var tokenStates = [Proof.ProofState]()
        for token in token.token {
            let mint = self.first(where: { $0.url.absoluteString == token.mint })!
            tokenStates.append(contentsOf: try await mint.check(token.proofs))
        }
        
        guard tokenStates.allSatisfy({ $0 == .unspent }) else {
            logger.error("CashuSwift does not allow you to redeem a multi mint token that is only partially spendable.")
            throw CashuError.partiallySpentToken
        }
        
        var proofs = [Proof]()
        for token in token.token {
            let mint = self.first(where: { $0.url.absoluteString == token.mint })!
            let singleMintToken = Token(token: [token])
            proofs.append(contentsOf: try await mint.receive(token: singleMintToken))
        }
        return proofs
    }
    
    public func updateAll() async throws {
        for mint in self {
            try await mint.update()
        }
    }
    
    public func restore(with seed:String, batchSize:Int = 10) async throws -> [Proof] {
        // call mint.restore on each of the mints
        var restoredProofs = [Proof]()
        for mint in self {
            let proofs = try await mint.restore(with: seed, batchSize: batchSize)
            restoredProofs.append(contentsOf: proofs)
        }
        return restoredProofs
    }
    
    public func getQuote(request:QuoteRequest) async throws -> [Quote] {
        // intended for melt quote request before MPP
        fatalError()
    }
    
    public func melt(quotes:[Quote], proofs:[Proof]) async throws -> [Proof] {
        // intended for multi nut payment (MPP)
        // check input proofs against mint info and keysets
        // make sure quote is Bolt11
        fatalError()
    }
    
}

extension Array where Element == Proof {
    public func select(amount: Int) -> (selected: [Proof], rest: [Proof])? {
        func backtrack(_ index: Int, _ currentSum: Int, _ currentSelection: [Proof]) -> [Proof]? {
            if currentSum == amount {
                return currentSelection
            }
            if index >= self.count || currentSum > amount {
                return nil
            }
            
            if let result = backtrack(index + 1, currentSum + self[index].amount, currentSelection + [self[index]]) {
                return result
            }
            return backtrack(index + 1, currentSum, currentSelection)
        }
        
        if let selected = backtrack(0, 0, []) {
            let rest = self.filter { !selected.contains($0) }
            return (selected, rest)
        }
        
        return nil
    }
    
    public var sum:Int {
        self.reduce(0) { $0 + $1.amount }
    }
}
