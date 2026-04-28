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

extension CashuError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .networkError: return "Network error"
        case .cryptoError(let msg): return "Crypto error: \(msg)"
        case .quoteNotPaid: return "Quote not paid"
        case .blindedMessageAlreadySigned: return "Blinded message already signed"
        case .alreadySpent: return "Proofs already spent"
        case .transactionUnbalanced: return "Transaction unbalanced"
        case .invalidToken: return "Invalid token"
        case .tokenEncoding(let msg): return "Token encoding error: \(msg)"
        case .tokenDecoding(let msg): return "Token decoding error: \(msg)"
        case .unsupportedToken(let msg): return "Unsupported token: \(msg)"
        case .inputError(let msg): return "Input error: \(msg)"
        case .insufficientInputs(let msg): return "Insufficient inputs: \(msg)"
        case .unitIsNotSupported(let msg): return "Unit not supported: \(msg)"
        case .keysetInactive: return "Keyset inactive"
        case .amountOutsideOfLimitRange: return "Amount outside limit range"
        case .proofsAlreadyIssuedForQuote: return "Proofs already issued for quote"
        case .mintingDisabled: return "Minting disabled"
        case .typeMismatch(let msg): return "Type mismatch: \(msg)"
        case .preferredDistributionMismatch(let msg): return "Preferred distribution mismatch: \(msg)"
        case .noActiveKeysetForUnit(let msg): return "No active keyset for unit: \(msg)"
        case .unitError(let msg): return "Unit error: \(msg)"
        case .invalidAmount: return "Invalid amount"
        case .missingRequestDetail(let msg): return "Missing request detail: \(msg)"
        case .restoreError(let msg): return "Restore error: \(msg)"
        case .feeCalculationError(let msg): return "Fee calculation error: \(msg)"
        case .partiallySpentToken: return "Partially spent token"
        case .bolt11InvalidInvoiceError(let msg): return "Invalid bolt11 invoice: \(msg)"
        case .quoteIsPending: return "Quote is pending"
        case .invoiceAlreadyPaid: return "Invoice already paid"
        case .quoteIsExpired: return "Quote is expired"
        case .unknownError(let msg): return "Unknown error: \(msg)"
        case .invalidKeysetID(let msg): return "Invalid keyset ID: \(msg)"
        case .spendingConditionError(let msg): return "Spending condition error: \(msg)"
        case .invalidKey(let msg): return "Invalid key: \(msg)"
        case .p2pkSigningError(let msg): return "P2PK signing error: \(msg)"
        case .invalidSplit(let msg): return "Invalid split: \(msg)"
        case .paymentRequestEncoding(let msg): return "Payment request encoding error: \(msg)"
        case .paymentRequestDecoding(let msg): return "Payment request decoding error: \(msg)"
        case .paymentRequestValidation(let msg): return "Payment request validation error: \(msg)"
        case .unsupportedTransport(let msg): return "Unsupported transport: \(msg)"
        case .lockingConditionMismatch(let msg): return "Locking condition mismatch: \(msg)"
        case .paymentRequestAmount(let msg): return "Payment request amount error: \(msg)"
        }
    }
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


