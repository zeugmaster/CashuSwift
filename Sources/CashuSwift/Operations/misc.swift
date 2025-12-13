//
//  File.swift
//  CashuSwift
//
//  Created by zm on 07.04.25.
//

import Foundation
import secp256k1
import OSLog
import BigNumber

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

/// The main namespace for CashuSwift operations.
public enum CashuSwift {
    
    /// Generates blinded outputs for minting.
    /// - Parameters:
    ///   - distribution: Array of amounts for each output
    ///   - mint: The mint to generate outputs for
    ///   - seed: Optional seed for deterministic generation
    ///   - unit: The unit to use (default: "sat")
    ///   - offset: Offset for deterministic counter (default: 0)
    /// - Returns: A tuple containing outputs, blinding factors, and secrets
    /// - Throws: An error if no active keyset is found for the unit
    public static func generateOutputs(distribution: [Int],
                                                mint: Mint,
                                                seed: String?,
                                                unit: String = "sat",
                                                offset: Int = 0) throws -> ((outputs: [Output],
                                                                             blindingFactors: [String],
                                                                             secrets: [String])) {
        guard let keyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit '\(unit)'")
        }
        
        return try Crypto.generateOutputs(amounts: distribution,
                                          keysetID: keyset.keysetID,
                                          deterministicFactors: seed.map({ ($0, keyset.derivationCounter + offset) }))
    }
    
    /// Generates P2PK-locked outputs for a specific amount.
    /// - Parameters:
    ///   - amount: The total amount to lock
    ///   - mint: The mint to generate outputs for
    ///   - publicKey: The Schnorr public key to lock to
    ///   - unit: The unit to use (default: "sat")
    /// - Returns: A tuple containing outputs, blinding factors, and secrets
    /// - Throws: An error if the operation fails
    public static func generateP2PKOutputs(for amount: Int,
                                           mint: Mint,
                                           publicKey: String,
                                           unit: String = "sat") throws -> ((outputs: [Output],
                                                                             blindingFactors: [String],
                                                                             secrets: [String])) {
        try generateP2PKOutputs(distribution: splitIntoBase2Numbers(amount),
                                mint: mint,
                                publicKey: publicKey,
                                unit: unit)
    }
    
    /// Generates P2PK-locked outputs with a specific distribution.
    /// - Parameters:
    ///   - distribution: Array of amounts for each output
    ///   - mint: The mint to generate outputs for
    ///   - publicKey: The Schnorr public key to lock to
    ///   - unit: The unit to use (default: "sat")
    /// - Returns: A tuple containing outputs, blinding factors, and secrets
    /// - Throws: An error if the operation fails
    public static func generateP2PKOutputs(distribution: [Int],
                                           mint: Mint,
                                           publicKey: String,
                                           unit: String = "sat") throws -> ((outputs: [Output],
                                                                             blindingFactors: [String],
                                                                             secrets: [String])) {
        guard let keyset = activeKeysetForUnit(unit, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit '\(unit)'")
        }
        
        var outputs = [Output]()
        var blindingFactors = [String]()
        var secrets = [String]()
        for amount in distribution {
            let nonce = try String(bytes: secp256k1.Signing.PrivateKey().dataRepresentation)
            let payload = SpendingCondition.Payload(nonce: nonce, data: publicKey, tags: nil)
            let sc = SpendingCondition(kind: .P2PK, payload: payload)
            let secret = try sc.serialize() // ONLY EVER SERIALIZE THIS ONCE to not have order of fields change
            let blindingFactor = try secp256k1.Signing.PrivateKey()
            let outputRaw = try Crypto.output(secret: secret, blindingFactor: blindingFactor)
            let output = Output(amount: amount,
                                B_: String(bytes: outputRaw.dataRepresentation),
                                id: keyset.keysetID)
            outputs.append(output)
            blindingFactors.append(String(bytes: blindingFactor.dataRepresentation))
            secrets.append(secret)
        }
        return (outputs, blindingFactors, secrets)
    }
    
    // MARK: - MELT
    /// Creates blank outputs for overpaid Lightning fees.
    ///
    /// Allows a wallet to create and persist blank outputs for an overpaid amount `sum(proofs) - quote.amount - inputFee`
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
    
    /// Checks the state of proofs with a mint.
    /// - Parameters:
    ///   - proofs: The proofs to check
    ///   - mint: The mint to check with
    /// - Returns: Array of proof states
    /// - Throws: An error if the check fails
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
    
    static func sum(_ outputs: [Output]) -> Int {
        outputs.reduce(0) { partialResult, o in
            partialResult + o.amount
        }
    }
    
    static func split(for total: Int, target: Int?, fee: Int) throws -> (sendAmount: Int, keepAmount: Int) {
        guard total >= 0 && fee >= 0 else {
            throw CashuError.invalidSplit("split function does not accept negative integers")
        }
        
        if let target {
            guard target >= 0 else {
                throw CashuError.invalidSplit("target value for split can not be negative.")
            }
            if total - fee == target {
                return (target, 0)
            } else if total - fee > target {
                return (target, total - target - fee)
            }
        } else {
            let target = total - fee
            if total - fee == target {
                return (target, 0)
            } else if total - fee > target {
                return (target + fee, total - target)
            }
        }
        throw CashuError.invalidSplit("target value (\(String(describing: target))) for split can not be greater than total(\(total))-fee(\(fee)).")
    }
    
    static func stripDLEQ(_ proofs: [Proof]) -> [CashuSwift.Proof] {
        proofs.map { p in
            CashuSwift.Proof(keysetID: p.keysetID,
                             amount: p.amount,
                             secret: p.secret,
                             C: p.C,
                             dleq: nil,
                             witness: p.witness)
        }
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

    public static func numericalRepresentation(of keysetID: String) throws -> Int {
        let bytes: [UInt8]
        if keysetID.count == 12 {
            guard let data = Data(base64Encoded: keysetID) else {
                throw CashuSwift.Crypto.Error.secretDerivation(
                    "Unable to calculate numerical representation of keyset id \(keysetID); unable to decode base64 to data")
            }
            bytes = [UInt8](data)
        } else if keysetID.count >= 16 {
            guard let b = try? keysetID.bytes else {
                throw CashuSwift.Crypto.Error.secretDerivation(
                    "Unable to calculate numerical representation of keyset id \(keysetID); unable to decode hex to bytes")
            }
            bytes = b
        } else {
            throw CashuSwift.Crypto.Error.secretDerivation(
                "Unable to calculate numerical representation of keyset id \(keysetID); invalid lenght (\(keysetID.count) chars, expected: 14, >= 16)")
        }
        let big = BInt(bytes: bytes)
        let result = big % (Int(pow(2.0, 31.0)) - 1)
        return Int(result)
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
    
    /// Calculates the total fee for spending the provided proofs.
    /// - Parameters:
    ///   - proofs: The proofs to calculate fees for
    ///   - mint: The mint the proofs belong to
    /// - Returns: The total fee in the smallest unit
    /// - Throws: An error if fee calculation fails
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
            throw CashuError.unitError("empty inputs to function .units(for:) proofs: \(proofs.count), keyset \(mint.keysets.count)")
        }
        
        var units:Set<String> = []
        for proof in proofs {
            if proof.keysetID.count == 12 {
                guard let keysetForID = mint.keysets.first(where: { $0.keysetID == proof.keysetID }) else {
                    throw CashuError.unitError("unable to determine keyset with id \(proof.keysetID) for mint \(mint.url.absoluteString)")
                }
                units.insert(keysetForID.unit)
            } else {
                if proof.keysetID.hasPrefix("00") {
                    guard let keysetForID = mint.keysets.first(where: { $0.keysetID == proof.keysetID }) else {
                        throw CashuError.unitError("unable to determine keyset with id \(proof.keysetID) for mint \(mint.url.absoluteString)")
                    }
                    
                    units.insert(keysetForID.unit)
                } else if proof.keysetID.hasPrefix("01") {
                    let keysets = mint.keysets.filter({ $0.keysetID.hasPrefix(proof.keysetID) })
                    
                    guard !keysets.isEmpty else {
                        throw CashuError.unitError("unable to determine any keyset with id \(proof.keysetID) for mint \(mint.url.absoluteString)")
                    }
                    
                    guard keysets.count == 1 else {
                        throw CashuError.invalidKeysetID("keyset id \(proof.keysetID) of mint \(mint.url.absoluteString) resolves to MORE THAN ONE keyset")
                    }
                    
                    units.insert(keysets.first!.unit)
                } else {
                    throw CashuError.invalidKeysetID("Invalid keyset id \(proof.keysetID)")
                }
            }
        }
        return units
    }
    
    /// Splits an integer into its base-2 components.
    /// - Parameter n: The number to split
    /// - Returns: Array of powers of 2 that sum to n
    static func splitIntoBase2Numbers(_ n:Int) -> [Int] {
        (0 ..< Int.bitWidth - n.leadingZeroBitCount)
            .map { 1 << $0 }
            .filter { n & $0 != 0 }
    }
    
    // concrete type overloads
    public static func check(_ proofs: [Proof], mint: Mint) async throws -> [Proof.ProofState] {
        return try await check(proofs as [ProofRepresenting], mint: mint as MintRepresenting)
    }
    
    // MARK: - Calculate Fee Overloads
    public static func calculateFee(for proofs: [Proof], of mint: Mint) throws -> Int {
        return try calculateFee(for: proofs as [ProofRepresenting], of: mint as MintRepresenting)
    }

}

