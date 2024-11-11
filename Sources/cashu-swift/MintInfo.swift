//
//  File.swift
//  CashuSwift
//
//  Created by zm on 11.11.24.
//

import Foundation

extension CashuSwift {
    public class MintInfo: Codable {
        public let name: String
        public let pubkey: String
        public let version: String
        public let descriptionShort: String?
        public let descriptionLong: String?
        
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
        public let contact: [[String]]
        public let motd: String?
        public let nuts: [String: Nut]
        
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
        
        public struct Nut: Codable {
            public let methods: [PaymentMethod]?
            public let disabled: Bool?
            public let supported: Bool?

            enum CodingKeys: String, CodingKey {
                case methods, disabled, supported
            }
        }
        
        public struct PaymentMethod: Codable {
            public let method: String
            public let unit: String
            public let minAmount: Int?
            public let maxAmount: Int?

            enum CodingKeys: String, CodingKey {
                case method, unit
                case minAmount = "min_amount"
                case maxAmount = "max_amount"
            }
        }
    }

    public class MintInfo0_16: MintInfo {
        public let contact: [Contact]
        public let motd: String
        public let nuts: [String: NutInfo]
        
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

    public struct Contact: Codable {
        public let method: String
        public let info: String
    }

    public struct NutInfo: Codable {
        public let methods: [Method]?
        public let disabled: Bool?
        public let supported: SupportedType?
        
        enum CodingKeys: String, CodingKey {
            case methods, disabled, supported
        }
        
        public init(from decoder: Decoder) throws {
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
        
        public func encode(to encoder: Encoder) throws {
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

    public enum SupportedType: Equatable {
        case bool(Bool)
        case methods([Method])

        public static func == (lhs: SupportedType, rhs: SupportedType) -> Bool {
            switch (lhs, rhs) {
            case let (.bool(lhsValue), .bool(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }



    public struct Method: Codable {
        public let method: String
        public let unit: String
        public let minAmount: Int?
        public let maxAmount: Int?
        public let commands: [String]?
        
        enum CodingKeys: String, CodingKey {
            case method, unit, commands
            case minAmount = "min_amount"
            case maxAmount = "max_amount"
        }
    }
}
