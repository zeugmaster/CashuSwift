import Foundation
import XCTest

/// Per-host HTTP fixtures keep parallel tests isolated and never contact a real mint.
final class MintHTTPStub: @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var stubs: [String: MintHTTPStub] = [:]
        let registered = URLProtocol.registerClass(MintURLProtocol.self)
    }
    private static let registry = Registry()
    let url: URL
    private let host: String
    private let lock = NSLock()
    private var captured: [URLRequest] = []
    struct Response { let data: Data; var status: Int = 200 }
    private let handler: (URLRequest) throws -> Response

    convenience init(handler: @escaping (URLRequest) throws -> Data) throws {
        try self.init(responseHandler: { Response(data: try handler($0)) })
    }

    init(responseHandler: @escaping (URLRequest) throws -> Response) throws {
        host = UUID().uuidString.lowercased() + ".mint-tests.invalid"
        url = try XCTUnwrap(URL(string: "https://" + host))
        self.handler = responseHandler
        Self.registry.lock.lock()
        defer { Self.registry.lock.unlock() }
        Self.registry.stubs[host] = self
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func remove() {
        Self.registry.lock.lock()
        defer { Self.registry.lock.unlock() }
        Self.registry.stubs.removeValue(forKey: host)
    }

    static func response(to request: URLRequest) throws -> Response {
        registry.lock.lock()
        let stub = registry.stubs[request.url?.host ?? ""]
        registry.lock.unlock()
        let fixture = try XCTUnwrap(stub)
        fixture.lock.lock()
        fixture.captured.append(request)
        fixture.lock.unlock()
        return try fixture.handler(request)
    }
}

private final class MintURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".mint-tests.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while true {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count == 0 { break }
                    guard count > 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    data.append(contentsOf: bytes.prefix(count))
                }
                captured.httpBody = data
            }
            let fixture = try MintHTTPStub.response(to: captured)
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: nil,
                                                       headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: fixture.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
