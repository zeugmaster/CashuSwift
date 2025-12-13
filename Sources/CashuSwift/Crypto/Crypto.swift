//
//  b_dhke.swift
//  macadamia-cli
//
//
import Foundation
import CryptoKit
import secp256k1
import BIP32
import BigNumber
import OSLog

fileprivate let logger = Logger(subsystem: "cashu-swift", category: "cryptography")

extension CashuSwift {
    /// Cryptographic operations for the Cashu protocol.
    public enum Crypto {
        
        /// Errors that can occur during cryptographic operations.
        enum Error: Swift.Error, CustomStringConvertible {
            var description: String {
                switch self {
                case .secretDerivation(let message):
                    return "Secret Derivation Error: \(message ?? "Unknown error")"
                case .unblinding(let message):
                    return "Unblinding Error: \(message ?? "Unknown error")"
                case .hashToCurve(let message):
                    return "Hash to Curve Error: \(message ?? "Unknown error")"
                case .DLEQVerificationNoData(let message):
                    return "DLEQ Verification Error: \(message)"
                case .DLEQVerificationUnknownKeyset(let message):
                    return "DLEQ Verification Error: \(message)"
                default:
                    return String(describing: self)
                }
            }
            
            case secretDerivation(String?)
            case unblinding(String?)
            case hashToCurve(String?)
            case DLEQVerificationNoData(String)
            case DLEQVerificationUnknownKeyset(String)
            case invalidSecret(String)
        }
        
        typealias PrivateKey = secp256k1.Signing.PrivateKey
        typealias PublicKey = secp256k1.Signing.PublicKey
        
        /// Result of a DLEQ verification.
        public enum DLEQVerificationResult: Sendable, Codable {
            /// The DLEQ proof is valid.
            case valid
            /// The DLEQ proof verification failed.
            case fail
            /// No DLEQ data was available for verification.
            case noData
        }
        
        //MARK: - OUTPUT GENERATION
        
        /// Generate a list of blinded `Output`s and corresponding blindingFactors and secrets for later unblinding Promises from the Mint.
        /// Not specifying `deterministicFactors` will give you random outputs that can not be recreated via seed phrase backup
        static func generateOutputs(amounts:[Int],
                                    keysetID:String,
                                    deterministicFactors:(seed:String,
                                                          counter:Int)? = nil)  throws -> (outputs: [Output],
                                                                                           blindingFactors: [String],
                                                                                           secrets:[String]) {

            var outputs = [Output]()
            var blindingFactors = [String]()
            var secrets = [String]()
            
            for i in 0..<amounts.count {
                if let deterministicFactors = deterministicFactors {
                    let index = deterministicFactors.counter + i
                    let deterministic = try generateDeterministicOutput(keysetID: keysetID,
                                                                    seed: deterministicFactors.seed,
                                                                    index: index)
                    outputs.append(Output(amount: amounts[i],
                                          B_: deterministic.output.stringRepresentation,
                                          id: keysetID))
                    blindingFactors.append(deterministic.blindingFactor.stringRepresentation)
                    secrets.append(deterministic.secret)
                } else {
                    let random = try generateRandomOutput()
                    outputs.append(Output(amount: amounts[i],
                                          B_: random.output.stringRepresentation,
                                          id: keysetID))
                    blindingFactors.append(random.blindingFactor.stringRepresentation)
                    secrets.append(random.secret)
                }
            }
            
            return (outputs, blindingFactors, secrets)
        }
        
        private static func generateRandomOutput() throws -> (output:PublicKey,
                                                              blindingFactor: PrivateKey,
                                                              secret:String) {
        let x = try PrivateKey()
        
        let xString = String(bytes: x.dataRepresentation)
        
        let Y = try secureHashToCurve(message: xString)
        
        let r = try PrivateKey()
        let B_ = try Y.combine([r.publicKey])
        
        logger.debug("Created random Output, blindingFactor and secret")
        
        return (B_, r, xString)
    }
        
        private static func generateDeterministicOutput(keysetID:String,
                                                        seed:String,
                                                        index:Int) throws -> (output:PublicKey,
                                                                              blindingFactor: PrivateKey,
                                                                              secret:String) {
            // determine keyset id version based on prefix
            if keysetID.hasPrefix("01") {
                return try v1deterministicOutput(keysetID: keysetID, seed: seed, index: index)
            } else {
                return try v0deterministicOutput(keysetID: keysetID, seed: seed, index: index)
            }
        }
         
