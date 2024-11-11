import Foundation
import OSLog

fileprivate let logger = Logger.init(subsystem: "CashuSwift", category: "wallet")

extension CashuSwift {
    open class Mint: Hashable, Codable, MintRepresenting {
        
        public required init(url: URL, keysets: [CashuSwift.Keyset]) {
            self.url = url
            self.keysets = keysets
        }
        
        public var url: URL
        public var keysets: [Keyset]
//        public var info: MintInfo?
//        public var nickname: String?
        
        public static func == (lhs: Mint, rhs: Mint) -> Bool {
            lhs.url == rhs.url
        }
        
//        required public init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            self.url = try container.decode(URL.self, forKey: .url)
//            self.keysets = try container.decode([Keyset].self, forKey: .keysets)
//            
//            let infoContainer = try container.superDecoder(forKey: .info)
//            if let info = try? MintInfo0_16(from: infoContainer) {
//                self.info = info
//            } else if let info = try? MintInfo0_15(from: infoContainer) {
//                self.info = info
//            } else if let info = try? MintInfo(from: infoContainer) {
//                self.info = info
//            } else {
//                logger.warning("Could not initiate from decoder mint info of \(self.url.absoluteString) as any known version.")
//            }
//            
//            self.nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
//        }
//        
//        enum CodingKeys: CodingKey {
//            case url
//            case keysets
//            case info
//            case nickname
//        }
//        
//        public func encode(to encoder: Encoder) throws {
//            var container = encoder.container(keyedBy: CodingKeys.self)
//            try container.encode(self.url, forKey: .url)
//            try container.encode(self.keysets, forKey: .keysets)
//            
//            if let info = self.info {
//                let infoContainer = container.superEncoder(forKey: .info)
//                try info.encode(to: infoContainer)
//            }
//            
//            try container.encodeIfPresent(self.nickname, forKey: .nickname)
//        }
        
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
