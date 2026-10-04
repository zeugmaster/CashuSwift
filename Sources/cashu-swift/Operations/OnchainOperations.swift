import Foundation
import secp256k1

extension CashuSwift.Onchain {
    public static func quoteLockingKey(seed: String, counter: UInt32) throws -> (privateKey: Data, publicKey: String) {
        guard counter < 0x80000000 else { throw CashuError.invalidAmount }
        return try CashuSwift.Crypto.nut20QuoteLockingKey(seed: seed, counter: counter)
    }

    public static func requestMintQuote(_ request: MintQuoteRequest, from mint: CashuSwift.Mint,
                                        info: CashuSwift.Mint.Info? = nil) async throws -> MintQuote {
        let requestedKey = try CashuSwift.Crypto.nut20PublicKey(request.pubkey)
        let metadata = try await metadata(info, mint: mint)
        _ = try settings(in: metadata, unit: request.unit, direction: .mint)
        let quote = try await Network.strictPost(url: endpoint(mint.url, "mint/quote/onchain"),
                                                body: request, expected: MintQuote.self)
        guard quote.unit == request.unit,
              try CashuSwift.Crypto.nut20PublicKey(quote.pubkey).dataRepresentation == requestedKey.dataRepresentation else {
            throw Error.invalidResponse
        }
        return quote
    }

    public static func mintQuoteState(_ id: String, from mint: CashuSwift.Mint) async throws -> MintQuote {
        try validateQuoteID(id)
        let result = try await Network.strictGet(url: endpoint(mint.url, "mint/quote/onchain/\(id)"), expected: MintQuote.self)
        guard result.quote == id else { throw Error.invalidResponse }
        return result
    }

    /// Prefer this overload when refreshing a persisted quote: it binds the response
    /// to the original address/key and merges accounting in timestamp order.
    public static func mintQuoteState(_ previous: MintQuote, from mint: CashuSwift.Mint) async throws -> MintQuote {
        try previous.merging(await mintQuoteState(previous.quote, from: mint))
    }

    public static func requestMeltQuote(_ request: MeltQuoteRequest, from mint: CashuSwift.Mint,
                                        info: CashuSwift.Mint.Info? = nil) async throws -> MeltQuote {
        try validateAddress(request.request)
        guard request.amount > 0 else { throw CashuError.invalidAmount }
        let metadata = try await metadata(info, mint: mint)
        try settings(in: metadata, unit: request.unit, direction: .melt).validate(amount: request.amount)
        let quote = try await Network.strictPost(url: endpoint(mint.url, "melt/quote/onchain"),
                                                body: request, expected: MeltQuote.self)
        guard quote.request == request.request, quote.unit == request.unit, quote.amount == request.amount,
              quote.state == .unpaid, quote.selectedFeeIndex == nil,
              quote.outpoint == nil, quote.change?.isEmpty ?? true else { throw Error.invalidResponse }
        return quote
    }

    public static func meltQuoteState(_ id: String, from mint: CashuSwift.Mint) async throws -> MeltQuote {
        try validateQuoteID(id)
        let quote = try await Network.strictGet(url: endpoint(mint.url, "melt/quote/onchain/\(id)"), expected: MeltQuote.self)
        guard quote.quote == id else { throw Error.invalidResponse }
        return quote
    }

    /// Prepare without network access. Persist the context and advance its output
    /// counter before calling `mint(context:from:)`. Serialize issuance per quote.
    public static func prepareMint(quote: MintQuote, from mint: CashuSwift.Mint, amount: Int,
                                   seed: String?, quoteKey: Data, info: CashuSwift.Mint.Info,
                                   preferredDistribution: [Int]? = nil) throws -> MintContext {
        try CashuSwift.Crypto.validateNut20QuoteKey(quoteKey, pubkey: quote.pubkey)
        try settings(in: info, unit: quote.unit, direction: .mint).validate(amount: amount)
        guard amount <= quote.mintableAmount else { throw CashuError.amountOutsideOfLimitRange }
        let distribution = preferredDistribution ?? CashuSwift.splitIntoBase2Numbers(amount)
        guard try total(distribution) == amount,
              distribution.allSatisfy({ $0 > 0 && $0.nonzeroBitCount == 1 }) else {
            throw CashuError.preferredDistributionMismatch("Invalid issuance distribution.")
        }
        let material = try generateMaterial(amounts: distribution, mint: mint, unit: quote.unit, seed: seed)
        let signature = try CashuSwift.Crypto.nut20Signature(quoteID: quote.quote, outputs: material.outputs, privateKey: quoteKey)
        return MintContext(version: 1, mintURL: mint.url, quote: quote, material: material, signature: signature)
    }