        private static func v0deterministicOutput(keysetID: String,
                                                  seed: String,
                                                  index: Int) throws -> (output:PublicKey,
                                                                         blindingFactor: PrivateKey,
                                                                         secret:String) {
            let keysetInt = keysetID.count == 16 ? convertHexKeysetID(keysetID: keysetID)! : convertKeysetID(keysetID: keysetID)!
            
            let secretPath = "m/129372'/0'/\(keysetInt)'/\(index)'/0"
            let blindingFactorPath = "m/129372'/0'/\(keysetInt)'/\(index)'/1"
            
            let x = try childPrivateKeyForDerivationPath(seed: seed, derivationPath: secretPath)
            
            let xString = String(bytes: x.dataRepresentation)
            
            let Y = try secureHashToCurve(message: xString)
            
            let r = try childPrivateKeyForDerivationPath(seed: seed,
                                                             derivationPath: blindingFactorPath)
            let B_ = try Y.combine([r.publicKey])
            
            logger.debug(
                    """
                    Created secrets with derivation path \(secretPath, privacy: .public), \
                    for keysetID: \(keysetID), output: ...\(B_.stringRepresentation.suffix(10))
                    """
            )
            
            return (B_, r, xString)
        }
        
        private static func v1deterministicOutput(keysetID: String,
                                                  seed: String,
                                                  index: Int) throws -> (output:PublicKey,
                                                                         blindingFactor: PrivateKey,
                                                                         secret:String) {
            
            let seedBytes = try seed.bytes
            
            var indexBigEndian = index.bigEndian
            let indexBytes = withUnsafeBytes(of: &indexBigEndian, { Array($0) })
            let message = Array("Cashu_KDF_HMAC_SHA256".utf8) + (try keysetID.bytes) + indexBytes
            
            // Step 2: Compute HMAC-SHA256
            let secretDigest = hmacSHA256(key: Data(seedBytes), message: Data(message + [0x00]))
            let blindingFactorDigest = hmacSHA256(key: Data(seedBytes), message: Data(message + [0x01]))
            
            // Step 3: Derive secret and blinding factor
            let xString = String(bytes: secretDigest)
            let r = try PrivateKey(dataRepresentation: blindingFactorDigest)
            
            // Create output by hashing secret to curve and combining with blinding factor
            let Y = try secureHashToCurve(message: xString)
            let B_ = try Y.combine([r.publicKey])
            
            logger.debug(
                    """
                    Created v1 deterministic output for keysetID: \(keysetID), \
                    index: \(index), output: ...\(B_.stringRepresentation.suffix(10))
                    """
            )
            
            return (B_, r, xString)
        }
        
        private static func hmacSHA256(key: Data, message: Data) -> Data {
            let symmetricKey = SymmetricKey(data: key)
            let mac = HMAC<CryptoKit.SHA256>.authenticationCode(for: message, using: symmetricKey)
            return Data(mac)
        }
        
        //MARK: - BLINDING
        
        static func output(secret: String, blindingFactor: PrivateKey) throws -> PublicKey {
            let Y = try secureHashToCurve(message: secret)
            return try Y.combine([blindingFactor.publicKey])
        }
        
        //MARK: - UNBLINDING
        
        static func unblindPromises(_ promises:[Promise],
                                    blindingFactors:[String],
                                    secrets:[String],
                                    keyset:Keyset) throws -> [Proof] {
            
            guard promises.count == blindingFactors.count,
                  promises.count == secrets.count else {
                throw Crypto.Error.unblinding("""
                    Array length mismatch: 
                    promises: \(promises.count), 
                    blindingFactors: \(blindingFactors.count), 
                    secrets: \(secrets.count)
                    """)
            }
                        
            var proofs = [Proof]()
            for i in 0..<promises.count {
                let promise = promises[i]
                guard let pubkeyData = try? keyset.keys[String(promise.amount)]?.bytes else {
                    throw CashuError.cryptoError("Could not associate mint pubkey from keyset. unblinding not possible")
                }
                
                let mintPubKey = try PublicKey(dataRepresentation: pubkeyData, format: .compressed)
                let r = try PrivateKey(dataRepresentation: blindingFactors[i].bytes)
                let C_ = try PublicKey(dataRepresentation: promise.C_.bytes, format: .compressed)
                let C = try unblind(C_: C_, r: r, A: mintPubKey)
                
                var dleq: DLEQ? = nil
                if let promiseDLEQ = promise.dleq {
                    dleq = DLEQ(e: promiseDLEQ.e, s: promiseDLEQ.s, r: blindingFactors[i])
                }
                
                let proof = Proof(keysetID: promises[i].id,
                                  amount: promises[i].amount,
                                  secret: secrets[i],
                                  C: String(bytes: C.dataRepresentation),
                                  dleq: dleq)
                
                proofs.append(proof)
            }
            return proofs
        }
        
