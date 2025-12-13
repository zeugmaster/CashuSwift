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
    /// Melts ecash proofs to pay a Lightning invoice and returns the full quote response.
    /// - Parameters:
    ///   - quote: The Bolt11 melt quote to pay
    ///   - mint: The mint to melt with
    ///   - proofs: The proofs to melt
    ///   - timeout: Request timeout in seconds (default: 600)
    ///   - blankOutputs: Optional blank outputs for fee return
    /// - Returns: A `MeltResult` containing the quote response, optional change proofs, and DLEQ verification result
    /// - Throws: An error if the melt operation fails
    public static func melt(quote: Bolt11.MeltQuote,
                            mint: Mint,
                            proofs: [Proof],
                            timeout: Double = 600,
                            blankOutputs: (outputs: [Output],
                                           blindingFactors: [String],
                                           secrets: [String])? = nil) async throws -> MeltResult {
        
        let lightningFee: Int = quote.feeReserve
        let inputFee: Int = try calculateFee(for: proofs, of: mint)
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
        
        let dleqResult: Crypto.DLEQVerificationResult
        if let change = change {
            do {
                dleqResult = try Crypto.checkDLEQ(for: change, with: mint)
                if case .noData = dleqResult {
                    logger.warning("""
                                   While melting with \(mint.url.absoluteString) DLEQ check could not be performed due to missing data. \
                                   Not all wallets and mints support NUT-10 yet.
                                   """)
                }
            } catch {
                throw error
            }
        } else {
            dleqResult = .valid
        }
        
        return MeltResult(quote: meltResponse, change: change, dleqResult: dleqResult)
    }
    
    /// Checks the payment state of a melt quote and returns the full quote response.
    /// - Parameters:
    ///   - quoteID: The quote ID to check
    ///   - mint: The mint that issued the quote
    ///   - blankOutputs: Optional blank outputs for fee return
    /// - Returns: A `MeltResult` containing the quote response, optional change proofs, and DLEQ verification result
    /// - Throws: An error if the state cannot be retrieved
    public static func meltState(for quoteID: String,
                                 with mint: Mint,
                                 blankOutputs: (outputs: [Output],
                                                blindingFactors: [String],
                                                secrets: [String])? = nil) async throws -> MeltResult {
        let url = mint.url.appending(path: "/v1/melt/quote/bolt11/\(quoteID)")
        let quote = try await Network.get(url: url, expected: Bolt11.MeltQuote.self)
        
        var change: [Proof]?
        
        switch quote.state {
        case .paid:
            guard let promises = quote.change else {
                logger.info("quote did not contain promises for overpaid LN fees")
                return MeltResult(quote: quote, change: [], dleqResult: .valid)
            }
            
            guard let blankOutputs else {
                logger.warning("checked melt quote that returns change for overpaid LN fees, but no blankOutputs were provided.")
                return MeltResult(quote: quote, change: [], dleqResult: .valid)
            }
            
            let ids = Set(blankOutputs.outputs.map({ $0.id }))
            
            guard let id = ids.first, ids.count == 1 else {
                throw CashuError.unknownError("could not determine singular keyset id from blankOutput list. result: \(ids)")
            }
            
            guard let keyset = mint.keysets.first(where: { $0.keysetID == id }) else {
                throw CashuError.unknownError("Could not find keyset for ID \(id)")
            }
            
            do {
                change = try Crypto.unblindPromises(promises,
                                                    blindingFactors: Array(blankOutputs.blindingFactors.prefix(promises.count)),
                                                    secrets: Array(blankOutputs.secrets.prefix(promises.count)),
                                                    keyset: keyset)
            } catch {
                logger.error("Unable to unblind change form melt operation due to error: \(error). operation will still return successful.")
                change = []
            }
            
        case .pending, .unpaid:
            change = nil
            
        case .none:
            throw CashuError.unknownError("Melt quote unexpected state. \(String(describing: quote.state)) - quote id: \(quoteID)")
        }
        
        let dleqResult: Crypto.DLEQVerificationResult
        if let change = change, !change.isEmpty {
            do {
                dleqResult = try Crypto.checkDLEQ(for: change, with: mint)
                if case .noData = dleqResult {
                    logger.warning("""
                                   While checking melt state for \(mint.url.absoluteString) DLEQ check could not be performed due to missing data. \
                                   Not all wallets and mints support NUT-10 yet.
                                   """)
                }
            } catch {
                throw error
            }
        } else {
            dleqResult = .valid
        }
        
        return MeltResult(quote: quote, change: change, dleqResult: dleqResult)
    }
}
