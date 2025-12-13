//
//  PaymentRequest.swift
//  CashuSwift
//
//  Created for NUT-18 Payment Requests
//

import Foundation
import SwiftCBOR

// MARK: - Transport

extension CashuSwift {
    /// Represents a transport method for sending payment request payloads.
    ///
    /// Transports specify how the sender should deliver the payment to the receiver.
    public struct Transport: Codable, Equatable, Hashable, Sendable, Identifiable {
        
        public var id: String {
            type + target
        }
        
        /// The type of transport (e.g., "nostr", "post")
        public let type: String
        
        /// The target address for the transport (e.g., URL, nostr identifier)
        public let target: String
        
        /// Optional tags providing additional transport information
        public let tags: [[String]]?
        
        enum CodingKeys: String, CodingKey {
            case type = "t"
            case target = "a"
            case tags = "g"
        }
        
        /// Creates a new transport instance.
        /// - Parameters:
        ///   - type: The type of transport
        ///   - target: The target address
        ///   - tags: Optional tags for additional transport features
        public init(type: String, target: String, tags: [[String]]? = nil) {
            self.type = type
            self.target = target
            self.tags = tags
        }
        
        /// Transport type constants
        public enum TransportType {
            public static let nostr = "nostr"
            public static let httpPost = "post"
        }
        
        /// Parses tags into a dictionary mapping tag keys to their values.
        /// - Returns: Dictionary where keys are tag names and values are arrays of tag values
        public func parsedTags() -> [String: [String]] {
            guard let tagArray = tags else { return [:] }
            var result: [String: [String]] = [:]
            
            for tag in tagArray {
                guard tag.count >= 2 else { continue }
                let key = tag[0]
                let values = Array(tag.dropFirst())
                result[key, default: []].append(contentsOf: values)
            }
            
            return result
        }
        
        /// Checks if the transport supports a specific tag value.
        /// - Parameters:
        ///   - key: The tag key to check
        ///   - value: The tag value to look for
        /// - Returns: True if the tag is present with the specified value
        public func hasTag(key: String, value: String) -> Bool {
            let parsed = parsedTags()
            return parsed[key]?.contains(value) ?? false
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a Transport from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for Transport")
            }
            
            guard let typeValue = cborMap[.utf8String("t")]?.asString(),
                  let targetValue = cborMap[.utf8String("a")]?.asString() else {
                throw CashuError.paymentRequestDecoding("Missing required fields in Transport")
            }
            
            self.type = typeValue
            self.target = targetValue
            
            // Decode optional tags
            if let tagsArray = cborMap[.utf8String("g")]?.asArray() {
                var tagsList: [[String]] = []
                for tagCBOR in tagsArray {
                    if let tagArray = tagCBOR.asArray() {
                        let stringTags = tagArray.compactMap { $0.asString() }
                        if !stringTags.isEmpty {
                            tagsList.append(stringTags)
                        }
                    }
                }
                self.tags = tagsList.isEmpty ? nil : tagsList
            } else {
                self.tags = nil
            }
        }
        
        /// Encodes the Transport to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [
                .utf8String("t"): .utf8String(type),
                .utf8String("a"): .utf8String(target)
            ]
            
            if let tagsList = tags, !tagsList.isEmpty {
                let tagsArray = tagsList.map { tag in
                    CBOR.array(tag.map { CBOR.utf8String($0) })
                }
                cborMap[.utf8String("g")] = .array(tagsArray)
            }
            
            return .map(cborMap)
        }
    }
}

// MARK: - NUT10Option

extension CashuSwift {
    /// Represents a NUT-10 locking condition option for payment requests.
    ///
    /// This specifies the required spending condition that the sender must apply to the payment.
    public struct NUT10Option: Codable, Equatable, Hashable, Sendable {
        
        /// The kind of spending condition (e.g., "P2PK", "HTLC")
        public let kind: String
        
        /// The data for the spending condition (e.g., public key hex, hash)
        public let data: String
        
        /// Optional tags for additional constraints
        public let tags: [[String]]?
        
        enum CodingKeys: String, CodingKey {
            case kind = "k"
            case data = "d"
            case tags = "t"
        }
        
        /// Creates a new NUT-10 option instance.
        /// - Parameters:
        ///   - kind: The kind of spending condition
        ///   - data: The data for the spending condition
        ///   - tags: Optional tags for additional constraints
        public init(kind: String, data: String, tags: [[String]]? = nil) {
            self.kind = kind
            self.data = data
            self.tags = tags
        }
        
        /// Common kind constants
        public enum Kind {
            public static let p2pk = "P2PK"
            public static let htlc = "HTLC"
        }
        
