//
//  paymentRequest.swift
//  CashuSwift
//
//  Created for NUT-18 Payment Requests
//

import Foundation
import secp256k1

extension CashuSwift {
    
    // MARK: - Receiver Side Operations
    
    /// Creates a payment request for receiving payments.
    ///
    /// - Parameters:
    ///   - amount: Optional amount to request (if nil, sender can choose amount)
    ///   - unit: Unit for the payment (e.g., "sat", "usd")
    ///   - mints: Optional list of accepted mint URLs (if nil, any mint is accepted)
    ///   - description: Optional human-readable description
    ///   - transports: Optional list of transport methods for receiving payment
    ///   - singleUse: Whether the payment request is for single use only
    ///   - lockingPublicKey: Optional public key hex for P2PK locking requirement
    ///   - lockingTags: Optional tags for locking conditions (e.g., [["timeout", "3600"]])
    /// - Returns: The serialized payment request string
    /// - Throws: An error if creation fails
    public static func createPaymentRequest(amount: Int?,
                                           unit: String,
                                           mints: [String]?,
                                           description: String? = nil,
                                           transports: [Transport]? = nil,
                                           singleUse: Bool? = nil,
                                           lockingPublicKey: String? = nil,
                                           lockingTags: [[String]]? = nil) throws -> String {
        
        // Generate a random payment ID
        let paymentId = generateRandomId()
        
        // Create NUT-10 option if locking is requested
        var nut10: NUT10Option? = nil
        if let publicKey = lockingPublicKey {
            nut10 = NUT10Option(kind: NUT10Option.Kind.p2pk, data: publicKey, tags: lockingTags)
        }
        
        let request = PaymentRequest(
            paymentId: paymentId,
            amount: amount,
            unit: unit,
            singleUse: singleUse,
            mints: mints,
            description: description,
            transports: transports,
            lockingCondition: nut10
        )
        
        return try request.serialize()
    }
    
    /// Receives and validates a payment against a payment request.
    ///
    /// - Parameters:
    ///   - payload: The payment request payload from the sender
    ///   - request: The original payment request
    ///   - mint: The mint to use for receiving the payment
    ///   - seed: Optional seed for deterministic secret generation
    ///   - privateKey: Optional private key for unlocking P2PK-locked tokens
    /// - Returns: A `ReceiveResult` containing the received proofs and DLEQ verification results
    /// - Throws: An error if validation or receiving fails
    public static func receivePaymentRequest(payload: PaymentRequestPayload,
                                            request: PaymentRequest,
                                            mint: Mint,
                                            seed: String?,
                                            privateKey: String?) async throws -> ReceiveResult {
        
        // Validate payload against request
        try payload.validates(against: request)
        
        // Convert payload to token
        let token = payload.toToken()
        
        // Receive the token using existing receive operation
        return try await receive(token: token, of: mint, seed: seed, privateKey: privateKey)
    }
    
    /// Sends a payment request payload via HTTP POST transport.
    ///
    /// - Parameters:
    ///   - payload: The payment request payload to send
    ///   - endpoint: The HTTP endpoint URL
    /// - Returns: The HTTP response data
    /// - Throws: An error if sending fails
    public static func sendPaymentViaHTTP(payload: PaymentRequestPayload,
                                         to endpoint: String) async throws -> Data {
        
        guard let url = URL(string: endpoint) else {
            throw CashuError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CashuError.networkError
        }
        
        return data
    }
    
    // MARK: - Helper Functions
    
    /// Generates a random payment ID.
    private static func generateRandomId() -> String {
        let bytes = (0..<4).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Generates a random nonce for spending conditions.
    private static func generateRandomNonce() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Selects proofs to cover a specific amount.
    private static func selectProofs(from proofs: [Proof], amount: Int) throws -> [Proof] {
        var selected: [Proof] = []
        var total = 0
        
        // Sort proofs by amount (smallest first for better selection)
        let sortedProofs = proofs.sorted { $0.amount < $1.amount }
        
        for proof in sortedProofs {
            if total >= amount {
                break
            }
            selected.append(proof)
            total += proof.amount
        }
        
        guard total >= amount else {
            throw CashuError.insufficientInputs("Cannot select enough proofs to cover amount \(amount)")
        }
        
        return selected
    }
}

