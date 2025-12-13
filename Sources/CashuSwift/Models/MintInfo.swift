//
//  File.swift
//  CashuSwift
//
//  Created by zm on 11.11.24.
//

import Foundation

extension CashuSwift.Mint {
    public struct Info: Codable, Sendable {
        public let name: String?
        public let pubkey: String?
        public let version: String?
        public let description: String?
        public let descriptionLong: String?
        public let contact: [Contact]?
        public let motd: String?
        public let iconUrl: String?
        public let urls: [String]?
        public let time: Int?
        public let tosUrl: String?
        public let nuts: Nuts?
        
        public struct Contact: Codable, Sendable {
            public let method: String
            public let info: String
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
        
        public struct Nuts: Codable, Sendable {
            public let nut04: NutInfo?
            public let nut05: NutInfo?
            public let nut07: NutInfo?
            public let nut08: NutInfo?
            public let nut09: NutInfo?
            public let nut10: NutInfo?
            public let nut11: NutInfo?
            public let nut12: NutInfo?
            public let nut14: NutInfo?
            public let nut15: NutInfo?
            public let nut17: NutInfo?
            public let nut20: NutInfo?
            
            enum CodingKeys: String, CodingKey {
                case nut04 = "4"
                case nut05 = "5"
                case nut07 = "7"
                case nut08 = "8"
                case nut09 = "9"
                case nut10 = "10"
                case nut11 = "11"
                case nut12 = "12"
                case nut14 = "14"
                case nut15 = "15"
                case nut17 = "17"
                case nut20 = "20"
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode each nut individually, setting to nil if one fails
                nut04 = try container.decodeIfPresent(NutInfo.self, forKey: .nut04)
                nut05 = try container.decodeIfPresent(NutInfo.self, forKey: .nut05)
                nut07 = try container.decodeIfPresent(NutInfo.self, forKey: .nut07)
                nut08 = try container.decodeIfPresent(NutInfo.self, forKey: .nut08)
                nut09 = try container.decodeIfPresent(NutInfo.self, forKey: .nut09)
                nut10 = try container.decodeIfPresent(NutInfo.self, forKey: .nut10)
                nut11 = try container.decodeIfPresent(NutInfo.self, forKey: .nut11)
                nut12 = try container.decodeIfPresent(NutInfo.self, forKey: .nut12)
                nut14 = try container.decodeIfPresent(NutInfo.self, forKey: .nut14)
                nut15 = try container.decodeIfPresent(NutInfo.self, forKey: .nut15)
                nut17 = try container.decodeIfPresent(NutInfo.self, forKey: .nut17)
                nut20 = try container.decodeIfPresent(NutInfo.self, forKey: .nut20)
            }
        }
        
        public struct NutInfo: Codable, Sendable {
            public let methods: [PaymentMethod]?
            public let disabled: Bool?
            public let supported: SupportedValue?
            
            enum CodingKeys: String, CodingKey {
                case methods, disabled, supported
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                // Try to decode methods, but allow failure
                methods = try container.decodeIfPresent([PaymentMethod].self, forKey: .methods)
                
                // Try to decode disabled flag, but allow failure
                disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
                
                // Handle supported field which can be either a bool or an array of methods
                if let boolSupported = try? container.decode(Bool.self, forKey: .supported) {
                    supported = .bool(boolSupported)
                } else if let methodsSupported = try? container.decode([PaymentMethod].self, forKey: .supported) {
                    supported = .methods(methodsSupported)
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
                    try container.encode(value, forKey: .supported)
                case .none:
                    break
                }
            }
        }
        
        public enum SupportedValue: Codable, Sendable {
            case bool(Bool)
            case methods([PaymentMethod])
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                
                if let boolValue = try? container.decode(Bool.self) {
                    self = .bool(boolValue)
                } else if let methodsValue = try? container.decode([PaymentMethod].self) {
                    self = .methods(methodsValue)
                } else {
                    throw DecodingError.typeMismatch(SupportedValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Bool or [PaymentMethod]"))
                }
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .bool(let value):
                    try container.encode(value)
                case .methods(let value):
                    try container.encode(value)
                }
            }
        }
        
        public struct PaymentMethod: Codable, Sendable {
            public let method: String
            public let unit: String
            public let minAmount: Int?
            public let maxAmount: Int?
            public let description: Bool?
            public let commands: [String]?
            
            enum CodingKeys: String, CodingKey {
                case method, unit, description, commands
                case minAmount = "min_amount"
                case maxAmount = "max_amount"
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                method = try container.decode(String.self, forKey: .method)
                unit = try container.decode(String.self, forKey: .unit)
                minAmount = try container.decodeIfPresent(Int.self, forKey: .minAmount)
                maxAmount = try container.decodeIfPresent(Int.self, forKey: .maxAmount)
                description = try container.decodeIfPresent(Bool.self, forKey: .description)
                commands = try container.decodeIfPresent([String].self, forKey: .commands)
            }
        }
    }
}
