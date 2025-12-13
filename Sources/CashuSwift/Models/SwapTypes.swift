//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation

extension CashuSwift {
    public struct SwapRequest:Codable {
        public let inputs: [Proof]
        public let outputs:[Output]
        
        public init(inputs: [Proof], outputs: [Output]) {
            self.inputs = inputs
            self.outputs = outputs
        }
    }

    public struct SwapResponse: Codable {
        public let signatures:[Promise]
    }
}
