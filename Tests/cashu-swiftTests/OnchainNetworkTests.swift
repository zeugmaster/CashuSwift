import XCTest
@testable import CashuSwift

final class OnchainNetworkTests: XCTestCase {
    typealias F = OnchainFixture
    typealias O = CashuSwift.Onchain

    func testHTTPStatusIsCheckedEvenForDecodableSuccessBody() async throws {
        let stub = try MintHTTPStub(responseHandler: { _ in
            .init(data: try JSONEncoder().encode(F.mintQuote()), status: 500)
        })
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        await assertOnchainError(O.Error.http(status: 500, mintCode: nil)) {
            _ = try await O.mintQuoteState("mint-1", from: mint)
        }
    }

    func testStructuredErrorCodeDoesNotMatchDetailSubstrings() async throws {
        let stub = try MintHTTPStub(responseHandler: { _ in
            .init(data: Data(#"{"code":20005,"detail":"text containing 11001 and secrets"}"#.utf8), status: 400)
        })
        defer { stub.remove() }
        let mint = try F.mint(url: stub.url)
        await assertOnchainError(O.Error.http(status: 400, mintCode: 20005)) {
            _ = try await O.mintQuoteState("mint-1", from: mint)
        }
        XCTAssertFalse(O.Error.http(status: 400, mintCode: 20005).localizedDescription.contains("secrets"))
    }

    func testTransportCancellationAndMalformedJSONStayDistinct() async throws {
        for code in [URLError.cancelled, .timedOut, .cannotConnectToHost] {
            let stub = try MintHTTPStub(handler: { _ in throw URLError(code) })
            defer { stub.remove() }
            let mint = try F.mint(url: stub.url)
            do { _ = try await O.mintQuoteState("mint-1", from: mint); XCTFail() }
            catch { XCTAssertEqual((error as? URLError)?.code, code) }
        }
        let stub = try MintHTTPStub { _ in Data("not JSON".utf8) }
        defer { stub.remove() }
        do { _ = try await O.mintQuoteState("mint-1", from: F.mint(url: stub.url)); XCTFail() }
        catch { XCTAssertTrue(error is DecodingError) }
    }
}