        /// Parses tags into a dictionary mapping tag keys to their values.
        /// - Returns: Dictionary where keys are tag names and values are arrays of tag values
        public func parsedTags() -> [String: [String]] {
            guard let tagArray = tags else { return [:] }
            var result: [String: [String]] = [:]
            
            for tag in tagArray {
                guard tag.count >= 2 else { continue }
                let key = tag[0]
                let values = Array(tag.dropFirst())
                result[key, default: []].append(contentsOf: values)
            }
            
            return result
        }
        
        /// Converts this NUT-10 option to a SpendingCondition.
        /// - Parameter nonce: A random nonce for the spending condition
        /// - Returns: A SpendingCondition instance
        /// - Throws: An error if the conversion fails
        public func toSpendingCondition(nonce: String) throws -> SpendingCondition {
            guard let conditionKind = SpendingCondition.Kind(rawValue: kind) else {
                throw CashuError.spendingConditionError("Unknown spending condition kind: \(kind)")
            }
            
            // Convert tags to SpendingCondition.Tag format
            var conditionTags: [SpendingCondition.Tag]? = nil
            if let tagArray = tags {
                conditionTags = try tagArray.compactMap { tag in
                    guard tag.count >= 2 else { return nil }
                    let key = tag[0]
                    let values = Array(tag.dropFirst())
                    
                    switch key {
                    case "sigflag":
                        return .sigflag(values: values)
                    case "pubkeys":
                        return .pubkeys(values: values)
                    case "refund":
                        return .refund(values: values)
                    case "n_sigs":
                        let intValues = try values.map { value in
                            guard let intValue = Int(value) else {
                                throw CashuError.spendingConditionError("Invalid integer value in n_sigs tag: \(value)")
                            }
                            return intValue
                        }
                        return .n_sigs(values: intValues)
                    case "locktime", "timeout":
                        let intValues = try values.map { value in
                            guard let intValue = Int(value) else {
                                throw CashuError.spendingConditionError("Invalid integer value in \(key) tag: \(value)")
                            }
                            return intValue
                        }
                        return .locktime(values: intValues)
                    default:
                        return nil
                    }
                }
            }
            
            let payload = SpendingCondition.Payload(
                nonce: nonce,
                data: data,
                tags: conditionTags
            )
            
            return SpendingCondition(kind: conditionKind, payload: payload)
        }
        
        /// Creates a NUT-10 option from a SpendingCondition.
        /// - Parameter spendingCondition: The spending condition to convert
        /// - Returns: A NUT10Option instance
        public static func from(spendingCondition: SpendingCondition) -> NUT10Option {
            let kindValue = spendingCondition.kind.rawValue
            let dataValue = spendingCondition.payload.data
            
            // Convert tags to NUT-10 format
            var tagsArray: [[String]]? = nil
            if let conditionTags = spendingCondition.payload.tags {
                tagsArray = conditionTags.map { tag in
                    switch tag {
                    case .sigflag(let values):
                        return ["sigflag"] + values
                    case .n_sigs(let values):
                        return ["n_sigs"] + values.map { String($0) }
                    case .pubkeys(let values):
                        return ["pubkeys"] + values
                    case .locktime(let values):
                        return ["locktime"] + values.map { String($0) }
                    case .refund(let values):
                        return ["refund"] + values
                    }
                }
            }
            
            return NUT10Option(kind: kindValue, data: dataValue, tags: tagsArray)
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a NUT10Option from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for NUT10Option")
            }
            
            guard let kindValue = cborMap[.utf8String("k")]?.asString(),
                  let dataValue = cborMap[.utf8String("d")]?.asString() else {
                throw CashuError.paymentRequestDecoding("Missing required fields in NUT10Option")
            }
            
            self.kind = kindValue
            self.data = dataValue
            
            // Decode optional tags
            if let tagsArray = cborMap[.utf8String("t")]?.asArray() {
                var tagsList: [[String]] = []
                for tagCBOR in tagsArray {
                    if let tagArray = tagCBOR.asArray() {
                        let stringTags = tagArray.compactMap { $0.asString() }
                        if !stringTags.isEmpty {
                            tagsList.append(stringTags)
                        }
                    }
                }
                self.tags = tagsList.isEmpty ? nil : tagsList
            } else {
                self.tags = nil
            }
        }
        
        /// Encodes the NUT10Option to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [
                .utf8String("k"): .utf8String(kind),
                .utf8String("d"): .utf8String(data)
            ]
            
            if let tagsList = tags, !tagsList.isEmpty {
                let tagsArray = tagsList.map { tag in
                    CBOR.array(tag.map { CBOR.utf8String($0) })
                }
                cborMap[.utf8String("t")] = .array(tagsArray)
            }
            
            return .map(cborMap)
        }
    }
}