        static func unblind(C_:PublicKey, r: PrivateKey, A: PublicKey) throws -> PublicKey {
            let rA = try A.multiply(r.dataRepresentation.bytes)
            let C = try C_.combine([rA.negation])
            return C
        }
        
        //MARK: - HASH TO CURVE
        
        static func secureHashToCurve(message: String) throws -> PublicKey {
            let domainSeparator = Data("Secp256k1_HashToCurve_Cashu_".utf8)
            let msgData = Data(message.utf8)
            let msgToHash = SHA256.hash(data: domainSeparator + msgData)
            var counter: UInt32 = 0

            while counter < UInt32(pow(2.0, 16)) {
                let counterData = Data(withUnsafeBytes(of: &counter, { Data($0) }))
                let hash = SHA256.hash(data: msgToHash + counterData)
                do {
                    let prefix = Data([0x02])
                    let combined = prefix + hash
                    return try PublicKey(dataRepresentation: combined, format: .compressed)
                } catch {
                    counter += 1
                }
            }
            
            // If no valid point is found, throw an error
            throw Error.hashToCurve("No point on the secp256k1 curve could be found.")
        }
        
        @available(*, deprecated, message: "use function checkDLEQ() with DLEQVerificationResult instead")
        public static func validDLEQ(for proofs: [Proof], with mint: MintRepresenting) throws -> Bool {
            var checks = [Bool]()
            
            for p in proofs {
                guard let keyset = mint.keysets.first(where: { $0.keysetID == p.keysetID }),
                      let AString = keyset.keys[String(p.amount)] else {
                    throw Crypto.Error.DLEQVerificationUnknownKeyset("""
                                                                     Could not associate mint keyset \
                                                                     or public key from keyset \(p.keysetID) \
                                                                     for DLEQ verification.
                                                                     """)
                }
                
                guard let e = try p.dleq?.e.bytes,
                      let s = try p.dleq?.s.bytes,
                      let r = try p.dleq?.r?.bytes else {
                    throw Crypto.Error.DLEQVerificationNoData("""
                                                        At least one necessary parameter for DLEQ \
                                                        verification is not contained in proof.
                                                        proof.dleq: \(p.dleq.debugDescription)
                                                        """)
                }
                
                let A = try PublicKey(dataRepresentation: AString.bytes, format: .compressed)
                let C = try PublicKey(dataRepresentation: p.C.bytes, format: .compressed)
                
                checks.append(try verifyDLEQ(A: A, C: C, x: p.secret, e: Data(e), s: Data(s), r: Data(r)))
            }
            
            return checks.allSatisfy({ $0 == true })
        }
        
        public static func checkDLEQ(for proofs: [Proof], with mint: MintRepresenting) throws -> DLEQVerificationResult {
            var checks = [Bool]()
            
            for p in proofs {
                guard let keyset = mint.keysets.first(where: { $0.keysetID == p.keysetID }),
                      let AString = keyset.keys[String(p.amount)] else {
                    throw Crypto.Error.DLEQVerificationUnknownKeyset("""
                                                                     Could not associate mint keyset \
                                                                     or public key from keyset \(p.keysetID) \
                                                                     for DLEQ verification.
                                                                     """)
                }
                
                guard let e = try p.dleq?.e.bytes,
                      let s = try p.dleq?.s.bytes,
                      let r = try p.dleq?.r?.bytes else {
                    return .noData
                }
                
                let A = try PublicKey(dataRepresentation: AString.bytes, format: .compressed)
                let C = try PublicKey(dataRepresentation: p.C.bytes, format: .compressed)
                
                checks.append(try verifyDLEQ(A: A, C: C, x: p.secret, e: Data(e), s: Data(s), r: Data(r)))
            }
            
            return checks.allTrue ? .valid : .fail
        }
        
