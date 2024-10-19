import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

public enum CashuSwift {
    
    // MARK: - MINT INITIALIZATION
    
    public static func loadMint<T: MintRepresenting>(url:URL, type:T.Type = Mint.self) async throws -> T {
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            var new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.keysetID.makeURLSafe())"),
                                             expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        return T(url: url, keysets: keysetsWithKeys)
    }
    
    public static func loadInfoFromMint(_ mint:MintRepresenting) async throws -> MintInfo? {
        let mintInfoData = try await Network.get(url: mint.url.appending(path: "v1/info"))!
        
        if let info = try? JSONDecoder().decode(MintInfo0_16.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo0_15.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo.self, from: mintInfoData) {
            return info
        } else {
            logger.warning("Could not parse mint info of \(mint.url.absoluteString) to any known version.")
            return nil
        }
    }
    
    public static func update(_ mint: inout MintRepresenting) async throws {
        let mintURL = mint.url  // Create a local copy of the URL
        let remoteKeysetList = try await Network.get(url: mintURL.appending(path: "/v1/keysets"),
                                                     expected: KeysetList.self)
        
        let remoteIDs = remoteKeysetList.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        let localIDs = mint.keysets.reduce(into: [String:Bool]()) { partialResult, keyset in
            partialResult[keyset.keysetID] = keyset.active
        }
        
        logger.debug("Updating local representation of mint \(mintURL)...")
        
        if remoteIDs != localIDs {
            logger.debug("List of keysets changed.")
            var keysetsWithKeys = [Keyset]()
            for keyset in remoteKeysetList.keysets {
                var new = keyset
                new.keys = try await Network.get(url: mintURL.appending(path: "/v1/keys/\(keyset.keysetID.makeURLSafe())"),
                                                 expected: KeysetList.self).keysets[0].keys
                keysetsWithKeys.append(new)
            }
            mint.keysets = keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
        }
    }
    
    // MARK: - GET QUOTE
    /// Get a quote for minting or melting tokens from the mint
    public static func getQuote(mint:MintRepresenting, quoteRequest:QuoteRequest) async throws -> Quote {
        var url = mint.url
        
        guard mint.keysets.contains(where: { $0.unit == quoteRequest.unit }) else {
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
    public static func issue(for quote:Quote,
                             on mint:MintRepresenting,
                             seed:String? = nil,
                             preferredDistribution:[Int]? = nil) async throws -> [ProofRepresenting] {
        
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
            distribution = CashuSwift.splitIntoBase2Numbers(requestDetail.amount)
        }
        
        guard var keyset = mint.keysets.first(where: { $0.active == true &&
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
        let promises = try await Network.post(url: mint.url.appending(path: "/v1/mint/bolt11"),
                                              body: mintRequest,
                                              expected: Bolt11.MintResponse.self)
                    
        let proofs = try Crypto.unblindPromises(promises.signatures,
                                                blindingFactors: outputs.blindingFactors,
                                                secrets: outputs.secrets,
                                                keyset: keyset)
        
        return proofs
    }
    
    // MARK: - SEND
    
    public static func send(mint:MintRepresenting,
                            proofs:[ProofRepresenting],
                            amount:Int? = nil,
                            seed:String? = nil,
                            memo:String? = nil) async throws -> (token:Token,
                                                        change:[ProofRepresenting]) {
        
        let proofSum = sum(proofs)
        let amount = amount ?? proofSum
        
        guard amount <= proofSum else {
            throw CashuError.insufficientInputs("amount must not be larger than input proofs")
        }
        
//        let _proofs:[Proof] = normalize(proofs)
        
        let sendProofs:[ProofRepresenting]
        let changeProofs:[ProofRepresenting]
        
        if proofSum == amount {
            sendProofs = proofs
            changeProofs = []
        } else {
            let (new, change) = try await swap(mint: mint, proofs: proofs, amount: amount)
            sendProofs = new
            changeProofs = change
        }
        
        let units = try units(for: sendProofs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("units needs to contain exactly ONE entry, more means multi unit, less means none found - no bueno")
        }

        let proofContainer = ProofContainer(mint: mint.url.absoluteString, proofs: normalize(sendProofs))
        let token = Token(token: [proofContainer], memo: memo, unit: units.first)
        
        return (token, changeProofs)
    }
    
    // MARK: - RECEIVE
    public static func receive(mint:MintRepresenting, token:Token,
                        seed:String? = nil) async throws -> [ProofRepresenting] {
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.token.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.token.first!.mint != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.token.first?.proofs,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        return try await swap(mint:mint, proofs: inputProofs).new
    }
    
    // MARK: - MELT
    public static func melt(mint:MintRepresenting,
                            quote:Quote,
                            proofs:[ProofRepresenting],
                            seed:String? = nil,
                            timeout:Double = 600) async throws -> (paid:Bool, change:[ProofRepresenting]) {
        
        guard let quote = quote as? Bolt11.MeltQuote else {
            throw CashuError.typeMismatch("you need to pass a Bolt11 melt quote to this function, nothing else is supported yet.")
        }
        
        let lightningFee:Int = quote.feeReserve
        let inputFee:Int = try calculateFee(for: proofs, of: mint)
        let targetAmount = quote.amount + lightningFee + inputFee
        
        guard sum(proofs) >= targetAmount else {
            throw CashuError.insufficientInputs("Input sum does cover total amount needed: \(targetAmount)")
        }
        
        logger.debug("Attempting melt with quote amount: \(quote.amount), lightning fee reserve: \(lightningFee), input fee: \(inputFee).")
        
        let meltRequest:Bolt11.MeltRequest
        var change = [Proof]()
        
        guard let units = try? units(for: proofs, of: mint), units.count == 1 else {
            throw CashuError.unitError("Could not determine singular unit for input proofs.")
        }
        
        guard var keyset = activeKeysetForUnit(units.first!, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit \(units)")
        }
        
        var deterministicFactors:(seed:String, counter:Int)? = nil
        
        if let seed {
            deterministicFactors = (seed, keyset.derivationCounter)
        }
        
        let overpayed = sum(proofs) - quote.amount - inputFee
        let blankDistribution = Array(repeating: 0, count: calculateNumberOfBlankOutputs(overpayed))
        
        let (blankOutputs, blindingFactors, secrets) = try Crypto.generateOutputs(amounts: blankDistribution,
                                                                                  keysetID: keyset.keysetID,
                                                                                  deterministicFactors: deterministicFactors)
        keyset.derivationCounter += blankOutputs.count
        
        if blankOutputs.isEmpty {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: normalize(proofs), outputs: nil)
        } else {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: normalize(proofs), outputs: blankOutputs)
        }
        
        
        // TODO: HANDLE TIMEOUT MORE EXPLICITLY
        
        let meltResponse:Bolt11.MeltQuote
        
        
        meltResponse = try await Network.post(url: mint.url.appending(path: "/v1/melt/bolt11"),
                                              body: meltRequest,
                                              expected: Bolt11.MeltQuote.self,
                                              timeout: timeout)
        
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
    public static func swap(mint:MintRepresenting,
                            proofs:[ProofRepresenting],
                            amount:Int? = nil,
                            seed:String? = nil,
                            preferredReturnDistribution:[Int]? = nil) async throws -> (new:[ProofRepresenting],
                                                                         change:[ProofRepresenting]) {
        let fee = try calculateFee(for: proofs, of: mint)
        let proofSum = sum(proofs)
        
        let returnAmount:Int
        let changeAmount:Int
        
        if let amount {
            if proofSum >= amount + fee {
                returnAmount = amount
                changeAmount = proofSum - returnAmount - fee
            } else {
                throw CashuError.insufficientInputs("SWAP: sum of proofs (\(proofSum)) is less than amount (\(amount)) + fees (\(fee))")
            }
        } else {
            returnAmount = proofSum - fee
            changeAmount = 0
        }
        
        // the number of units from potentially mutliple keysets across input proofs must be 1:
        // less than 1 would mean no matching keyset/unit
        // more than one would imply multiple unit input proofs, which is not supported
        
        let units = try units(for: proofs, of: mint)
        
        guard units.count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        guard let activeKeyset = activeKeysetForUnit(units.first!, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("no active keyset could be found for unit \(String(describing: units.first))")
        }
        
        // TODO: implement true output selection
        
        let swapDistribution = CashuSwift.splitIntoBase2Numbers(returnAmount)
        let changeDistribution:[Int]
        
        if let preferredReturnDistribution {
            // TODO: CHECK THAT AMOUNTS ARE ONLY VALID INTEGERS
            let preferredReturnDistributionSum = preferredReturnDistribution.reduce(0, +)
            guard preferredReturnDistribution.reduce(0, +) == changeAmount else {
                throw CashuError.preferredDistributionMismatch(
                """
                preferredReturnDistribution does not add up to expected change amount.
                proof sum: \(proofSum), return amount: \(returnAmount), change amount: \(changeAmount), fees: \(fee), preferred distr sum: \(preferredReturnDistributionSum)
                """)
            }
            changeDistribution = preferredReturnDistribution
        } else {
            changeDistribution = CashuSwift.splitIntoBase2Numbers(changeAmount)
        }
        
        let combinedDistribution = (swapDistribution + changeDistribution).sorted()
        
        let deterministicFactors:(String, Int)?
        if let seed {
            deterministicFactors = (seed, activeKeyset.derivationCounter)
        } else {
            deterministicFactors = nil
        }
        
        let (outputs, bfs, secrets) = try Crypto.generateOutputs(amounts: combinedDistribution,
                                                                 keysetID: activeKeyset.keysetID,
                                                                 deterministicFactors: deterministicFactors)
        
        let internalProofs = normalize(proofs)
        let swapRequest = SwapRequest(inputs: internalProofs, outputs: outputs)
        let swapResponse = try await Network.post(url: mint.url.appending(path: "/v1/swap"),
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
    public static func restore(mint:MintRepresenting, with seed:String,
                        batchSize:Int = 10) async throws -> [(ProofRepresenting, String)] {
        // no need to check validity of seed as function would otherwise crash during first det sec generation
        var restoredProofs = [(ProofRepresenting, String)]()
        for var keyset in mint.keysets {
            logger.info("Attempting restore for keyset: \(keyset.keysetID) of mint: \(mint.url.absoluteString)")
            let (proofs, _, lastMatchCounter) = try await restoreForKeyset(mint:mint, keyset:keyset, with: seed, batchSize: batchSize)
            print("last match counter: \(String(describing: lastMatchCounter))")
            
            // if we dont have any restorable proofs on this keyset, move on to the next
            if proofs.isEmpty {
                logger.debug("No ecash to restore for keyset \(keyset.keysetID).")
                continue
            }
            
            // FIXME: ugly
            keyset.derivationCounter = lastMatchCounter + 1
            
            let states = try await check(proofs, mint: mint) // ignores pending but should not
            guard states.count == proofs.count else {
                throw CashuError.restoreError("unable to filter for unspent ecash during restore")
            }
            var spendableProofs = [ProofRepresenting]()
            for i in 0..<states.count {
                if states[i] == .unspent { spendableProofs.append(proofs[i]) }
            }
            
            spendableProofs.forEach({ restoredProofs.append(($0, keyset.unit)) })
            logger.info("Found \(spendableProofs.count) spendable proofs for keyset \(keyset.keysetID)")
        }
        return restoredProofs
    }
    
    static func restoreForKeyset(mint:MintRepresenting,
                                 keyset:Keyset,
                                 with seed:String,
                                 batchSize:Int) async throws -> (proofs:[ProofRepresenting],
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
            let response = try await Network.post(url: mint.url.appending(path: "/v1/restore"),
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
    
    public static func check(_ proofs:[ProofRepresenting], mint:MintRepresenting) async throws -> [Proof.ProofState] {
        let ys = try proofs.map { proof in
            try Crypto.secureHashToCurve(message: proof.secret).stringRepresentation
        }
        
        let request = Proof.StateCheckRequest(Ys: ys)
        let response = try await Network.post(url: mint.url.appending(path: "/v1/checkstate"),
                                              body: request,
                                              expected: Proof.StateCheckResponse.self)
        return response.states.map { entry in
            entry.state
        }
    }
    
    public static func check(_ proofs:[ProofRepresenting], url:URL) async throws -> [Proof.ProofState] {
        let ys = try proofs.map { proof in
            try Crypto.secureHashToCurve(message: proof.secret).stringRepresentation
        }
        
        let request = Proof.StateCheckRequest(Ys: ys)
        let response = try await Network.post(url: url.appending(path: "/v1/checkstate"),
                                              body: request,
                                              expected: Proof.StateCheckResponse.self)
        return response.states.map { entry in
            entry.state
        }
    }

    // MARK: - MISC
    
    static func normalize(_ proofs:[ProofRepresenting]) -> [Proof] {
        proofs.map({ CashuSwift.Proof($0) })
    }
    
    static func sum(_ proofRepresenting:[ProofRepresenting]) -> Int {
        proofRepresenting.reduce(0) { $0 + $1.amount }
    }
    
    public static func pick(_ proofs: [ProofRepresenting],
                            amount: Int,
                            mint: MintRepresenting,
                            ignoreFees: Bool = false) -> (selected: [ProofRepresenting],
                                                          change: [ProofRepresenting],
                                                          fee: Int)? {
        // Checks ...

        // Sort proofs in descending order
        var sortedProofs = proofs.sorted(by: { $0.amount > $1.amount })
        var currentProofSum = 0
        var totalFeePPK = 0

        var selected = [ProofRepresenting]()

        while !sortedProofs.isEmpty {
            let proof = sortedProofs.removeFirst()
            selected.append(proof)

            let feePPK = mint.keysets.first(where: { $0.keysetID == proof.keysetID })?.inputFeePPK ?? 0
            totalFeePPK += feePPK
            currentProofSum += proof.amount

            let totalFee = ignoreFees ? 0 : ((totalFeePPK + 999) / 1000)
            if currentProofSum >= (amount + totalFee) {
                // Remaining proofs are the change
                let change = sortedProofs
                return (selected, change, totalFee)
            }
        }
        return nil
    }

    
    static func selectProofsToSumTarget(proofs: [ProofRepresenting], targetAmount: Int) -> ([ProofRepresenting], [ProofRepresenting])? {
        guard targetAmount > 0 else {
            return nil
        }
        
        let n = proofs.count
        let totalSubsets = 1 << n  // Total number of subsets (2^n)

        for subset in 0..<totalSubsets {
            var sum = 0
            var selectedProofs = [ProofRepresenting]()
            var remainingProofs = [ProofRepresenting]()
            
            for i in 0..<n {
                if (subset & (1 << i)) != 0 {
                    sum += proofs[i].amount
                    selectedProofs.append(proofs[i])
                } else {
                    remainingProofs.append(proofs[i])
                }
            }
            
            if sum == targetAmount {
                return (selectedProofs, remainingProofs)
            }
        }
        
        // No subset sums up to targetAmount
        return nil
    }
    
    public static func calculateFee(for proofs: [ProofRepresenting], of mint:MintRepresenting) throws -> Int {
        var sumFees = 0
        for proof in proofs {
            if let feeRate = mint.keysets.first(where: { $0.keysetID == proof.keysetID })?.inputFeePPK {
                sumFees += feeRate
            } else {
                throw CashuError.feeCalculationError("trying to calculate fees for proofs of keyset \(proof.keysetID) which does not seem to be associated with mint \(mint.url.absoluteString).")
            }
        }
        return (sumFees + 999) / 1000
    }
    
    public static func activeKeysetForUnit(_ unit:String, mint:MintRepresenting) -> Keyset? {
        mint.keysets.first(where: {
            $0.active == true &&
            $0.unit == unit
        })
    }
    
    /// Returns a set of units represented in the proofs
    static func units(for proofs:[ProofRepresenting], of mint:MintRepresenting) throws -> Set<String> {
        guard !mint.keysets.isEmpty, !proofs.isEmpty else {
            fatalError("empty inputs to function .check() proofs: \(proofs.count), keysete\(mint.keysets.count)")
        }
        
        var units:Set<String> = []
        for proof in proofs {
            if let keysetForID = mint.keysets.first(where: { $0.keysetID == proof.keysetID }) {
                units.insert(keysetForID.unit)
            } else {
                // found a proof that belongs to a keyset not from this mint
                throw CashuError.unitError("proofs from keyset \(proof.keysetID)  do not belong to mint \(mint.url.absoluteString)")
            }
        }
        return units
    }
}

extension Array where Element : MintRepresenting {
    
    // docs: deprecated and only for redeeming legace V3 multi mint token
    public func receive(token:CashuSwift.Token,
                        seed:String? = nil) async throws -> Dictionary<String, [ProofRepresenting]> {
        
        guard token.token.count == self.count else {
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
        
        var tokenStates = [CashuSwift.Proof.ProofState]()
        for token in token.token {
            let mint = self.first(where: { $0.url.absoluteString == token.mint })!
            tokenStates.append(contentsOf: try await CashuSwift.check(token.proofs, mint: mint))
        }
        
        guard tokenStates.allSatisfy({ $0 == .unspent }) else {
            logger.error("CashuSwift does not allow you to redeem a multi mint token that is only partially spendable.")
            throw CashuError.partiallySpentToken
        }
        
        var proofs = Dictionary<String, [ProofRepresenting]>()
        for token in token.token {
            let mint = self.first(where: { $0.url.absoluteString == token.mint })!
            let singleMintToken = CashuSwift.Token(token: [token])
            proofs[mint.url.absoluteString] = try await CashuSwift.receive(mint: mint, token: singleMintToken)
        }
        return proofs
    }
    
    public func restore(with seed:String, batchSize:Int = 10) async throws -> [(proof:ProofRepresenting, unit:String)] {
        // call mint.restore on each of the mints
        var restoredProofs = [(ProofRepresenting, String)]()
        for mint in self {
            let proofs = try await CashuSwift.restore(mint:mint, with: seed, batchSize: batchSize)
            restoredProofs.append(contentsOf: proofs)
        }
        return restoredProofs
    }

//    public func getQuote(request:QuoteRequest) async throws -> [Quote] {
//        // intended for melt quote request before MPP
//        fatalError()
//    }
//    
//    public func melt(quotes:[Quote], proofs:[Proof]) async throws -> [Proof] {
//        // intended for multi nut payment (MPP)
//        // check input proofs against mint info and keysets
//        // make sure quote is Bolt11
//        fatalError()
//    }
    
}

extension Array where Element : ProofRepresenting {
    
    public var sum: Int {
        self.reduce(0) { $0 + $1.amount }
    }
    
    public func pick(_ amount:Int) -> (picked:[ProofRepresenting], change:[ProofRepresenting])? {
        CashuSwift.selectProofsToSumTarget(proofs: self, targetAmount: amount)
    }
    
    func internalize() -> [CashuSwift.Proof] {
        map({ CashuSwift.Proof($0) })
    }
}