// MARK: - PaymentRequest

extension CashuSwift {
    /// Represents a Cashu payment request (NUT-18).
    ///
    /// Payment requests allow receivers to specify requirements for incoming payments,
    /// such as amount, unit, accepted mints, and locking conditions.
    public struct PaymentRequest: Codable, Equatable, Hashable, Sendable {
        
        /// Payment ID to be included in the payment payload
        public let paymentId: String?
        
        /// The amount of the requested payment
        public let amount: Int?
        
        /// The unit of the requested payment (MUST be set if amount is set)
        public let unit: String?
        
        /// Whether the payment request is for single use
        public let singleUse: Bool?
        
        /// A set of mints from which the payment is requested
        public let mints: [String]?
        
        /// A human readable description
        public let description: String?
        
        /// The method of transport chosen to transmit the payment
        public let transports: [Transport]?
        
        /// The required NUT-10 locking condition
        public let lockingCondition: NUT10Option?
        
        enum CodingKeys: String, CodingKey {
            case paymentId = "i"
            case amount = "a"
            case unit = "u"
            case singleUse = "s"
            case mints = "m"
            case description = "d"
            case transports = "t"
            case lockingCondition = "nut10"
        }
        
        /// Creates a new payment request instance.
        /// - Parameters:
        ///   - paymentId: Optional payment ID
        ///   - amount: Optional amount
        ///   - unit: Optional unit (required if amount is set)
        ///   - singleUse: Optional single-use flag
        ///   - mints: Optional array of accepted mint URLs
        ///   - description: Optional description
        ///   - transports: Optional array of transport methods
        ///   - lockingCondition: Optional NUT-10 locking condition
        public init(paymentId: String?, amount: Int?, unit: String?, singleUse: Bool?, mints: [String]?, description: String?, transports: [Transport]?, lockingCondition: NUT10Option?) {
            self.paymentId = paymentId
            self.amount = amount
            self.unit = unit
            self.singleUse = singleUse
            self.mints = mints
            self.description = description
            self.transports = transports
            self.lockingCondition = lockingCondition
        }
        
        /// Validates the payment request.
        /// - Throws: An error if the request is invalid
        public func validate() throws {
            // If amount is set, unit must be set
            if amount != nil && unit == nil {
                throw CashuError.paymentRequestValidation("Unit must be set when amount is specified")
            }
        }
        
        /// Checks if a mint URL is accepted by this payment request.
        /// - Parameter mintURL: The mint URL to check
        /// - Returns: True if the mint is accepted (or if no mint constraint is specified)
        public func acceptsMint(_ mintURL: String) -> Bool {
            guard let acceptedMints = mints else { return true }
            return acceptedMints.contains(mintURL)
        }
        
        /// Checks if a specific amount and unit satisfy this payment request.
        /// - Parameters:
        ///   - amount: The amount to check
        ///   - unit: The unit to check
        /// - Returns: True if the amount and unit satisfy the request
        public func satisfiesAmountAndUnit(amount amountValue: Int, unit unitValue: String) -> Bool {
            // Check unit
            if let requiredUnit = unit, requiredUnit != unitValue {
                return false
            }
            
            // Check amount
            if let requiredAmount = amount, requiredAmount != amountValue {
                return false
            }
            
            return true
        }
        
        // MARK: - CBOR Encoding/Decoding
        
        /// Decodes a PaymentRequest from CBOR
        init(fromCBOR cbor: CBOR) throws {
            guard let cborMap = cbor.asMap() else {
                throw CashuError.paymentRequestDecoding("Expected CBOR map for PaymentRequest")
            }
            
            // Decode optional fields
            self.paymentId = cborMap[.utf8String("i")]?.asString()
            
            if let amountUInt = cborMap[.utf8String("a")]?.asUnsignedInt() {
                self.amount = Int(amountUInt)
            } else {
                self.amount = nil
            }
            
            self.unit = cborMap[.utf8String("u")]?.asString()
            
            if case .boolean(let singleUseValue) = cborMap[.utf8String("s")] {
                self.singleUse = singleUseValue
            } else {
                self.singleUse = nil
            }
            
            // Decode mint array
            if let mintsArray = cborMap[.utf8String("m")]?.asArray() {
                self.mints = mintsArray.compactMap { $0.asString() }
            } else {
                self.mints = nil
            }
            
            self.description = cborMap[.utf8String("d")]?.asString()
            
            // Decode transport array
            if let transportsArray = cborMap[.utf8String("t")]?.asArray() {
                self.transports = try transportsArray.map { try CashuSwift.Transport(fromCBOR: $0) }
            } else {
                self.transports = nil
            }
            
            // Decode NUT-10 option
            if let nut10CBOR = cborMap[.utf8String("nut10")] {
                self.lockingCondition = try CashuSwift.NUT10Option(fromCBOR: nut10CBOR)
            } else {
                self.lockingCondition = nil
            }
        }
        