        static func verifyDLEQ(A: PublicKey, B_: PublicKey, C_: PublicKey, e: Data, s: Data) throws -> Bool {
            // R1 = s*G - e*A
            // R2 = s*B' - e*C'
            // e == hash(R1,R2,A,C') # must be True
            
            let sTimesG = try PrivateKey(dataRepresentation: s).publicKey
            let eTimesA = try A.multiply([UInt8](e))
            
            let R1 = try sTimesG.subtract(eTimesA, format: .uncompressed)
            
            let sTimesBprime = try B_.multiply([UInt8](s))
            let eTimesCprime = try C_.multiply([UInt8](e))
            
            let R2 = try sTimesBprime.subtract(eTimesCprime, format: .uncompressed)

            let hash = hashConcat([R1, R2, A, C_])
            
            if hash == e {
                return true
            } else {
                return false
            }
        }
        
        static func verifyDLEQ(A: PublicKey, C: PublicKey, x: String, e: Data, s: Data, r: Data) throws -> Bool {
            // Y = hash_to_curve(x)
            // C' = C + r*A
            // B' = Y + r*G
            //
            // R1 = ... (same as Alice)
            let Y = try secureHashToCurve(message: x)
            let rA =  try A.multiply([UInt8](r))
            let C_ = try C.combine([rA])
            let rG = try PrivateKey(dataRepresentation: r).publicKey
            let B_ = try Y.combine([rG])
            
            return try verifyDLEQ(A: A, B_: B_, C_: C_, e: e, s: s)
        }
        
        static func hashConcat(_ publicKeys: [PublicKey]) -> Data {
            
            var concat = ""
            for k in publicKeys {
                let kData = k.uncompressedRepresentation
                concat.append(String(bytes: kData))
            }
            
            return Data(SHA256.hash(data: concat.data(using: .utf8)!))
        }
        
        static func signatures(on secret: String,
                               with keys: [secp256k1.Schnorr.PrivateKey]) throws -> [String] {
            guard let secretData = secret.data(using: .utf8) else {
                throw Crypto.Error.invalidSecret("Could not turn secret string into data for signing.")
            }
            return try keys.map { key in
                let sigBytes = try key.signature(for: secretData).bytes
                return String(bytes: sigBytes)
            }
        }
        
        //MARK: - DETERMINISTIC KEY GENERATION
        
        static func childPrivateKeyForDerivationPath(seed:String, derivationPath:String) throws -> PrivateKey {
            var parts = derivationPath.split(separator: "/")
            
            if parts.count > 7 || parts.count < 1 {
                throw NSError(domain: "cashu crypto error", code: 1)
            }
            
            if parts.first!.contains("m") {
                parts.removeFirst()
            }
            
            let privateMasterKeyDerivator: PrivateMasterKeyDerivating = PrivateMasterKeyDerivator()
            var current = try privateMasterKeyDerivator.privateKey(seed: Data(seed.bytes))

            for var part in parts {
                var index:Int = 0
                if part.contains("'") {
                    part.replace("'", with: "")
                    index = 2147483648
                }
                if let i = Int(part) {
                     index += i
                } else {
                    logger.error("Secret derivation: Unable to calculate child private key from derivation path string.")
                    throw Error.secretDerivation("Unable to calculate child private key from derivation path string.")
                }
                //derive child for current key and set current = new
                let new = try PrivateChildKeyDerivator().privateKey(privateParentKey: current, index: UInt32(index))
                current = new
            }

            return try PrivateKey(dataRepresentation: current.key)
        }
    }
}

//MARK: - HELPER

@available(*, deprecated, message: "pre v1 keyset IDs are no longer supported")
func convertKeysetID(keysetID: String) -> Int? {
    let data = [UInt8](Data(base64Encoded: keysetID)!)
    let big = BInt(bytes: data)
    let result = big % (Int(pow(2.0, 31.0)) - 1)
    return Int(result)
}

func convertHexKeysetID(keysetID: String) -> Int? {
    let data = try! [UInt8](Data(keysetID.bytes))
    let big = BInt(bytes: data)
    let result = big % (Int(pow(2.0, 31.0)) - 1)
    return Int(result)
}

extension secp256k1.Signing.PublicKey {
    var stringRepresentation:String {
        return String(bytes: self.dataRepresentation)
    }
    
    func subtract(_ publicKey: secp256k1.Signing.PublicKey, format: secp256k1.Format = .compressed) throws -> secp256k1.Signing.PublicKey {
        try self.combine([publicKey.negation], format: format)
    }
}

extension secp256k1.Signing.PrivateKey {
    var stringRepresentation:String {
        return String(bytes: self.dataRepresentation)
    }
}
