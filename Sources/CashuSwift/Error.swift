//
//  File.swift
//  
//
//  Created by zm on 15.08.24.
//

import Foundation

/// Errors that can occur when using the CashuSwift library.
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
    case invalidKeysetID(String)
    
    case spendingConditionError(String)
    
    case invalidKey(String)
    case p2pkSigningError(String)
    
    case invalidSplit(String)
    
    // NUT-18 Payment Request errors
    case paymentRequestEncoding(String)
    case paymentRequestDecoding(String)
    case paymentRequestValidation(String)
    case unsupportedTransport(String)
    case lockingConditionMismatch(String)
    case paymentRequestAmount(String)
}

extension CashuError: Equatable {
    public static func == (lhs: CashuError, rhs: CashuError) -> Bool {
        switch (lhs, rhs) {
        // Cases without associated values
        case (.networkError, .networkError),
             (.quoteNotPaid, .quoteNotPaid),
             (.blindedMessageAlreadySigned, .blindedMessageAlreadySigned),
             (.alreadySpent, .alreadySpent),
             (.transactionUnbalanced, .transactionUnbalanced),
             (.invalidToken, .invalidToken),
             (.keysetInactive, .keysetInactive),
             (.amountOutsideOfLimitRange, .amountOutsideOfLimitRange),
             (.proofsAlreadyIssuedForQuote, .proofsAlreadyIssuedForQuote),
             (.mintingDisabled, .mintingDisabled),
             (.invalidAmount, .invalidAmount),
             (.partiallySpentToken, .partiallySpentToken),
             (.quoteIsPending, .quoteIsPending),
             (.invoiceAlreadyPaid, .invoiceAlreadyPaid),
             (.quoteIsExpired, .quoteIsExpired),
             (.invalidKeysetID, .invalidKeysetID):
            return true
        
        // Cases with associated values (String)
        case (.cryptoError, .cryptoError),
             (.tokenEncoding, .tokenEncoding),
             (.tokenDecoding, .tokenDecoding),
             (.unsupportedToken, .unsupportedToken),
             (.inputError, .inputError),
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
             (.unknownError, .unknownError),
             (.spendingConditionError, .spendingConditionError),
             (.invalidKey, .invalidKey),
             (.p2pkSigningError, .p2pkSigningError),
             (.invalidSplit, .invalidSplit),
             (.paymentRequestEncoding, .paymentRequestEncoding),
             (.paymentRequestDecoding, .paymentRequestDecoding),
             (.paymentRequestValidation, .paymentRequestValidation),
             (.unsupportedTransport, .unsupportedTransport),
             (.lockingConditionMismatch, .lockingConditionMismatch),
             (.paymentRequestAmount, .paymentRequestAmount):
            return true
            
        default:
            return false
        }
    }
}


