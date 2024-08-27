import Foundation
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

/// This is the mint object.
open class Mint: Hashable, Codable {
    
    public let url: URL
    var keysets: [Keyset]
    public var info: MintInfo?
    public var nickname: String?
    
    public static func == (lhs: Mint, rhs: Mint) -> Bool {
        lhs.url == rhs.url
    }
    
    public init(with url: URL) async throws {
        self.url = url
        
        // load keysets or fail with error propagating up
        let keysetList = try await Network.get(url: url.appending(path: "/v1/keysets"),
                                               expected: KeysetList.self)
        var keysetsWithKeys = [Keyset]()
        for keyset in keysetList.keysets {
            let new = keyset
            new.keys = try await Network.get(url: url.appending(path: "/v1/keys/\(keyset.keysetID.makeURLSafe())"),
                                             expected: KeysetList.self).keysets[0].keys
            keysetsWithKeys.append(new)
        }
        
        self.keysets = keysetsWithKeys
        
        self.info = try? await loadInfo()
    }
    
    func loadInfo() async throws -> MintInfo? {
        let mintInfoData = try await Network.get(url: self.url.appending(path: "v1/info"))!
        
        if let info = try? JSONDecoder().decode(MintInfo0_16.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo0_15.self, from: mintInfoData) {
            return info
        } else if let info = try? JSONDecoder().decode(MintInfo.self, from: mintInfoData) {
            return info
        } else {
            logger.warning("Could not parse mint info of \(self.url.absoluteString) to any known version.")
            return nil
        }
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(URL.self, forKey: .url)
        self.keysets = try container.decode([Keyset].self, forKey: .keysets)
        
        let infoContainer = try container.superDecoder(forKey: .info)
        if let info = try? MintInfo0_16(from: infoContainer) {
            self.info = info
        } else if let info = try? MintInfo0_15(from: infoContainer) {
            self.info = info
        } else if let info = try? MintInfo(from: infoContainer) {
            self.info = info
        } else {
            logger.warning("Could not initiate from decoder mint info of \(self.url.absoluteString) as any known version.")
        }
        
        self.nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
    }
    
    enum CodingKeys: CodingKey {
        case url
        case keysets
        case info
        case nickname
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.url, forKey: .url)
        try container.encode(self.keysets, forKey: .keysets)
        
        if let info = self.info {
            let infoContainer = container.superEncoder(forKey: .info)
            try info.encode(to: infoContainer)
        }
        
        try container.encodeIfPresent(self.nickname, forKey: .nickname)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    /// Pings the mint for its info to check whether it is online or not
    public func isReachable() async -> Bool {
        do {
            // if the network doesn't throw an error we can assume the mint is online
            let url = self.url.appending(path: "/v1/info")
            let _ = try await Network.get(url: url)
            return true
        } catch {
            return false
        }
    }
    
    public func calculateFee(for proofs: [Proof]) throws -> Int {
        var sumFees = 0
        for proof in proofs {
            if let feeRate = self.keysets.first(where: { $0.keysetID == proof.keysetID })?.inputFeePPK {
                sumFees += feeRate
            } else {
                throw CashuError.feeCalculationError("trying to calculate fees for proofs of keyset \(proof.keysetID) which does not seem to be associated with mint \(self.url.absoluteString).")
            }
        }
        return (sumFees + 999) / 1000
    }
}

public class MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let descriptionShort: String?
    let descriptionLong: String?
    
    enum CodingKeys: String, CodingKey {
        case name, pubkey, version
        case descriptionLong = "description_long"
        case descriptionShort = "description"
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.pubkey = try container.decode(String.self, forKey: .pubkey)
        self.version = try container.decode(String.self, forKey: .version)
        self.descriptionShort = try container.decodeIfPresent(String.self, forKey: .descriptionShort)
        self.descriptionLong = try container.decodeIfPresent(String.self, forKey: .descriptionLong)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(descriptionShort, forKey: .descriptionShort)
        try container.encodeIfPresent(descriptionLong, forKey: .descriptionLong)
    }
}

public class MintInfo0_15: MintInfo {
    let contact: [[String]]
    let motd: String?
    let nuts: [String: Nut]
    
    enum CodingKeys: String, CodingKey {
        case contact, motd, nuts
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contact = try container.decode([[String]].self, forKey: .contact)
        self.motd = try container.decodeIfPresent(String.self, forKey: .motd)
        self.nuts = try container.decode([String: Nut].self, forKey: .nuts)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contact, forKey: .contact)
        try container.encodeIfPresent(motd, forKey: .motd)
        try container.encode(nuts, forKey: .nuts)
    }
    
    struct Nut: Codable {
        let methods: [PaymentMethod]?
        let disabled: Bool?
        let supported: Bool?

        enum CodingKeys: String, CodingKey {
            case methods, disabled, supported
        }
    }
    
    struct PaymentMethod: Codable {
        let method: String
        let unit: String
        let minAmount: Int?
        let maxAmount: Int?

        enum CodingKeys: String, CodingKey {
            case method, unit
            case minAmount = "min_amount"
            case maxAmount = "max_amount"
        }
    }
}

public class MintInfo0_16: MintInfo {
    let contact: [Contact]
    let motd: String
    let nuts: [String: NutInfo]
    
    enum CodingKeys: String, CodingKey {
        case contact, motd, nuts
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contact = try container.decode([Contact].self, forKey: .contact)
        self.motd = try container.decode(String.self, forKey: .motd)
        self.nuts = try container.decode([String: NutInfo].self, forKey: .nuts)
        
        try super.init(from: decoder)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contact, forKey: .contact)
        try container.encode(motd, forKey: .motd)
        try container.encode(nuts, forKey: .nuts)
    }
}

struct Contact: Codable {
    let method: String
    let info: String
}

struct NutInfo: Codable {
    let methods: [Method]?
    let disabled: Bool?
    let supported: SupportedType?
    
    enum CodingKeys: String, CodingKey {
        case methods, disabled, supported
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        methods = try container.decodeIfPresent([Method].self, forKey: .methods)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        
        if let boolSupported = try? container.decode(Bool.self, forKey: .supported) {
            supported = .bool(boolSupported)
        } else if let arraySupported = try? container.decode([Method].self, forKey: .supported) {
            supported = .methods(arraySupported)
        } else {
            supported = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(methods, forKey: .methods)
        try container.encodeIfPresent(disabled, forKey: .disabled)
        
        switch supported {
        case .bool(let value):
            try container.encode(value, forKey: .supported)
        case .methods(let value):
            try container.encode(value, forKey: .methods)
        case .none:
            break
        }
    }
}

enum SupportedType {
    case bool(Bool)
    case methods([Method])
}

struct Method: Codable {
    let method: String
    let unit: String
    let minAmount: Int?
    let maxAmount: Int?
    let commands: [String]?
    
    enum CodingKeys: String, CodingKey {
        case method, unit, commands
        case minAmount = "min_amount"
        case maxAmount = "max_amount"
    }
}
