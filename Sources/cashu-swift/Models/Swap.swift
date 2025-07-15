//
//  File.swift
//  
//
//  Created by zm on 03.08.24.
//

import Foundation

// Move types outside of extension to ensure proper symbol export
public struct CashuSwapRequest: Codable {
    public let inputs: [CashuSwift.Proof]
    public let outputs: [CashuSwift.Output]
    
    public init(inputs: [CashuSwift.Proof], outputs: [CashuSwift.Output]) {
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct CashuSwapResponse: Codable {
    public let signatures: [CashuSwift.Promise]
    
    public init(signatures: [CashuSwift.Promise]) {
        self.signatures = signatures
    }
}

// Keep the extension types for backward compatibility within CashuSwift
extension CashuSwift {
    typealias SwapRequest = CashuSwapRequest
    typealias SwapResponse = CashuSwapResponse
}