extension Encodable {
    func debugPretty() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? "Unable to convert JSON data to UTF-8 string"
        } catch {
            return "Could not encode object as pretty JSON string."
        }
    }
}


func calculateNumberOfBlankOutputs(_ overpayed:Int) -> Int {
    if overpayed <= 0 {
        return 0
    } else {
        return max(Int(ceil(log2(Double(overpayed)))), 1)
    }
}

extension Array where Element : ProofRepresenting {
    
    public func withShortKeysetID() -> [CashuSwift.Proof] {
        self.map { p in
            let shortID = p.keysetID.count != 12 && p.keysetID.hasPrefix("01") ? String(p.keysetID.prefix(16)) : p.keysetID
            return CashuSwift.Proof(keysetID: shortID,
                                    amount: p.amount,
                                    secret: p.secret,
                                    C: p.C,
                                    dleq: p.dleq,
                                    witness: nil)
        }
    }
    
    public func withFullKeysetID(of mint: MintRepresenting) throws -> [CashuSwift.Proof] {
        var proofs = [CashuSwift.Proof]()
        
        for p in self {
            let fullID: String
            if p.keysetID.count == 12 {
                fullID = p.keysetID
            } else {
                if p.keysetID.hasPrefix("00") {
                    fullID = p.keysetID
                } else if p.keysetID.hasPrefix("01") {
                    let keysets = mint.keysets.filter({ $0.keysetID.hasPrefix(p.keysetID) })
                    guard !keysets.isEmpty else {
                        throw CashuError.invalidKeysetID("No keyset of mint \(mint.url.absoluteString) could be determined for short id \(p.keysetID)")
                    }
                    guard keysets.count == 1 else {
                        throw CashuError.invalidKeysetID("More than one keyset of mint \(mint.url.absoluteString) matches the shortened version \(p.keysetID)")
                    }
                    fullID = keysets.first!.keysetID
                } else {
                    throw CashuError.invalidKeysetID("keyset id \(p.keysetID) is invalid (neither legacy, nor v0 '00' or v1 '01'")
                }
            }
            proofs.append(CashuSwift.Proof(keysetID: fullID,
                                           amount: p.amount,
                                           secret: p.secret,
                                           C: p.C,
                                           dleq: p.dleq,
                                           witness: nil))
        }
        
        return proofs
    }
    
