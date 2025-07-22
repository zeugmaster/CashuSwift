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
    /// Requests a quote from a mint for minting or melting tokens.
    /// - Parameters:
    ///   - mint: The mint to request the quote from
    ///   - quoteRequest: The quote request details (either `RequestMintQuote` or `RequestMeltQuote`)
    /// - Returns: A quote response from the mint
    /// - Throws: `CashuError.unitIsNotSupported` if the mint doesn't support the requested unit
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
    

}
