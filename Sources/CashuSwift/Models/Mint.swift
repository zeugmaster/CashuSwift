import Foundation
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    /// Represents a Cashu mint with its URL and keysets.
    public struct Mint: Hashable, Codable, MintRepresenting, Sendable {
        
        /// Creates a new mint instance.
        /// - Parameters:
        ///   - url: The URL of the mint
        ///   - keysets: The keysets associated with this mint
        public init(url: URL, keysets: [CashuSwift.Keyset]) {
            self.url = url
            self.keysets = keysets
        }
        
        /// Creates a mint instance from a MintRepresenting protocol conformer.
        /// - Parameter mintRepresentation: The mint representation to copy from
        public init(_ mintRepresentation: MintRepresenting) {
            self.url = mintRepresentation.url
            self.keysets = mintRepresentation.keysets
        }
        
        /// The URL of the mint.
        public var url: URL
        
        /// The keysets available on this mint.
        public var keysets: [Keyset]
        public static func == (lhs: Mint, rhs: Mint) -> Bool {
            lhs.url == rhs.url
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }
        
        /// Checks if the mint is reachable by pinging its info endpoint.
        /// - Returns: `true` if the mint is online and reachable, `false` otherwise
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
    }
}