    public var sum: Int {
        self.reduce(0) { $0 + $1.amount }
    }
    
    public func pick(_ amount:Int) -> (picked:[ProofRepresenting], change:[ProofRepresenting])? {
        CashuSwift.selectProofsToSumTarget(proofs: self, targetAmount: amount)
    }
}

extension Array where Element == Bool {
    public var allTrue: Bool {
        self.allSatisfy({ $0 == true })
    }
}

/// Extensions for Token-related operations.
extension CashuSwift.Token {
    /// Result of checking locked proofs.
    public enum LockVerificationResult {
        /// All proofs match the provided public key.
        case match
        /// All proofs are locked but to a different key.
        case mismatch
        /// Some proofs match, some don't.
        case partial
        /// No proofs have spending conditions.
        case notLocked
        /// Proofs are locked but no key was provided to check.
        case noKey
    }
    
    public func checkAllInputsLocked(to publicKey: String?) throws -> LockVerificationResult {
        guard let proofs = self.proofsByMint.first?.value else {
            throw CashuError.invalidToken
        }
        
        return try CashuSwift.check(all: proofs, lockedTo: publicKey)
    }
}

extension CashuSwift {
    /// Checks if proofs are locked to a specific public key.
    /// - Parameters:
    ///   - inputs: The proofs to check
    ///   - publicKey: Optional public key to check against
    /// - Returns: The lock verification result
    /// - Throws: An error if verification fails
    public static func check(all inputs:[Proof], lockedTo publicKey: String?) throws -> Token.LockVerificationResult {
        let verifications = Set<Token.LockVerificationResult>( inputs.map { p in
            if let spendingCondition = CashuSwift.SpendingCondition.deserialize(from: p.secret) {
                switch spendingCondition.kind {
                case .P2PK:
                    if let publicKey {
                        return spendingCondition.payload.data == publicKey ? .match : .mismatch
                    } else {
                        return .noKey
                    }
                case .HTLC:
                    return .mismatch
                }
            } else {
                return .notLocked
            }
        })
        
        return verifications.count == 1 ? verifications.first! : .partial
    }
    
    /// Signs P2PK-locked proofs with a private key.
    /// - Parameters:
    ///   - inputs: The proofs to sign
    ///   - keyHex: Hex string of the private key
    /// - Throws: An error if signing fails
    public static func sign(all inputs: [Proof], using keyHex: String) throws {
        let key = try secp256k1.Schnorr.PrivateKey(dataRepresentation: keyHex.bytes)
        let publicKeyHex = String(bytes: key.publicKey.dataRepresentation)
        
        for var p in inputs {
            guard let sc = SpendingCondition.deserialize(from: p.secret) else {
                throw CashuError.spendingConditionError("Secret is not 'Well-known secret' kind, probably deterministic. Secret: \(p.secret)")
            }
            if sc.kind == .HTLC {
                throw CashuError.spendingConditionError("Fucntion expects P2PK spending condition but received HTLC kind. Secret: \(p.secret)")
            }
            guard sc.payload.data == publicKeyHex else {
                throw CashuError.invalidKey("The provided public key does not match the one the input is locked to.")
            }
            try p.sign(using: [key])
        }
    }
}

extension CashuSwift.Proof {
    mutating func sign(using keys: [secp256k1.Schnorr.PrivateKey]) throws {
        let signatures = try CashuSwift.Crypto.signatures(on: self.secret, with: keys)
        let witness = Witness(signatures: signatures)
        self.witness = try witness.stringJSON()
    }
}