    public static func mint(context: MintContext, from mint: CashuSwift.Mint) async throws -> MintResult {
        try validate(context, mint: mint)
        let response = try await Network.strictPost(url: endpoint(mint.url, "mint/onchain"),
                                                   body: context.executionBody, expected: CashuSwift.MintExecutionResponse.self)
        return recoverMint(promises: response.signatures, context: context)
    }

    /// Recover a lost mint response using the saved outputs (NUT-09). This requests
    /// existing signatures and never issues new ecash. An empty response is pending,
    /// not proof that it is safe to issue another set of outputs for this quote.
    public static func restoreMint(context: MintContext, from mint: CashuSwift.Mint) async throws -> MintResult {
        try validate(context, mint: mint)
        let response = try await Network.strictPost(url: endpoint(mint.url, "restore"),
            body: CashuSwift.RestoreRequest(outputs: context.material.outputs), expected: CashuSwift.RestoreResponse.self)
        guard response.outputs.count == response.signatures.count else { throw Error.invalidResponse }
        if response.outputs.isEmpty { return MintResult(promises: [], recovery: .pending) }
        var byOutput = [String: CashuSwift.Promise]()
        let expected = Set(context.material.outputs.map(\.B_))
        for (output, promise) in zip(response.outputs, response.signatures) {
            guard expected.contains(output.B_), byOutput[output.B_] == nil else { throw Error.invalidResponse }
            byOutput[output.B_] = promise
        }
        guard byOutput.count == context.material.outputs.count else { throw Error.invalidResponse }
        let ordered = context.material.outputs.compactMap { byOutput[$0.B_] }
        return recoverMint(promises: ordered, context: context)
    }

    /// Recover previously saved signatures without resubmitting the mint operation.
    public static func recoverMint(promises: [CashuSwift.Promise], context: MintContext) -> MintResult {
        let recovery: RecoveryResult
        do {
            try validate(context, mint: CashuSwift.Mint(url: context.mintURL, keysets: []))
            recovery = recover(promises, material: context.material, exactAmounts: true,
                               maximum: try total(context.material.outputs.map(\.amount)))
        } catch { recovery = .failed(.invalidPromises) }
        return MintResult(promises: promises, recovery: recovery)
    }

    /// Prepare a withdrawal using already selected proofs. For selection use
    /// `try quote.selectingFee(index:).requiredInputAmount(inputFee: 0)` as the target.
    public static func prepareMelt(quote: MeltQuote, feeIndex: Int, from mint: CashuSwift.Mint,
                                   proofs: [CashuSwift.Proof], seed: String?, info: CashuSwift.Mint.Info,
                                   now: Date = Date()) throws -> MeltContext {
        let selected = try quote.selectingFee(index: feeIndex)
        guard quote.state == .unpaid, quote.selectedFeeIndex == nil,
              quote.outpoint == nil, quote.change?.isEmpty ?? true else { throw Error.invalidQuote }
        try checkExpiry(quote.expiry, now: now)
        try settings(in: info, unit: quote.unit, direction: .melt).validate(amount: quote.amount)
        // Expand short IDs before fee/key lookup, retaining supplied witnesses.
        let expanded = try proofs.withFullKeysetID(of: mint)
        let inputs = zip(expanded, proofs).map { full, original in
            CashuSwift.Proof(keysetID: full.keysetID, amount: full.amount, secret: full.secret,
                             C: full.C, dleq: original.dleq, witness: original.witness)
        }
        let fee = try inputFee(inputs, mint: mint, unit: quote.unit)
        let sum = try total(inputs.map(\.amount))
        guard try sum >= selected.requiredInputAmount(inputFee: fee) else {
            throw CashuError.insufficientInputs("Proofs do not cover the selected onchain fee option.")
        }
        let maximumReturn = sum - quote.amount - fee
        let blanks = Array(repeating: 0, count: calculateNumberOfBlankOutputs(maximumReturn))
        let material = try generateMaterial(amounts: blanks, mint: mint, unit: quote.unit, seed: seed)
        return MeltContext(version: 1, mintURL: mint.url, quote: quote, feeIndex: feeIndex,
                           inputs: inputs, inputFee: fee, material: material)
    }

