import Foundation
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    public struct Mint: Hashable, Codable, MintRepresenting, Sendable {
        
        public init(url: URL, keysets: [CashuSwift.Keyset]) {
            self.url = url
            self.keysets = keysets
        }
        
        public init(_ mintRepresentation: MintRepresenting) {
            self.url = mintRepresentation.url
            self.keysets = mintRepresentation.keysets
        }
        
        public var url: URL
        public var keysets: [Keyset]
        public static func == (lhs: Mint, rhs: Mint) -> Bool {
            lhs.url == rhs.url
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
    }
}
