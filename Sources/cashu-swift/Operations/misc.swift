//
//  File.swift
//  CashuSwift
//
//  Created by zm on 07.04.25.
//

import Foundation
import secp256k1
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

public enum CashuSwift {
    
    // MARK: - MELT
    ///Allows a wallet to create and persist NUT-08 blank outputs for an overpaid amount `sum(proofs) - quote.amount - inputFee`
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

extension Array where Element : MintRepresenting {
    
    // docs: deprecated and only for redeeming legace V3 multi mint token
    @available(*, deprecated)
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

extension CashuSwift.Token {
    public enum LockVerificationResult { case match, mismatch, partial, notLocked, noKey }
    
    public func checkAllInputsLocked(to publicKey: String?) throws -> LockVerificationResult {
        guard let proofs = self.proofsByMint.first?.value else {
            throw CashuError.invalidToken
        }
        
        let verifications = Set<LockVerificationResult>( try proofs.map { p in
            let secret = try CashuSwift.Secret.deserialize(string: p.secret)
            switch secret {
            case .P2PK(sc: let sc):
                if let publicKey {
                    return sc.data == publicKey ? .match : .mismatch
                } else {
                    return .noKey
                }
            case .HTLC(sc: let sc):
                return .mismatch
            case .deterministic(s: _):
                return .notLocked
            }
        })
        
        return verifications.count == 1 ? verifications.first! : .partial
    }
}
