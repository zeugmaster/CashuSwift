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

enum NetworkError: Error {
    case decoding(data: Data)
    case encoding
    case unavailable
}

class Network {
    
    ///Make a HTTP GET request to the specified URL, returns the decoded response of the expected type T or an error if decoding fails
    ///Timeout in seconds, default is 10
    static func get<T:Codable>(url:URL, expected:T.Type, timeout:Double = 10) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse, 
                  httpResponse.statusCode == 200 else {
            throw NetworkError.unavailable
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw NetworkError.decoding(data: data)
        }
        return decoded
    }
    
    static func post<T:Codable>(url:URL, body:Any, expected:T.Type) throws -> T {
        fatalError()
    }
}
