//
//  JSONValue.swift
//  CashuSwift
//

import Foundation

extension CashuSwift {
    /// A typed JSON value used by `Generic` payment-method types to carry method-specific
    /// fields that the library does not model directly. Wallet UIs can surface these
    /// fields to the user without the library having first-class support for the method.
    public enum JSONValue: Hashable, Sendable, Codable {
        case string(String)
        case integer(Int64)
        case double(Double)
        case bool(Bool)
        case null
        case array([JSONValue])
        case object([String: JSONValue])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Unsupported JSON value")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .integer(let v): try container.encode(v)
            case .double(let v): try container.encode(v)
            case .bool(let v): try container.encode(v)
            case .null: try container.encodeNil()
            case .array(let v): try container.encode(v)
            case .object(let v): try container.encode(v)
            }
        }
    }

    /// Convenience typealias for a JSON object payload.
    public typealias JSONObject = [String: JSONValue]
}
