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
    
    case insufficientInputs(String)
    
    case noKeysetForUnit(String)
    
    case typeMismatch(String)
    
    case preferredDistributionMismatch(String)
    
    case noActiveKeysetForUnit(String)
    
    case unitError(String)
    
    case invalidAmount
    
    case missingRequestDetail(String)
    
    case restoreError(String)
    
    case feeCalculationError(String)
}

