//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

extension Cashu {
    
    static func splitIntoBase2Numbers(_ n:Int) -> [Int] {
        var remaining = n
        var result: [Int] = []
        while remaining > 0 {
            var powerOfTwo = 1
            while (powerOfTwo * 2) <= remaining {
                powerOfTwo *= 2
            }
            remaining -= powerOfTwo
            result.append(powerOfTwo)
        }
        return result
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
