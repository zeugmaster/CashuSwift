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
//
//// completely overkill and unnecessary ai code to brute force a flattened JSON string keeping the original order TODO: REMOVE
//extension String {
//    func compactJSON() -> String? {
//        guard let data = self.data(using: .utf8) else { return nil }
//        
//        let decoder = JSONDecoder()
//        let encoder = JSONEncoder()
//        encoder.outputFormatting = []
//        
//        // Try decoding as a dictionary first
//        if let jsonObject = try? decoder.decode([String: AnyCodable].self, from: data),
//           let compactData = try? encoder.encode(jsonObject) {
//            return String(data: compactData, encoding: .utf8)
//        }
//        
//        // If that fails, try decoding as an array
//        if let arrayObject = try? decoder.decode([AnyCodable].self, from: data),
//           let compactData = try? encoder.encode(arrayObject) {
//            return String(data: compactData, encoding: .utf8)
//        }
//        
//        return nil
//    }
//}
//
//// AnyCodable struct (same as before)
//struct AnyCodable: Codable {
//    let value: Any
//    
//    init(_ value: Any) {
//        self.value = value
//    }
//    
//    init(from decoder: Decoder) throws {
//        let container = try decoder.singleValueContainer()
//        if let value = try? container.decode(String.self) {
//            self.value = value
//        } else if let value = try? container.decode(Int.self) {
//            self.value = value
//        } else if let value = try? container.decode(Double.self) {
//            self.value = value
//        } else if let value = try? container.decode(Bool.self) {
//            self.value = value
//        } else if let value = try? container.decode([AnyCodable].self) {
//            self.value = value.map { $0.value }
//        } else if let value = try? container.decode([String: AnyCodable].self) {
//            self.value = value.mapValues { $0.value }
//        } else {
//            self.value = NSNull()
//        }
//    }
//    
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.singleValueContainer()
//        switch value {
//        case let value as String: try container.encode(value)
//        case let value as Int: try container.encode(value)
//        case let value as Double: try container.encode(value)
//        case let value as Bool: try container.encode(value)
//        case let value as [Any]: try container.encode(value.map { AnyCodable($0) })
//        case let value as [String: Any]: try container.encode(value.mapValues { AnyCodable($0) })
//        case is NSNull, is Void: try container.encodeNil()
//        default: throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Invalid JSON value"))
//        }
//    }
//}
