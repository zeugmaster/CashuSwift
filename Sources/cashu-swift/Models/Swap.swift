//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation

extension CashuSwift {
    struct SwapRequest:Codable {
        let inputs: [Proof]
        let outputs:[Output]
    }

    struct SwapResponse: Codable {
        let signatures:[Promise]
    }
}
