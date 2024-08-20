//
//  File.swift
//  
//
//  Created by zm on 15.08.24.
//

import Foundation

enum CashuError: Swift.Error {
    case quoteNotPaid
    case duplicateOutput
    case alreadySpent
    case transactionUnbalanced
    case invalidToken
    case tokenEncoding
    case tokenDecoding
    case inputError(String)
    case insufficientInputs
    
    case typeMismatch
    
    case preferredDistributionMismatch
    
    case noActiveKeyset
    
    case unit
    
    case invalidAmount
}