    /// Submit once. A thrown transport error or cancellation leaves the outcome
    /// unknown: keep the context/inputs reserved and call `meltState`, not `melt`.
    public static func melt(context: MeltContext, from mint: CashuSwift.Mint,
                            timeout: Double = 30) async throws -> MeltResult {
        try validate(context, mint: mint)
        try checkExpiry(context.quote.expiry, now: Date())
        guard try inputFee(context.inputs, mint: mint, unit: context.quote.unit) == context.inputFee else {
            throw Error.invalidContext
        }
        guard timeout.isFinite, timeout > 0 else { throw Error.invalidContext }
        let quote = try await Network.strictPost(url: endpoint(mint.url, "melt/onchain"),
                                                body: context.executionBody, expected: MeltQuote.self, timeout: timeout)
        guard quote.state == .pending else { throw Error.invalidResponse }
        return try meltResult(quote, context: context)
    }

    /// Poll the original quote, even after expiry. This never posts proofs.
    /// Upsert returned change by proof identity; repeated calls return the same change.
    public static func meltState(context: MeltContext, from mint: CashuSwift.Mint) async throws -> MeltResult {
        try validate(context, mint: mint)
        let quote = try await meltQuoteState(context.quote.quote, from: mint)
        return try meltResult(quote, context: context)
    }

    private static func meltResult(_ quote: MeltQuote, context: MeltContext) throws -> MeltResult {
        let original = context.quote
        guard quote.quote == original.quote, quote.request == original.request,
              quote.amount == original.amount, quote.unit == original.unit, quote.expiry == original.expiry,
              quote.feeOptions.sorted(by: { $0.feeIndex < $1.feeIndex }) == original.feeOptions.sorted(by: { $0.feeIndex < $1.feeIndex }),
              // CDK 0.18 acknowledges PENDING before persisting selected_fee_index.
              // Keep the wallet's explicit choice in the context; a present index
              // must match, and settlement always requires a matching index.
              quote.selectedFeeIndex == context.feeIndex || (quote.state != .paid && quote.selectedFeeIndex == nil) else {
            throw Error.invalidResponse
        }
        let recovery: RecoveryResult
        if quote.state == .paid {
            guard quote.outpoint != nil else { throw Error.invalidResponse }
            let maximum = try total(context.inputs.map(\.amount)) - quote.amount - context.inputFee
            let reserve = try original.selectingFee(index: context.feeIndex).selectedFee.feeReserve
            // A mint may keep the whole reserve, but not denomination overpayment.
            if (try? total((quote.change ?? []).map(\.amount))).map({ $0 >= maximum - reserve }) != true {
                recovery = .failed(.invalidPromises)
            } else {
                recovery = recover(quote.change ?? [], material: context.material, exactAmounts: false, maximum: maximum)
            }
        } else {
            recovery = .pending
        }
        return MeltResult(quote: quote, changeRecovery: recovery)
    }

    private static func metadata(_ info: CashuSwift.Mint.Info?, mint: CashuSwift.Mint) async throws -> CashuSwift.Mint.Info {
        if let info { return info }
        return try await Network.strictGet(url: endpoint(mint.url, "info"), expected: CashuSwift.Mint.Info.self)
    }

