//
//  File.swift
//  CashuSwift
//
//  Created by zm on 11.11.24.
//

import Foundation

extension CashuSwift {
    
    @available(*, deprecated, renamed: "Mint.Info")
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

extension CashuSwift.Mint {
    public struct Info: Codable {
        let name: String?
        let pubkey: String?
        let version: String?
        let description: String?
        let descriptionLong: String?
        let contact: [Contact]?
        let motd: String?
        let iconUrl: String?
        let urls: [String]?
        let time: Int?
        let tosUrl: String?
        let nuts: Nuts?
        
        public struct Contact: Codable {
            let method: String
            let info: String
        }
        
        enum CodingKeys: String, CodingKey {
            case name, pubkey, version, description, contact, motd, urls, time, nuts
            case descriptionLong = "description_long"
            case iconUrl = "icon_url"
            case tosUrl = "tos_url"
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Decode all the standard fields
            name = try container.decodeIfPresent(String.self, forKey: .name)
            pubkey = try container.decodeIfPresent(String.self, forKey: .pubkey)
            version = try container.decodeIfPresent(String.self, forKey: .version)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            descriptionLong = try container.decodeIfPresent(String.self, forKey: .descriptionLong)
            contact = try container.decodeIfPresent([Contact].self, forKey: .contact)
            motd = try container.decodeIfPresent(String.self, forKey: .motd)
            iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
            urls = try container.decodeIfPresent([String].self, forKey: .urls)
            time = try container.decodeIfPresent(Int.self, forKey: .time)
            tosUrl = try container.decodeIfPresent(String.self, forKey: .tosUrl)
            
            // Try to decode nuts field, but if it fails, set to nil
            do {
                nuts = try container.decodeIfPresent(Nuts.self, forKey: .nuts)
            } catch {
                print("Failed to decode nuts field: \(error)")
                nuts = nil
            }
        }
        
        public struct Nuts: Codable {
            let nut04: PaymentMethodList?
            let nut05: PaymentMethodList?
            let nut07: NutSupportFlag?
            let nut08: NutSupportFlag?
            let nut09: NutSupportFlag?
            let nut10: NutSupportFlag?
            let nut12: NutSupportFlag?
            
            enum CodingKeys: String, CodingKey {
                case nut04 = "4"
                case nut05 = "5"
                case nut07 = "7"
                case nut08 = "8"
                case nut09 = "9"
                case nut10 = "10"
                case nut12 = "12"
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode each nut individually, setting to nil if one fails
                do {
                    nut04 = try container.decodeIfPresent(PaymentMethodList.self, forKey: .nut04)
                } catch {
                    print("Failed to decode nut04: \(error)")
                    nut04 = nil
                }
                
                do {
                    nut05 = try container.decodeIfPresent(PaymentMethodList.self, forKey: .nut05)
                } catch {
                    print("Failed to decode nut05: \(error)")
                    nut05 = nil
                }
                
                do {
                    nut07 = try container.decodeIfPresent(NutSupportFlag.self, forKey: .nut07)
                } catch {
                    print("Failed to decode nut07: \(error)")
                    nut07 = nil
                }
                
                do {
                    nut08 = try container.decodeIfPresent(NutSupportFlag.self, forKey: .nut08)
                } catch {
                    print("Failed to decode nut08: \(error)")
                    nut08 = nil
                }
                
                do {
                    nut09 = try container.decodeIfPresent(NutSupportFlag.self, forKey: .nut09)
                } catch {
                    print("Failed to decode nut09: \(error)")
                    nut09 = nil
                }
                
                do {
                    nut10 = try container.decodeIfPresent(NutSupportFlag.self, forKey: .nut10)
                } catch {
                    print("Failed to decode nut10: \(error)")
                    nut10 = nil
                }
                
                do {
                    nut12 = try container.decodeIfPresent(NutSupportFlag.self, forKey: .nut12)
                } catch {
                    print("Failed to decode nut12: \(error)")
                    nut12 = nil
                }
            }
        }
        
        public struct PaymentMethodList: Codable {
            let methods: [PaymentMethod]?
            let disabled: Bool?
            
            enum CodingKeys: String, CodingKey {
                case methods, disabled
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode methods, but allow failure
                do {
                    methods = try container.decodeIfPresent([PaymentMethod].self, forKey: .methods)
                } catch {
                    print("Failed to decode PaymentMethodList.methods: \(error)")
                    methods = nil
                }
                
                // Try to decode supported flag, but allow failure
                do {
                    disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
                } catch {
                    print("Failed to decode PaymentMethodList.supported: \(error)")
                    disabled = nil
                }
            }
        }
        
        public struct PaymentMethod: Codable {
            let method: String
            let unit: String
            let minAmount: Int
            let maxAmount: Int
            
            enum CodingKeys: String, CodingKey {
                case method, unit
                case minAmount = "min_amount"
                case maxAmount = "max_amount"
            }
        }
        
        public struct NutSupportFlag: Codable {
            let supported: Bool
        }
    }
}
