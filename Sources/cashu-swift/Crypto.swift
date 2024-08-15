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

enum Crypto {
    
    enum Error: Swift.Error {
        case secretDerivation(String?)
        case unblinding(String?)
        case hashToCurve(String?)
    }
    
    typealias PrivateKey = secp256k1.Signing.PrivateKey
    typealias PublicKey = secp256k1.Signing.PublicKey
    
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
                let random = try generateRandomOutput(keysetID: keysetID)
                outputs.append(Output(amount: amounts[i], 
                                      B_: random.output.stringRepresentation,
                                      id: keysetID))
                blindingFactors.append(random.blindingFactor.stringRepresentation)
                secrets.append(random.secret)
            }
        }
        
        return (outputs, blindingFactors, secrets)
    }
    
    private static func generateRandomOutput(keysetID:String) throws -> (output:PublicKey,
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
        
        let keysetInt:Int
        if keysetID.count == 16 {
            keysetInt = convertHexKeysetID(keysetID: keysetID)!
        } else {
            keysetInt = convertKeysetID(keysetID: keysetID)!
        }
        
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
    
    //MARK: - UNBLINDING
    
    static func unblindPromises(_ promises:[Promise],
                         blindingFactors:[String],
                         secrets:[String],
                         keyset:Keyset) throws -> [Proof] {
        
        var proofs = [Proof]()
        for i in 0..<promises.count {
            let promise = promises[i]
            guard let pubkeyData = try? keyset.keys[String(promise.amount)]?.bytes else {
                fatalError("Could not associate mint pubkey from keyset. unblinding not possible")
            }
            
            let mintPubKey = try PublicKey(dataRepresentation: pubkeyData, format: .compressed)
            let r = try PrivateKey(dataRepresentation: blindingFactors[i].bytes)
            let C_ = try PublicKey(dataRepresentation: promise.C_.bytes, format: .compressed)
            let C = try unblind(C_: C_, r: r, A: mintPubKey)
            
            proofs.append(Proof(id: promises[i].id, 
                                amount: promises[i].amount,
                                secret: secrets[i],
                                C: String(bytes: C.dataRepresentation)))
        }
        return proofs
    }
    
    static func unblind(C_:PublicKey, r: PrivateKey, A: PublicKey) throws -> PublicKey {
        let rA = try A.multiply(r.dataRepresentation.bytes)
        let C = try C_.combine([negatePublicKey(key: rA)])
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
    
    //MARK: - HELPER
    
    static func negatePublicKey(key: PublicKey) -> PublicKey {
        let serialized = key.dataRepresentation
        var firstByte = serialized.first!
        let remainder = serialized.dropFirst()
        switch firstByte {
        case 0x03:
            firstByte = 0x02
        case 0x02:
            firstByte = 0x03
        default:
            break
        }
        let newKeyData = Data([firstByte]) + remainder
        let newKey = try! PublicKey(dataRepresentation: newKeyData, format: .compressed)
        return newKey
    }
    
    //MARK: - DETERMINISTIC KEY GENERATION
    
    fileprivate static func childPrivateKeyForDerivationPath(seed:String, derivationPath:String) throws -> PrivateKey {
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

//MARK: - HELPER

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
}

extension secp256k1.Signing.PrivateKey {
    var stringRepresentation:String {
        return String(bytes: self.dataRepresentation)
    }
}