        /// Encodes the PaymentRequest to CBOR
        func toCBOR() -> CBOR {
            var cborMap: [CBOR: CBOR] = [:]
            
            // Encode only non-nil fields
            if let id = paymentId {
                cborMap[.utf8String("i")] = .utf8String(id)
            }
            
            if let amt = amount {
                cborMap[.utf8String("a")] = .unsignedInt(UInt64(amt))
            }
            
            if let u = unit {
                cborMap[.utf8String("u")] = .utf8String(u)
            }
            
            if let single = singleUse {
                cborMap[.utf8String("s")] = .boolean(single)
            }
            
            if let mintList = mints, !mintList.isEmpty {
                cborMap[.utf8String("m")] = .array(mintList.map { .utf8String($0) })
            }
            
            if let desc = description {
                cborMap[.utf8String("d")] = .utf8String(desc)
            }
            
            if let transportList = transports, !transportList.isEmpty {
                cborMap[.utf8String("t")] = .array(transportList.map { $0.toCBOR() })
            }
            
            if let locking = lockingCondition {
                cborMap[.utf8String("nut10")] = locking.toCBOR()
            }
            
            return .map(cborMap)
        }
        
        // MARK: - Serialization
        
        /// Serializes the payment request to an encoded string.
        /// - Returns: The encoded payment request string with "creqA" prefix
        /// - Throws: An error if serialization fails
        public func serialize() throws -> String {
            try validate()
            
            let cborValue = self.toCBOR()
            let cborData = cborValue.encode()
            
            let base64URLSafe = Data(cborData).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
            
            return "creqA\(base64URLSafe)"
        }
        
        /// Initializes a PaymentRequest from an encoded string.
        /// - Parameter encodedRequest: The encoded payment request string
        /// - Throws: An error if decoding fails
        public init(encodedRequest: String) throws {
            guard encodedRequest.hasPrefix("creqA") else {
                throw CashuError.paymentRequestDecoding("Payment request must start with 'creqA'")
            }
            
            let base64URLSafeString = String(encodedRequest.dropFirst(5))
            
            guard let cborData = base64URLSafeString.decodeBase64UrlSafe() else {
                throw CashuError.paymentRequestDecoding("Could not decode base64 string")
            }
            
            guard let cborValue = try? CBOR.decode([UInt8](cborData)) else {
                throw CashuError.paymentRequestDecoding("Could not decode CBOR data")
            }
            
            self = try CashuSwift.PaymentRequest(fromCBOR: cborValue)
            try self.validate()
        }
    }
}

// MARK: - PaymentRequestPayload

extension CashuSwift {
    /// Represents the payload sent from sender to receiver for a payment request.
    ///
    /// This is the actual payment data transmitted via the chosen transport method.
    public struct PaymentRequestPayload: Codable, Equatable, Sendable {
        
        /// Payment ID corresponding to the payment request
        public let id: String?
        
        /// Optional memo from the sender
        public let memo: String?
        
        /// The mint URL from which the ecash is from
        public let mint: String
        
        /// The unit of the payment
        public let unit: String
        
        /// The array of proofs (ecash) for the payment
        public let proofs: [Proof]
        
        /// Creates a new payment request payload instance.
        /// - Parameters:
        ///   - id: Optional payment ID from the payment request
        ///   - memo: Optional memo from the sender
        ///   - mint: The mint URL
        ///   - unit: The unit of the payment
        ///   - proofs: The proofs for the payment
        public init(id: String?, memo: String?, mint: String, unit: String, proofs: [Proof]) {
            self.id = id
            self.memo = memo
            self.mint = mint
            self.unit = unit
            self.proofs = proofs
        }
        
        /// Calculates the total amount of the payment.
        /// - Returns: The sum of all proof amounts
        public func totalAmount() -> Int {
            return proofs.reduce(0) { $0 + $1.amount }
        }
        
