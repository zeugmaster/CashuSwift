//
//  KeysetVersion.swift
//
//  Single source of truth for classifying a keyset by its ID, replacing the
//  scattered `hasPrefix("00"/"01")` / `count == 12` checks throughout the library.
//

import Foundation

extension CashuSwift {
    /// The cryptographic scheme a keyset uses, inferred from the shape of its ID.
    ///
    /// - `legacyBase64`: 12-character base64 ID (pre-NUT-02 hex IDs), secp256k1.
    /// - `v0`: `00…` hex ID (NUT-02 v1 derivation), secp256k1.
    /// - `v1`: `01…` hex ID (NUT-02 v2 derivation), secp256k1.
    /// - `v3`: `02…` hex ID (NUT PR #371), BLS12-381 pairing crypto.
    public enum KeysetVersion: Sendable, Equatable {
        case legacyBase64
        case v0
        case v1
        case v3

        /// Classifies a keyset ID. Returns `nil` for an unrecognized format.
        ///
        /// Length is checked before prefix: legacy base64 IDs are exactly 12 chars, while
        /// hex IDs are 16 (shortened) or 66 (full) chars, so the schemes never collide.
        public init?(keysetID: String) {
            if keysetID.count == 12 {
                self = .legacyBase64
            } else if keysetID.hasPrefix("00") {
                self = .v0
            } else if keysetID.hasPrefix("01") {
                self = .v1
            } else if keysetID.hasPrefix("02") {
                self = .v3
            } else {
                return nil
            }
        }

        /// Whether this keyset uses BLS12-381 pairing crypto (v3) instead of secp256k1.
        public var isBLS: Bool { self == .v3 }

        /// Whether the ID can appear in a shortened 16-char form that must be resolved to a
        /// full ID by prefix matching. Only the modern hex schemes (v1, v3) use short IDs.
        var supportsShortID: Bool { self == .v1 || self == .v3 }
    }
}
