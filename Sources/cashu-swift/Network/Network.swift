//
//  File.swift
//  
//
//  Created by zm on 25.05.24.
//

import Foundation
import OSLog

fileprivate let logger = Logger(subsystem: "cashu-swift", category: "Network")

struct Network {
    
    private init() {}
    
    enum Error: Swift.Error {
        case decoding(data: Data)
        case encoding
    }
    
    ///Make a HTTP GET request to the specified URL, returns the decoded response of the expected type T or an error if decoding fails
    ///Timeout in seconds, default is 10
    static func get<T:Decodable>(url:URL, expected:T.Type, timeout:Double = 10) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw CashuError.networkError
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw parse(data)
        }
    }
    
    ///Make a HTTP GET request to the specified URL, returns Data if available. 
    ///Timeout in seconds, default is 10
    static func get(url:URL, timeout:Double = 10) async throws -> Data?{
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw CashuError.networkError
        }

        return data
    }
    
    ///Makes a HTTP POST request to the specified URL, with the body as an object of type `I` that conforms to `Codable`
    ///returns the decoded response of the expected type `T` or an error if decoding fails
    ///Timeout in seconds, default is 10
    static func post<I:Encodable, T:Decodable>(url:URL, body:I, expected:T.Type, timeout:Double = 10) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        guard let payload = try? JSONEncoder().encode(body) else {
            throw Error.encoding
        }
        
        req.httpBody = payload
        req.timeoutInterval = timeout
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw CashuError.networkError
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw parse(data)
        }
    }
    
    static func parse(_ data:Data) -> Swift.Error {
        if let string = String(data: data, encoding: .utf8) {
            return filterErrorMessage(string)
        } else {
            return CashuError.unknownError("Could not decode server response data of lenght \(data.count) bytes.")
        }
    }
    
    static func filterErrorMessage(_ string: String) -> Swift.Error {
        switch string {
        case let s where s.contains("10002"):
            return CashuError.blindedMessageAlreadySigned
        case let s where s.contains("11001"):
            return CashuError.alreadySpent
        case let s where s.contains("11002"):
            return CashuError.transactionUnbalanced
        case let s where s.contains("11005"):
            return CashuError.unitIsNotSupported(s)
        case let s where s.contains("11006"):
            return CashuError.amountOutsideOfLimitRange
        case let s where s.contains("12002"):
            return CashuError.keysetInactive
        case let s where s.contains("20001"):
            return CashuError.quoteNotPaid
        case let s where s.contains("2001"): // to account for a typo in nutshell error codes
            return CashuError.quoteNotPaid
        case let s where s.contains("20002"):
            return CashuError.proofsAlreadyIssuedForQuote
        case let s where s.contains("20003"):
            return CashuError.mintingDisabled
        case let s where s.contains("20005"):
            return CashuError.quoteIsPending
        case let s where s.contains("20006"):
            return CashuError.invoiceAlreadyPaid
        case let s where s.contains("20007"):
            return CashuError.quoteIsExpired
        default:
            return CashuError.unknownError(string)
        }
    }
}