        /// Validates that the payload satisfies a payment request.
        /// - Parameter request: The payment request to validate against
        /// - Throws: An error if validation fails
        public func validates(against request: PaymentRequest) throws {
            // Check payment ID matches
            if let requestId = request.paymentId, requestId != id {
                throw CashuError.paymentRequestValidation("Payment ID mismatch: expected '\(requestId)', got '\(id ?? "nil")'")
            }
            
            // Check unit matches
            if let requestUnit = request.unit, requestUnit != unit {
                throw CashuError.paymentRequestValidation("Unit mismatch: expected '\(requestUnit)', got '\(unit)'")
            }
            
            // Check amount matches
            if let requestAmount = request.amount {
                let total = totalAmount()
                if total != requestAmount {
                    throw CashuError.paymentRequestValidation("Amount mismatch: expected \(requestAmount), got \(total)")
                }
            }
            
            // Check mint is accepted
            if let acceptedMints = request.mints, !acceptedMints.contains(mint) {
                throw CashuError.paymentRequestValidation("Mint '\(mint)' is not in the accepted mints list")
            }
            
            // Check locking conditions if specified
            if let nut10 = request.lockingCondition {
                try validateLockingConditions(nut10: nut10)
            }
        }
        
        /// Validates that the proofs have the required locking conditions.
        /// - Parameter nut10: The required NUT-10 locking condition
        /// - Throws: An error if the locking conditions are not met
        private func validateLockingConditions(nut10: NUT10Option) throws {
            // Check that all proofs have the required spending condition
            for proof in proofs {
                guard let spendingCondition = SpendingCondition.deserialize(from: proof.secret) else {
                    throw CashuError.lockingConditionMismatch("Proof does not have a spending condition")
                }
                
                // Check kind matches
                if spendingCondition.kind.rawValue != nut10.kind {
                    throw CashuError.lockingConditionMismatch("Spending condition kind mismatch: expected '\(nut10.kind)', got '\(spendingCondition.kind.rawValue)'")
                }
                
                // Check data matches (public key, hash, etc.)
                if spendingCondition.payload.data != nut10.data {
                    throw CashuError.lockingConditionMismatch("Spending condition data mismatch")
                }
                
                // Validate tags if specified
                let requestedTags = nut10.parsedTags()
                if !requestedTags.isEmpty {
                    let proofTags = spendingCondition.payload.tags ?? []
                    
                    // Check for timeout/locktime requirements
                    if let timeoutValues = requestedTags["timeout"] ?? requestedTags["locktime"],
                       let minTimeout = timeoutValues.compactMap({ Int($0) }).first {
                        
                        var hasValidTimeout = false
                        for tag in proofTags {
                            if case .locktime(let values) = tag {
                                if let proofTimeout = values.first, proofTimeout >= minTimeout {
                                    hasValidTimeout = true
                                    break
                                }
                            }
                        }
                        
                        if !hasValidTimeout {
                            throw CashuError.lockingConditionMismatch("Proof does not have required timeout of at least \(minTimeout) seconds")
                        }
                    }
                }
            }
        }
        
        /// Serializes the payload to a compact JSON string (no whitespace).
        /// - Returns: A JSON string representation of the payload
        /// - Throws: An error if encoding fails
        public func toJSONString() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = []
            let data = try encoder.encode(self)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw CashuError.paymentRequestEncoding("Failed to convert JSON data to string")
            }
            return jsonString
        }
        
        /// Parses a PaymentRequestPayload from a JSON string.
        /// - Parameter jsonString: The JSON string to parse
        /// - Returns: A PaymentRequestPayload instance
        /// - Throws: An error if decoding fails
        public static func from(jsonString: String) throws -> PaymentRequestPayload {
            guard let data = jsonString.data(using: .utf8) else {
                throw CashuError.paymentRequestDecoding("Failed to convert JSON string to data")
            }
            let decoder = JSONDecoder()
            return try decoder.decode(PaymentRequestPayload.self, from: data)
        }
        
        /// Converts the payload to a Token object.
        /// - Returns: A Token instance
        public func toToken() -> Token {
            return Token(proofs: [mint: proofs], unit: unit, memo: memo)
        }
        
        /// Creates a PaymentRequestPayload from a Token and optional payment request.
        /// - Parameters:
        ///   - token: The token to convert
        ///   - request: Optional payment request to extract ID from
        /// - Returns: A PaymentRequestPayload instance
        /// - Throws: An error if the token has multiple mints
        public static func from(token: Token, request: PaymentRequest?) throws -> PaymentRequestPayload {
            guard token.proofsByMint.count == 1 else {
                throw CashuError.invalidToken
            }
            
            guard let (mintURL, proofs) = token.proofsByMint.first else {
                throw CashuError.invalidToken
            }
            
            return PaymentRequestPayload(
                id: request?.paymentId,
                memo: token.memo,
                mint: mintURL,
                unit: token.unit,
                proofs: proofs
            )
        }
    }
}