    static func endpoint(_ url: URL, _ path: String) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw Error.invalidContext
        }
        return url.appending(path: "v1/\(path)")
    }

    private static func checkExpiry(_ expiry: Int?, now: Date) throws {
        if let expiry, Double(expiry) <= now.timeIntervalSince1970 { throw CashuError.quoteIsExpired }
    }

    static func total(_ values: [Int]) throws -> Int {
        try values.reduce(0) { try add($0, $1) }
    }

    private static func inputFee(_ proofs: [CashuSwift.Proof], mint: CashuSwift.Mint, unit: String) throws -> Int {
        guard !proofs.isEmpty, Set(proofs.map(\.secret)).count == proofs.count else { throw Error.invalidContext }
        var feePPK = 0
        for proof in proofs {
            guard proof.amount > 0, proof.amount.nonzeroBitCount == 1,
                  let keyset = mint.keysets.first(where: { $0.keysetID == proof.keysetID }),
                  keyset.unit == unit, keyset.keys[String(proof.amount)] != nil else { throw Error.invalidContext }
            try validateKeyset(keyset)
            // Locked proofs need a dedicated witness-aware spending flow.
            guard !proof.secret.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") else {
                throw CashuError.spendingConditionError("Prepare unlocked inputs before an onchain withdrawal.")
            }
            _ = try CashuSwift.Crypto.nut20PublicKey(proof.C)
            feePPK = try add(feePPK, keyset.inputFeePPK)
        }
        return feePPK / 1000 + (feePPK % 1000 == 0 ? 0 : 1)
    }

    private static func validateKeyset(_ keyset: CashuSwift.Keyset) throws {
        guard keyset.inputFeePPK >= 0, !keyset.keys.isEmpty else { throw Error.invalidContext }
        for (amount, key) in keyset.keys {
            guard let denomination = UInt64(amount), denomination > 0, denomination.nonzeroBitCount == 1,
                  String(denomination) == amount else { throw Error.invalidContext }
            _ = try CashuSwift.Crypto.nut20PublicKey(key)
        }
        guard keyset.validID else { throw CashuError.invalidKeysetID("Onchain keyset ID does not match its keys.") }
    }

    private static func generateMaterial(amounts: [Int], mint: CashuSwift.Mint, unit: String, seed: String?) throws -> OutputMaterial {
        _ = try endpoint(mint.url, "info")
        guard let keyset = CashuSwift.activeKeysetForUnit(unit, mint: mint) else { throw CashuError.noActiveKeysetForUnit(unit) }
        try validateKeyset(keyset)
        guard amounts.allSatisfy({ $0 == 0 || keyset.keys[String($0)] != nil }) else { throw CashuError.invalidAmount }
        let range: CounterRange?
        if seed != nil {
            let next = try add(keyset.derivationCounter, amounts.count)
            // Legacy derivation uses hardened UInt32 child indexes.
            guard keyset.keysetID.hasPrefix("01") || UInt64(next) <= 0x80000000 else { throw CashuError.invalidAmount }
            range = CounterRange(keysetID: keyset.keysetID, start: keyset.derivationCounter, next: next)
        } else { range = nil }
        let outputs = try CashuSwift.Crypto.generateOutputs(amounts: amounts, keysetID: keyset.keysetID,
                                                           deterministicFactors: seed.map { ($0, keyset.derivationCounter) })
        return OutputMaterial(keyset: keyset, outputs: outputs.outputs, blindingFactors: outputs.blindingFactors,
                              secrets: outputs.secrets, counterRange: range)
    }

    private static func validate(_ material: OutputMaterial, unit: String) throws {
        try validateKeyset(material.keyset)
        guard material.keyset.unit == unit,
              material.outputs.count == material.secrets.count, material.outputs.count == material.blindingFactors.count,
              Set(material.secrets).count == material.secrets.count else { throw Error.invalidContext }
        if let range = material.counterRange {
            guard range.keysetID == material.keyset.keysetID,
                  try add(range.start, material.outputs.count) == range.next else { throw Error.invalidContext }
        }
        for (i, output) in material.outputs.enumerated() {
            guard output.id == material.keyset.keysetID, output.amount >= 0,
                  output.amount == 0 || material.keyset.keys[String(output.amount)] != nil else { throw Error.invalidContext }
            let r = try CashuSwift.Crypto.PrivateKey(dataRepresentation: material.blindingFactors[i].bytes)
            let expected = try CashuSwift.Crypto.output(secret: material.secrets[i], blindingFactor: r)
            guard try expected.dataRepresentation == CashuSwift.Crypto.nut20PublicKey(output.B_).dataRepresentation else {
                throw Error.invalidContext
            }
        }
    }

    private static func validate(_ context: MintContext, mint: CashuSwift.Mint) throws {
        guard context.version == 1 else { throw Error.unsupportedContextVersion }
        guard context.mintURL == mint.url else { throw Error.invalidContext }
        try validate(context.material, unit: context.quote.unit)
        let amounts = context.material.outputs.map(\.amount)
        guard !amounts.isEmpty, amounts.allSatisfy({ $0 > 0 }),
              try total(amounts) <= context.quote.mintableAmount else { throw Error.invalidContext }
        let key = try secp256k1.Schnorr.PublicKey(dataRepresentation: context.quote.pubkey.bytes, format: .compressed)
        let signature = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: context.signature.bytes)
        guard try key.xonly.isValidSignature(signature, for: CashuSwift.Crypto.nut20MessageToSign(
            quoteID: context.quote.quote, outputs: context.material.outputs)) else { throw Error.invalidContext }
    }

    private static func validate(_ context: MeltContext, mint: CashuSwift.Mint) throws {
        guard context.version == 1 else { throw Error.unsupportedContextVersion }
        guard context.mintURL == mint.url, context.quote.state == .unpaid,
              context.quote.selectedFeeIndex == nil, context.inputFee >= 0 else { throw Error.invalidContext }
        try validate(context.material, unit: context.quote.unit)
        guard context.material.outputs.allSatisfy({ $0.amount == 0 }) else { throw Error.invalidContext }
        let selected = try context.quote.selectingFee(index: context.feeIndex)
        let sum = try total(context.inputs.map(\.amount))
        guard !context.inputs.isEmpty, context.inputs.allSatisfy({ $0.amount > 0 }),
              Set(context.inputs.map(\.secret)).count == context.inputs.count,
              try sum >= selected.requiredInputAmount(inputFee: context.inputFee),
              context.material.outputs.count == calculateNumberOfBlankOutputs(sum - context.quote.amount - context.inputFee) else {
            throw Error.invalidContext
        }
    }

    private static func recover(_ promises: [CashuSwift.Promise], material: OutputMaterial,
                                 exactAmounts: Bool, maximum: Int) -> RecoveryResult {
        guard promises.count <= material.outputs.count,
              !exactAmounts || promises.count == material.outputs.count else { return .failed(.invalidPromises) }
        do {
            guard try total(promises.map(\.amount)) <= maximum else { return .failed(.invalidPromises) }
            for (i, promise) in promises.enumerated() {
                let output = material.outputs[i]
                guard promise.id == output.id, promise.amount > 0,
                      !exactAmounts || promise.amount == output.amount,
                      let key = material.keyset.keys[String(promise.amount)] else { return .failed(.invalidPromises) }
                guard let dleq = promise.dleq else { return .failed(.missingDLEQ) }
                let valid = try CashuSwift.Crypto.verifyDLEQ(
                    A: CashuSwift.Crypto.nut20PublicKey(key), B_: CashuSwift.Crypto.nut20PublicKey(output.B_),
                    C_: CashuSwift.Crypto.nut20PublicKey(promise.C_), e: Data(dleq.e.bytes), s: Data(dleq.s.bytes))
                guard valid else { return .failed(.invalidDLEQ) }
            }
            let proofs = try CashuSwift.Crypto.unblindPromises(promises,
                blindingFactors: Array(material.blindingFactors.prefix(promises.count)),
                secrets: Array(material.secrets.prefix(promises.count)), keyset: material.keyset)
            return .complete(proofs)
        } catch { return .failed(.invalidPromises) }
    }
}
