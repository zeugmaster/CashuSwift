//
//  File.swift
//  
//
//  Created by zm on 15.08.24.
//

import Foundation

public enum CashuError: Swift.Error {
    
    case networkError
    case cryptoError(String)
    
    case quoteNotPaid // 20001
    case blindedMessageAlreadySigned // 10002
    case alreadySpent // 11001
    case transactionUnbalanced // 11002
    case invalidToken
    case tokenEncoding(String)
    case tokenDecoding(String)
    case unsupportedToken(String)
    case inputError(String)
    case insufficientInputs(String)
    case unitIsNotSupported(String) // 11005
    case keysetInactive // 12002
    case amountOutsideOfLimitRange // 11006
    case proofsAlreadyIssuedForQuote // 20002
    case mintingDisabled // 20003
    case typeMismatch(String)
    case preferredDistributionMismatch(String)
    case noActiveKeysetForUnit(String)
    case unitError(String)
    case invalidAmount
    case missingRequestDetail(String)
    case restoreError(String)
    case feeCalculationError(String)
    case partiallySpentToken
    case bolt11InvalidInvoiceError(String)
    case quoteIsPending // 20005
    case invoiceAlreadyPaid // 20006
    case quoteIsExpired // 20007
    case unknownError(String)
}

extension CashuError: Equatable {
    public static func == (lhs: CashuError, rhs: CashuError) -> Bool {
        switch (lhs, rhs) {
        case (.quoteNotPaid, .quoteNotPaid),
             (.blindedMessageAlreadySigned, .blindedMessageAlreadySigned),
             (.alreadySpent, .alreadySpent),
             (.transactionUnbalanced, .transactionUnbalanced),
             (.invalidToken, .invalidToken),
             (.tokenEncoding, .tokenEncoding),
             (.tokenDecoding, .tokenDecoding),
             (.keysetInactive, .keysetInactive),
             (.amountOutsideOfLimitRange, .amountOutsideOfLimitRange),
             (.proofsAlreadyIssuedForQuote, .proofsAlreadyIssuedForQuote),
             (.mintingDisabled, .mintingDisabled),
             (.invalidAmount, .invalidAmount),
             (.partiallySpentToken, .partiallySpentToken),
             (.quoteIsPending, .quoteIsPending),
             (.invoiceAlreadyPaid, .invoiceAlreadyPaid),
             (.quoteIsExpired, .quoteIsExpired):
            return true
            
        case (.inputError, .inputError),
             (.insufficientInputs, .insufficientInputs),
             (.unitIsNotSupported, .unitIsNotSupported),
             (.typeMismatch, .typeMismatch),
             (.preferredDistributionMismatch, .preferredDistributionMismatch),
             (.noActiveKeysetForUnit, .noActiveKeysetForUnit),
             (.unitError, .unitError),
             (.missingRequestDetail, .missingRequestDetail),
             (.restoreError, .restoreError),
             (.feeCalculationError, .feeCalculationError),
             (.bolt11InvalidInvoiceError, .bolt11InvalidInvoiceError),
             (.unknownError, .unknownError):
            return true
            
        default:
            return false
        }
    }
}


