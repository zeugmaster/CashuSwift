//
//  File.swift
//  
//
//  Created by zm on 15.06.24.
//

import Foundation

extension CashuSwift {
    static func splitIntoBase2Numbers(_ n:Int) -> [Int] {
        (0 ..< Int.bitWidth - n.leadingZeroBitCount)
            .map { 1 << $0 }
            .filter { n & $0 != 0 }
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
