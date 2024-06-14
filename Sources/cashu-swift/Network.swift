//
//  File.swift
//  
//
//  Created by zm on 25.05.24.
//

import Foundation

// this class should:
// make request
// check if the response is
// - ok
// - network error local
// - network error remote
// - decoding error -> throw with data to filter for protocol errors

struct Network {
    
    private init() {}
    
    enum Error: Swift.Error {
        case decoding(data: Data)
        case encoding
        case unavailable
    }
    
    ///Make a HTTP GET request to the specified URL, returns the decoded response of the expected type T or an error if decoding fails
    ///Timeout in seconds, default is 10
    static func get<T:Decodable>(url:URL, expected:T.Type, timeout:Double = 10) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw Error.unavailable
        }
        
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw Error.decoding(data: data)
        }
        
        return decoded
    }
    
    ///Make a HTTP GET request to the specified URL, returns Data if available. 
    ///Timeout in seconds, default is 10
    static func get(url:URL, timeout:Double = 10) async throws -> Data?{
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw Error.unavailable
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
        
        guard let (data, _) = try? await URLSession.shared.data(for: req) else {
            throw Error.unavailable
        }
                
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw Error.decoding(data: data)
        }
        
        return decoded
    }
}
