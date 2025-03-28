import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

public enum CashuSwift {
    
    // MARK: - MINT INITIALIZATION
    
    /// Loads a mint from a given URL and retrieves its keysets
    /// - Parameters:
    ///   - url: The URL of the mint to load
    ///   - type: The type conforming to MintRepresenting protocol (defaults to Mint.self)
    /// - Returns: An initialized mint of type T
    /// - Throws: Network or decoding errors
    public static func loadMint<T: MintRepresenting>(url:URL, type:T.Type = Mint.self) async throws -> T {
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            var new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                             expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        return T(url: url, keysets: keysetsWithKeys)
    }
    
    /// Loads mint information in a backward compatible way (deprecated)
    /// - Parameter mint: The mint to load information from
    /// - Returns: Optional MintInfo object
    /// - Throws: Network or decoding errors
    @available(*, deprecated)
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
    
    /// Loads current mint information
    /// - Parameter mint: The mint to load information from
    /// - Returns: Mint.Info object containing current mint information
    /// - Throws: Network or decoding errors
    public static func loadInfo(of mint: MintRepresenting) async throws -> Mint.Info {
        return try await Network.get(url: mint.url.appending(path: "v1/info"),
                                     expected: Mint.Info.self)
    }
    
    /// Updates the local representation of a mint's keysets
    /// - Parameter mint: The mint to update
    /// - Throws: Network or decoding errors
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
                new.keys = try await Network.get(url: mintURL.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                                 expected: KeysetList.self).keysets[0].keys
                keysetsWithKeys.append(new)
            }
            mint.keysets = keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
        }
    }
    
    /// Gets updated keysets for a mint without modifying the mint
    /// - Parameter mint: The mint to get updated keysets for
    /// - Returns: Array of updated Keyset objects
    /// - Throws: Network or decoding errors
    public static func updatedKeysetsForMint(_ mint:MintRepresenting) async throws -> [Keyset] {
        let mintURL = mint.url
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
                new.keys = try await Network.get(url: mintURL.appending(path: "/v1/keys/\(keyset.keysetID.urlSafe)"),
                                                 expected: KeysetList.self).keysets[0].keys
                
                let detsecCounter = mint.keysets.first(where: {$0.keysetID == keyset.keysetID})?.derivationCounter ?? 0
                new.derivationCounter = detsecCounter
                keysetsWithKeys.append(new)
            }
            return keysetsWithKeys
        } else {
            logger.debug("No changes in list of keysets.")
            return mint.keysets
        }
    }
    
    // MARK: - GET QUOTE
    
    /// Gets a quote for minting or melting tokens from the mint.
    ///
    /// - Parameters:
    ///   - mint: The mint to request the quote from.
    ///   - quoteRequest: The quote request details, must be either:
    ///     - ``Bolt11/RequestMintQuote``: For minting new tokens.
    ///     - ``Bolt11/RequestMeltQuote``: For melting tokens to Lightning payment.
    /// - Returns: A ``Quote`` object containing the quote details and payment information.
    /// - Throws: ``CashuError/unitIsNotSupported(_:)`` if the requested unit isn't available.
    ///           ``CashuError/typeMismatch(_:)`` if an unsupported quote type is used.
    public static func getQuote(mint:MintRepresenting, quoteRequest:QuoteRequest) async throws -> Quote {
        var url = mint.url
        
        guard mint.keysets.contains(where: { $0.unit == quoteRequest.unit }) else {
            throw CashuError.unitIsNotSupported("No keyset on mint \(url.absoluteString) for unit \(quoteRequest.unit.uppercased()).")
        }
        
        switch quoteRequest {
        case let quoteRequest as Bolt11.RequestMintQuote:
            url.append(path: "/v1/mint/quote/bolt11")
            var result = try await Network.post(url: url,
                                                body: quoteRequest,
                                                expected: Bolt11.MintQuote.self)
            result.requestDetail = quoteRequest // simplifies working with quotes on the frontend
            return result
        case let quoteRequest as Bolt11.RequestMeltQuote:
            url.append(path: "/v1/melt/quote/bolt11")
            var response = try await Network.post(url: url,
                                                  body:quoteRequest,
                                                  expected: Bolt11.MeltQuote.self)
            response.quoteRequest = quoteRequest // simplifies working with quotes on the frontend
            return response
        default:
            throw CashuError.typeMismatch("User tried to call getQuote using unsupported QuoteRequest type.")
        }
    }
    
    // MARK: - ISSUE
    
    /// Issues ecash tokens after paying a quote amount to the mint
    /// - Parameters:
    ///   - quote: The quote to issue tokens for (must be a Bolt11.MintQuote)
    ///   - mint: The mint to issue tokens from
    ///   - seed: Optional seed for deterministic outputs. When provided, the proofs can be
    ///          restored from this seed if lost. Leave empty for non-deterministic outputs
    ///   - preferredDistribution: Optional specific distribution of token amounts. Must sum
    ///                           to the same amount as the quote. If not provided, amounts
    ///                           will be split into powers of 2
    /// - Returns: Array of ProofRepresenting objects representing the issued tokens
    /// - Throws: CashuError.typeMismatch if quote is not a Bolt11.MintQuote
    ///          CashuError.missingRequestDetail if quote lacks request details
    ///          CashuError.preferredDistributionMismatch if distribution doesn't match amount
    ///          CashuError.noActiveKeysetForUnit if no active keyset exists for the unit
    public static func issue(for quote:Quote,
                           on mint: MintRepresenting,
                           seed:String? = nil,
                           preferredDistribution:[Int]? = nil) async throws -> [some ProofRepresenting] {
        
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
        
        guard let activeKeyset = mint.keysets.first(where: { $0.active == true &&
                                                       $0.unit == requestDetail.unit }) else {
            throw CashuError.noActiveKeysetForUnit("Could not determine an ACTIVE keyset for this unit \(requestDetail.unit.uppercased())")
        }
        
        // tuple for outputs, blindingfactors, secrets
        // swift does not allow uninitialized tuple declaration
        var outputs = (outputs:[Output](), blindingFactors:[""], secrets:[""])
        if let seed = seed {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: activeKeyset.keysetID,
                                                 deterministicFactors: (seed: seed,
                                                                        counter: activeKeyset.derivationCounter))

            
            
            
        } else {
            outputs = try Crypto.generateOutputs(amounts: distribution,
                                                 keysetID: activeKeyset.keysetID)
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
                                                keyset: activeKeyset)
        
        return proofs
    }
    
    // MARK: - SEND
    
    /// Creates a token from proofs that can be sent to another user
    /// - Parameters:
    ///   - mint: The mint the proofs belong to
    ///   - proofs: Array of proofs to send
    ///   - amount: Optional specific amount to send. If nil, sends the sum of all proofs.
    ///            Must not be larger than the sum of input proofs
    ///   - seed: Optional seed for deterministic outputs. When provided, enables backup recovery
    ///   - memo: Optional memo to attach to the token for the recipient
    /// - Returns: Tuple containing:
    ///           - token: The Token object that can be sent to another user
    ///           - change: Array of change proofs if input amount was larger than requested
    /// - Throws: CashuError.insufficientInputs if amount is larger than proof sum
    ///          CashuError.unitError if proofs are from multiple units
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
            let (new, change) = try await swap(mint: mint, proofs: proofs, amount: amount, seed: seed)
            sendProofs = new
            changeProofs = change
        }
        
        let units = try units(for: sendProofs, of: mint)
        guard units.count == 1 else {
            throw CashuError.unitError("units needs to contain exactly ONE entry, more means multi unit, less means none found - no bueno")
        }
        
        let proofsPerMint = [mint.url.absoluteString: sendProofs]
        let token = Token(proofs: proofsPerMint,
                          unit: units.first ?? "sat",
                          memo: memo)
    
        
        return (token, changeProofs)
    }
    
    // MARK: - RECEIVE
    public static func receive(mint:MintRepresenting,
                               token:Token,
                               seed:String? = nil) async throws -> [ProofRepresenting] {
        // this should check whether proofs are from this mint and not multi unit FIXME: potentially wonky and not very descriptive
        guard token.proofsByMint.count == 1 else {
            logger.error("You tried to receive a token that either contains no proofs at all, or proofs from more than one mint.")
            throw CashuError.invalidToken
        }
        
        if token.proofsByMint.keys.first! != mint.url.absoluteString {
            logger.warning("Mint URL field from token does not seem to match this mints URL.")
        }
        
        guard let inputProofs = token.proofsByMint.first?.value,
              try units(for: inputProofs, of: mint).count == 1 else {
            throw CashuError.unitError("Proofs to swap are either of mixed unit or foreign to this mint.")
        }
        
        return try await swap(mint:mint, proofs: inputProofs, seed: seed).new
    }
    
    // MARK: - MELT
    
    /// Generates blank outputs for overpaid amounts in NUT-08 transactions
    /// - Parameters:
    ///   - quote: The melt quote containing payment and fee information
    ///   - proofs: Array of proofs being used for the melt
    ///   - mint: The mint processing the melt
    ///   - unit: The currency unit being used (e.g., "sat" for satoshis)
    ///   - seed: Optional seed for deterministic outputs. When provided, enables backup recovery
    /// - Returns: Tuple containing:
    ///           - outputs: Array of blank outputs for fee returns
    ///           - blindingFactors: Array of blinding factors for each output
    ///           - secrets: Array of secrets for each output
    /// - Throws: CashuError.noActiveKeysetForUnit if no active keyset exists for the unit
    public static func generateBlankOutputs(quote: CashuSwift.Bolt11.MeltQuote,
                                          proofs: [some ProofRepresenting],
                                          mint: MintRepresenting,
                                          unit: String,
                                          seed: String? = nil) throws -> ((outputs: [Output],
                                                                         blindingFactors: [String],
                                                                         secrets: [String])) {
        
        guard let activeKeyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit(unit)
        }
        
        let deterministicFactors: (String, Int)?
        
        if let seed {
            deterministicFactors = (seed, activeKeyset.derivationCounter)
        } else {
            deterministicFactors = nil
        }
        
        let inputFee = try calculateFee(for: proofs, of: mint)
        let amountOverpaid = proofs.sum - quote.amount - quote.feeReserve - inputFee
        
        let blankDistribution = Array(repeating: 0, count: calculateNumberOfBlankOutputs(amountOverpaid))
        
        return try Crypto.generateOutputs(amounts: blankDistribution,
                                          keysetID: activeKeyset.keysetID,
                                          deterministicFactors: deterministicFactors)
    }
    
    /// Melts (redeems) proofs for a Lightning payment
    /// - Parameters:
    ///   - mint: The mint to perform the melt operation
    ///   - quote: The melt quote to process (must be Bolt11.MeltQuote)
    ///   - proofs: Array of proofs to melt
    ///   - timeout: Maximum time in seconds to wait for payment completion (default 600)
    ///   - blankOutputs: Optional tuple containing outputs for fee returns. Required if expecting
    ///                   change from overpaid Lightning network fees
    /// - Returns: Tuple containing:
    ///           - paid: Boolean indicating if payment was successful
    ///           - change: Optional array of change proofs from overpaid fees
    /// - Throws: CashuError.typeMismatch if quote is not a Bolt11.MeltQuote
    ///          CashuError.insufficientInputs if proofs don't cover amount and fees
    ///          CashuError.unitError if proofs are from multiple units
    public static func melt(mint:MintRepresenting,
                          quote:Quote,
                          proofs:[ProofRepresenting],
                          timeout:Double = 600,
                          blankOutputs: (outputs: [Output],
                                       blindingFactors: [String],
                                       secrets: [String])? = nil) async throws -> (paid:Bool,
                                                                                 change:[ProofRepresenting]?) {
        
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
        
        guard let units = try? units(for: proofs, of: mint), units.count == 1 else {
            throw CashuError.unitError("Could not determine singular unit for input proofs.")
        }
        
        guard var keyset = activeKeysetForUnit(units.first!, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit \(units)")
        }
        
        if let blankOutputs {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: normalize(proofs), outputs: blankOutputs.outputs)
        } else {
            meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: normalize(proofs), outputs: nil)
        }
        
        let meltResponse:Bolt11.MeltQuote
        
        
        meltResponse = try await Network.post(url: mint.url.appending(path: "/v1/melt/bolt11"),
                                              body: meltRequest,
                                              expected: Bolt11.MeltQuote.self,
                                              timeout: timeout)
        
        let change: [Proof]?
        if let promises = meltResponse.change, let blankOutputs {
            guard promises.count <= blankOutputs.outputs.count else {
                throw Crypto.Error.unblinding("could not unblind blank outputs for fee return")
            }
            
            change = try Crypto.unblindPromises(promises,
                                                blindingFactors: blankOutputs.blindingFactors,
                                                secrets: blankOutputs.secrets,
                                                keyset: keyset)
        } else {
            change = nil
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
            throw CashuError.unknownError("Unable to find payment state data in melt response.")
        }
    }
    
    /// Checks the payment status of a melt operation and processes any fee returns
    /// - Parameters:
    ///   - mint: The mint to check the payment status
    ///   - quoteID: The ID of the quote to check
    ///   - blankOutputs: Optional tuple containing outputs for fee returns. Required if expecting
    ///                   change from overpaid Lightning network fees
    /// - Returns: Tuple containing:
    ///           - paid: Boolean indicating if payment was successful
    ///           - change: Optional array of change proofs from overpaid fees
    /// - Throws: CashuError.unknownError if payment state cannot be determined
    ///          CashuError for keyset identification or unblinding failures
    public static func meltState(mint: MintRepresenting,
                               quoteID: String,
                               blankOutputs: (outputs: [Output],
                                            blindingFactors: [String],
                                            secrets: [String])? = nil) async throws -> (paid: Bool,
                                                                                      change: [ProofRepresenting]?) {
        let url = mint.url.appending(path: "/v1/melt/quote/bolt11/\(quoteID)")
        let quote = try await Network.get(url: url, expected: CashuSwift.Bolt11.MeltQuote.self)
        
        switch quote.state {
        case .paid:
            let ids = Set(mint.keysets.map({ $0.keysetID }))
            
            guard let promises = quote.change else {
                logger.info("quote did not contain promises for overpaid LN fees")
                return (true, [])
            }
            
            guard let blankOutputs else {
                logger.warning("checked melt quote that returns change for overpaid LN fees, but no blankOutputs were provided.")
                return (true, [])
            }
            
            guard let id = ids.first, ids.count == 1 else {
                throw CashuError.unknownError("could not determine singular keyset id from blankOutput list. result: \(ids)")
            }
            
            guard let keyset = mint.keysets.first(where: { $0.keysetID == id }) else {
                throw CashuError.unknownError("Could not find keyset for ID \(id)")
            }
            
            let change = try Crypto.unblindPromises(promises,
                                                    blindingFactors: blankOutputs.blindingFactors,
                                                    secrets: blankOutputs.secrets,
                                                    keyset: keyset)
            return (true, change)
        case .pending:
            return (false, nil)
        case .unpaid:
            return (false, nil)
        case .none:
            throw CashuError.unknownError("Melt quote unmexpected state. \(String(describing: quote.state)) - quote id: \(quoteID)")
        }
    }
    
    // MARK: - SWAP
    
    /// Swaps proofs for new ones from the mint, optionally with a specific amount
    /// - Parameters:
    ///   - mint: The mint to perform the swap
    ///   - proofs: Array of proofs to swap
    ///   - amount: Optional specific amount to swap for. If nil, swaps for the total amount
    ///            minus fees. Must not be larger than the sum of input proofs
    ///   - seed: Optional seed for deterministic outputs. When provided, enables backup recovery
    ///          of the new proofs if they are lost
    ///   - preferredReturnDistribution: Optional specific distribution for return amounts. Must sum
    ///                                 to the same amount as the change amount. If not provided,
    ///                                 amounts will be split into powers of 2
    /// - Returns: Tuple containing:
    ///           - new: Array of new proofs from the swap
    ///           - change: Array of change proofs if input amount was larger than requested
    /// - Throws: CashuError.insufficientInputs if amount plus fees exceeds proof sum
    ///          CashuError.unitError if proofs are from multiple units
    ///          CashuError.preferredDistributionMismatch if distribution doesn't match change amount
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
    
    /// Restores proofs from a seed phrase
    /// - Parameters:
    ///   - mint: The mint to restore proofs from
    ///   - seed: The seed phrase to use for restoration
    ///   - batchSize: Number of proofs to attempt to restore at once (default 10)
    /// - Returns: Array of KeysetRestoreResult containing restored proofs
    /// - Throws: CashuError for restoration failures
    public static func restore(mint:MintRepresenting,
                             with seed:String,
                             batchSize:Int = 10) async throws -> [KeysetRestoreResult] {
        // no need to check validity of seed as function would otherwise crash during first det sec generation
        var results = [KeysetRestoreResult]()
        for keyset in mint.keysets {
            logger.info("Attempting restore for keyset: \(keyset.keysetID) of mint: \(mint.url.absoluteString)")
            let (proofs, _, lastMatchCounter) = try await restoreForKeyset(mint:mint, keyset:keyset, with: seed, batchSize: batchSize)
            print("last match counter: \(String(describing: lastMatchCounter))")
            
            // if we dont have any restorable proofs on this keyset, move on to the next
            if proofs.isEmpty {
                logger.debug("No ecash to restore for keyset \(keyset.keysetID).")
                continue
            }
                        
            let states = try await check(proofs, mint: mint) // ignores pending but should not

            guard states.count == proofs.count else {
                throw CashuError.restoreError("unable to filter for unspent ecash during restore")
            }

            var spendableProofs = [ProofRepresenting]()
            for i in 0..<states.count {
                if states[i] == .unspent { spendableProofs.append(proofs[i]) }
            }
            
            let result = KeysetRestoreResult(keysetID: keyset.keysetID,
                                             derivationCounter: lastMatchCounter + 1,
                                             unitString: keyset.unit,
                                             proofs: spendableProofs,
                                             inputFeePPK: keyset.inputFeePPK)
            results.append(result)
            logger.info("Found \(spendableProofs.count) spendable proofs for keyset \(keyset.keysetID)")
        }
        return results
    }
    
    /// Restores proofs for a specific keyset
    /// - Parameters:
    ///   - mint: The mint to restore from
    ///   - keyset: The specific keyset to restore
    ///   - seed: The seed phrase to use
    ///   - batchSize: Number of proofs to attempt at once
    /// - Returns: Tuple containing restored proofs, total restored count, and last match counter
    /// - Throws: CashuError for restoration failures
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
            
            // filter blindingfactor and secret arrays to include only the ones for outputs that exist
            var rs = [String]()
            var xs = [String]()
            for i in 0..<outputs.count {
                if response.outputs.contains(where: {$0.B_ == outputs[i].B_}) {
                    rs.append(blindingFactors[i])
                    xs.append(secrets[i])
                }
            }
            
            let batchProofs = try Crypto.unblindPromises(response.signatures,
                                                         blindingFactors: rs,
                                                         secrets: xs,
                                                         keyset: keyset)
            proofs.append(contentsOf: batchProofs)
        }
        currentCounter -= (emptyRuns + 1) * batchSize
        currentCounter += batchLastMatchIndex
        if currentCounter < 0 { currentCounter = 0 }
        return (proofs, proofs.count, currentCounter)
    }
    
    /// Checks the state of proofs with the mint
    /// - Parameters:
    ///   - proofs: Array of proofs to check
    ///   - mint: The mint to check against
    /// - Returns: Array of proof states
    /// - Throws: Network or encoding errors
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
    
    /// Checks the state of proofs with a specific mint URL
    /// - Parameters:
    ///   - proofs: Array of proofs to check
    ///   - url: The URL of the mint to check against
    /// - Returns: Array of proof states
    /// - Throws: Network or encoding errors
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
    
    /// Normalizes an array of ProofRepresenting to internal Proof type
    /// - Parameter proofs: Array of proofs to normalize
    /// - Returns: Array of normalized Proof objects
    static func normalize(_ proofs:[ProofRepresenting]) -> [Proof] {
        proofs.map({ CashuSwift.Proof($0) })
    }
    
    /// Calculates the sum of amounts in an array of proofs
    /// - Parameter proofRepresenting: Array of proofs to sum
    /// - Returns: Total amount of all proofs
    static func sum(_ proofRepresenting:[ProofRepresenting]) -> Int {
        proofRepresenting.reduce(0) { $0 + $1.amount }
    }
    
    /// Picks proofs that sum to a target amount, considering fees
    /// - Parameters:
    ///   - proofs: Available proofs to pick from
    ///   - amount: Target amount to reach
    ///   - mint: The mint for fee calculation
    ///   - ignoreFees: Whether to ignore fee calculation
    /// - Returns: Optional tuple containing selected proofs, change proofs, and fee amount
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

    
    /// Selects proofs that sum exactly to a target amount
    /// - Parameters:
    ///   - proofs: Available proofs to select from
    ///   - targetAmount: Exact amount to reach
    /// - Returns: Optional tuple containing selected proofs and remaining proofs
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
    
    /// Calculates the total fee for a set of proofs
    /// - Parameters:
    ///   - proofs: Proofs to calculate fees for
    ///   - mint: The mint to use for fee rates
    /// - Returns: Total fee amount
    /// - Throws: CashuError if fee calculation fails
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
    
    /// Gets the active keyset for a specific unit
    /// - Parameters:
    ///   - unit: The unit to find keyset for
    ///   - mint: The mint to search in
    /// - Returns: Optional Keyset that is active for the unit
    public static func activeKeysetForUnit(_ unit:String, mint:MintRepresenting) -> Keyset? {
        mint.keysets.first(where: {
            $0.active == true &&
            $0.unit == unit
        })
    }
    
    /// Gets the set of units represented in the proofs
    /// - Parameters:
    ///   - proofs: Proofs to check units for
    ///   - mint: The mint to validate against
    /// - Returns: Set of unit strings
    /// - Throws: CashuError if units cannot be determined or are invalid
    static func units(for proofs:[ProofRepresenting], of mint:MintRepresenting) throws -> Set<String> {
        guard !mint.keysets.isEmpty, !proofs.isEmpty else {
            throw CashuError.unitError("empty inputs to function .check() proofs: \(proofs.count), keysete\(mint.keysets.count)")
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
    /// Receives a token across multiple mints (deprecated)
    /// - Parameters:
    ///   - token: The token to receive
    ///   - seed: Optional seed for deterministic outputs
    /// - Returns: Dictionary mapping mint URLs to received proofs
    /// - Throws: CashuError for invalid tokens or partially spent tokens
    public func receive(token:CashuSwift.Token,
                       seed:String? = nil) async throws -> Dictionary<String, [ProofRepresenting]> {
        
        guard token.proofsByMint.count == self.count else {
            logger.error("Number of mints in array does not match number of mints in token.")
            throw CashuError.invalidToken
        }
        
        // strictly make sure that mint URLs match
        guard token.proofsByMint.keys.allSatisfy({ mintURLstring in
            self.contains(where: { mintURLstring == $0.url.absoluteString })
        }) else {
            logger.error("URLs from token do not match mint array.")
            throw CashuError.invalidToken
        }
        
        var tokenStates = [CashuSwift.Proof.ProofState]()
        for (mintURLstring, proofs) in token.proofsByMint {
            let mint = self.first(where: { $0.url.absoluteString == mintURLstring })!
            tokenStates.append(contentsOf: try await CashuSwift.check(proofs, mint: mint))
        }
        
        guard tokenStates.allSatisfy({ $0 == .unspent }) else {
            logger.error("CashuSwift does not allow you to redeem a multi mint token that is only partially spendable.")
            throw CashuError.alreadySpent
        }
        
        var aggregateProofs = Dictionary<String, [ProofRepresenting]>()
        
        for (url, proofs) in token.proofsByMint {
            let mint = self.first(where: { $0.url.absoluteString == url })!
            let singleMintToken = CashuSwift.Token(proofs: [url: proofs], unit: token.unit)
            aggregateProofs[url] = try await CashuSwift.receive(mint: mint, token: singleMintToken, seed: seed)
        }
        return aggregateProofs
    }
    
}

extension Array where Element : ProofRepresenting {
    
    /// Calculates the sum of all proof amounts in the array
    /// - Returns: Total amount of all proofs combined
    public var sum: Int {
        self.reduce(0) { $0 + $1.amount }
    }
    
    /// Picks proofs that sum to a specific amount
    /// - Parameter amount: Target amount to reach
    /// - Returns: Optional tuple containing picked proofs and change proofs
    /// - Note: Returns nil if no combination of proofs sums to the target amount
    public func pick(_ amount:Int) -> (picked:[ProofRepresenting], change:[ProofRepresenting])? {
        CashuSwift.selectProofsToSumTarget(proofs: self, targetAmount: amount)
    }
    
    /// Converts proofs to internal Proof type for processing
    /// - Returns: Array of internal Proof objects
    /// - Note: Used for internal type consistency when processing proofs
    func internalize() -> [CashuSwift.Proof] {
        map({ CashuSwift.Proof($0) })
    }
}
