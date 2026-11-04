//
//  File.swift
//  
//
//  Created by zm on 13.09.24.
//

import Foundation

/// Protocol for types that can represent a mint.
public protocol MintRepresenting {
    /// The URL of the mint.
    var url:URL { get set }
    
    /// The keysets available on this mint.
    var keysets:[CashuSwift.Keyset] { get set }
//    var info:CashuSwift.MintInfo? { get set }
    
    /// Creates a new mint representation.
    /// - Parameters:
    ///   - url: The URL of the mint
    ///   - keysets: The keysets available on this mint
    init(url:URL, keysets:[CashuSwift.Keyset])
}

/// Protocol for types that can represent a proof.
public protocol ProofRepresenting/*: Codable, Equatable*/ {
    /// The keyset ID this proof belongs to.
    var keysetID:String { get }
    
    /// The blinded signature.
    var C:String { get }
    
    /// The secret used to generate this proof.
    var secret:String { get }
    
    /// The amount value of this proof.
    var amount:Int { get }
    
    /// Optional DLEQ proof.
    var dleq: CashuSwift.DLEQ? { get }
    
    /// NUT-00 spend info of a v3 proof. Defaults to `nil` for conformers that do not persist it;
    /// a v3 proof without it cannot be spent, so wallets must store it.
    var spendInfo: CashuSwift.SpendInfo? { get }
    
//    var witness: String? { get }
}

public extension ProofRepresenting {
    var spendInfo: CashuSwift.SpendInfo? { nil }
}

