//
//  LightningDecoding.swift
//  CashuSwift
//

import Foundation
import Bolt11
import Bolt12

extension CashuSwift {
    public enum LightningRequest {
        case bolt11Invoice(Invoice)
        case bolt12Offer(Bolt12Offer)
        case bolt12InvoiceRequest(Bolt12InvoiceRequest)
        case bolt12Invoice(Bolt12Invoice)
    }

    /// Decodes a Lightning payment string as either BOLT11 or BOLT12.
    ///
    /// `lightning:` URI prefixes are accepted. BOLT12 continuation separators
    /// are handled by the Bolt12 decoder.
    public static func decodeLightningRequest(_ string: String) throws -> LightningRequest {
        let payload = lightningPayloadString(string)
        let prefix = compactLightningPrefix(payload)

        if prefix.hasPrefix("lnbc") ||
            prefix.hasPrefix("lntb") ||
            prefix.hasPrefix("lntbs") ||
            prefix.hasPrefix("lnbcrt") {
            return .bolt11Invoice(try decodeBolt11Invoice(payload))
        }

        if prefix.hasPrefix("lno1") || prefix.hasPrefix("lnr1") || prefix.hasPrefix("lni1") {
            let message = try decodeBolt12Message(payload)
            switch message.kind {
            case .offer:
                guard let offer = message.offer else {
                    throw CashuError.unsupportedPaymentMethod("Could not decode BOLT12 offer.")
                }
                return .bolt12Offer(offer)
            case .invoiceRequest:
                guard let invoiceRequest = message.invoiceRequest else {
                    throw CashuError.unsupportedPaymentMethod("Could not decode BOLT12 invoice request.")
                }
                return .bolt12InvoiceRequest(invoiceRequest)
            case .invoice:
                guard let invoice = message.invoice else {
                    throw CashuError.unsupportedPaymentMethod("Could not decode BOLT12 invoice.")
                }
                return .bolt12Invoice(invoice)
            }
        }

        throw CashuError.unsupportedPaymentMethod("Unsupported Lightning request prefix.")
    }

    /// Decodes and validates a BOLT11 invoice.
    public static func decodeBolt11Invoice(_ invoice: String) throws -> Invoice {
        do {
            return try Bolt11Decoder.decode(lightningPayloadString(invoice))
        } catch {
            throw CashuError.bolt11InvalidInvoiceError(error.localizedDescription)
        }
    }

    /// Decodes a BOLT12 offer, invoice request, or invoice.
    public static func decodeBolt12Message(_ string: String) throws -> Bolt12Message {
        do {
            return try Bolt12Decoder.decode(string)
        } catch {
            throw CashuError.unsupportedPaymentMethod(error.localizedDescription)
        }
    }

    private static func lightningPayloadString(_ string: String) -> String {
        var payload = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.lowercased().hasPrefix("lightning:") {
            payload.removeFirst("lightning:".count)
        }
        return payload
    }

    private static func compactLightningPrefix(_ string: String) -> String {
        var result = ""
        for character in string {
            if character == "+" || character.isWhitespace {
                continue
            }
            result.append(character.lowercased())
            if result.count >= 6 {
                break
            }
        }
        return result
    }
}

extension CashuSwift.Bolt11.MintQuote {
    /// Decoded Lightning invoice returned by the mint for this mint quote.
    public var decodedInvoice: Invoice {
        get throws {
            try CashuSwift.decodeBolt11Invoice(request)
        }
    }
}

extension CashuSwift.Bolt11.MeltQuoteRequest {
    /// Decoded Lightning invoice the mint is being asked to pay.
    public var decodedInvoice: Invoice {
        get throws {
            try CashuSwift.decodeBolt11Invoice(request)
        }
    }
}

extension CashuSwift.Bolt11.MeltQuote {
    /// Decoded Lightning invoice for this melt quote, when the mint echoed it.
    public var decodedInvoice: Invoice? {
        get throws {
            guard let request else { return nil }
            return try CashuSwift.decodeBolt11Invoice(request)
        }
    }
}

extension CashuSwift.Bolt12.MintQuote {
    /// Decoded BOLT12 offer returned by the mint for this mint quote.
    public var decodedOffer: Bolt12Offer {
        get throws {
            try Bolt12Decoder.decodeOffer(request)
        }
    }
}

extension CashuSwift.Bolt12.MeltQuoteRequest {
    /// Decoded BOLT12 offer, invoice request, or invoice the mint is being asked to pay.
    public var decodedRequest: Bolt12Message {
        get throws {
            try CashuSwift.decodeBolt12Message(request)
        }
    }
}

extension CashuSwift.Bolt12.MeltQuote {
    /// Decoded BOLT12 payload for this melt quote, when the mint echoed it.
    public var decodedRequest: Bolt12Message? {
        get throws {
            guard let request else { return nil }
            return try CashuSwift.decodeBolt12Message(request)
        }
    }
}
