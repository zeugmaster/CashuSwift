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

extension CashuSwift {
    
    @available(*, deprecated, message: "function does not check DLEQ")
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
        
        guard let units = try? units(for: proofs, of: mint), units.count == 1 else {
            throw CashuError.unitError("Could not determine singular unit for input proofs.")
        }
        
        guard let keyset = activeKeysetForUnit(units.first!, mint: mint) else {
            throw CashuError.noActiveKeysetForUnit("No active keyset for unit \(units)")
        }
        
        let noDLEQ = proofs.map({ Proof(keysetID: $0.keysetID, amount: $0.amount, secret: $0.secret, C: $0.C, dleq: nil, witness: nil) })
                
        let meltRequest = Bolt11.MeltRequest(quote: quote.quote, inputs: noDLEQ, outputs: blankOutputs.map({ $0.outputs }))
        
        let meltResponse = try await Network.post(url: mint.url.appending(path: "/v1/melt/bolt11"),
                                                  body: meltRequest,
                                                  expected: Bolt11.MeltQuote.self,
                                                  timeout: timeout)
        
        let change: [Proof]?
        if let promises = meltResponse.change, let blankOutputs {
            guard promises.count <= blankOutputs.outputs.count else {
                throw Crypto.Error.unblinding("could not unblind blank outputs for fee return")
            }
            
            do {
                change = try Crypto.unblindPromises(promises,
                                                    blindingFactors: Array(blankOutputs.blindingFactors.prefix(promises.count)),
                                                    secrets: Array(blankOutputs.secrets.prefix(promises.count)),
                                                    keyset: keyset)
            } catch {
                logger.error("Unable to unblind change form melt operation due to error: \(error). operation will still return successful.")
                change = nil
            }
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
    
    ///Checks whether the invoice was successfully paid by the mint.
    ///If the check returns `true` and the user has provided NUT-07 blank outputs for fee return
    ///it will also unblind the mint's promises and return valid change proofs.
    @available(*, deprecated, message: "function does not check DLEQ")
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
            
            do {
                let change = try Crypto.unblindPromises(promises,
                                                        blindingFactors: Array(blankOutputs.blindingFactors.prefix(promises.count)),
                                                        secrets: Array(blankOutputs.secrets.prefix(promises.count)),
                                                        keyset: keyset)
                return (true, change)
            } catch {
                logger.error("Unable to unblind change form melt operation due to error: \(error). operation will still return successful.")
                return (true, [])
            }
            
        case .pending:
            return (false, nil)
        case .unpaid:
            return (false, nil)
        case .none:
            throw CashuError.unknownError("Melt quote unmexpected state. \(String(describing: quote.state)) - quote id: \(quoteID)")
        }
    }
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func melt(mint: Mint,
                            quote: Quote,
                            proofs: [Proof],
                            timeout: Double = 600,
                            blankOutputs: (outputs: [Output],
                                        blindingFactors: [String],
                                        secrets: [String])? = nil) async throws -> (paid: Bool, change: [Proof]?) {
        let result = try await melt(mint: mint as MintRepresenting,
                                    quote: quote,
                                    proofs: proofs as [ProofRepresenting],
                                    timeout: timeout,
                                    blankOutputs: blankOutputs)
        return (result.paid, result.change as! [Proof]?)
    }
    
    @available(*, deprecated, message: "function does not check DLEQ")
    public static func meltState(mint: Mint,
                                 quoteID: String,
                                 blankOutputs: (outputs: [Output],
                                                blindingFactors: [String],
                                                secrets: [String])? = nil) async throws -> (paid: Bool,
                                                                                            change: [Proof]?) {
        return try await meltState(mint: mint as MintRepresenting,
                                   quoteID: quoteID,
                                   blankOutputs: blankOutputs) as! (Bool, [Proof])
    }
    
    public static func meltState(for quoteID: String,
                                 mint: Mint,
                                 blankOutputs: (outputs: [Output],
                                                blindingFactors: [String],
                                                secrets: [String])? = nil) async throws -> (paid: Bool,
                                                                                            change: [Proof]?,
                                                                                            validDLEQ: Bool) {
        let result = try await meltState(mint: mint as MintRepresenting,
                                         quoteID: quoteID,
                                         blankOutputs: blankOutputs)
        
        let change = result.change as! [CashuSwift.Proof]
        
        let dleqValid: Bool
        
        do {
            dleqValid = try Crypto.validDLEQ(for: change, with: mint)
        } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(_) {
            logger.warning("""
                           While melting with \(mint.url.absoluteString) DLEQ check could not be performed due to missing data but will still \
                           evaluate as passing because not all wallets and mint support NUT-10. \
                           future versions will consider the check failed.
                           """)
            dleqValid = true
        } catch {
            throw error
        }
        
        return (result.paid, change, dleqValid)
    }
    
    public static func melt(with quote: Quote,
                            mint: Mint,
                            proofs: [Proof],
                            timeout: Double = 600,
                            blankOutputs: (outputs: [Output],
                                           blindingFactors: [String],
                                           secrets: [String])? = nil) async throws -> (paid: Bool,
                                                                                       change: [Proof]?,
                                                                                       dleqValid: Bool) {
        
        let result = try await melt(mint: mint as MintRepresenting,
                                    quote: quote,
                                    proofs: proofs,
                                    timeout: timeout,
                                    blankOutputs: blankOutputs) as! (paid: Bool, change: [Proof]?)
        
        let dleqValid: Bool
        if let change = result.change {
            do {
                dleqValid = try Crypto.validDLEQ(for: change, with: mint)
            } catch CashuSwift.Crypto.Error.DLEQVerificationNoData(_) {
                logger.warning("""
                               While melting with \(mint.url.absoluteString) DLEQ check could not be performed due to missing data but will still \
                               evaluate as passing because not all wallets and mint support NUT-10. \
                               future versions will consider the check failed.
                               """)
                dleqValid = true
            } catch {
                throw error
            }
        } else {
            dleqValid = true
        }
        
        return (result.paid, result.change, dleqValid)
    }
}
