//
//  File.swift
//  
//
//  Created by zm on 13.09.24.
//

import Foundation

public protocol MintRepresenting {
    var url:URL { get set }
    var keysets:[CashuSwift.Keyset] { get set }
//    var info:CashuSwift.MintInfo? { get set }
    
    init(url:URL, keysets:[CashuSwift.Keyset])
}

public protocol ProofRepresenting/*: Codable, Equatable*/ {
    var keysetID:String { get }
    var C:String { get }
    var secret:String { get }
    var amount:Int { get }
    
    var dleq: CashuSwift.DLEQ? { get }
    
//    var witness: String? { get }
}

