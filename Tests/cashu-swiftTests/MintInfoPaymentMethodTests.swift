import CashuSwift
import Foundation
import XCTest

final class MintInfoPaymentMethodTests: XCTestCase {
    func testNutrootLeafAdvertisementsSurviveCachingAndDefaultToCore() throws {
        for json in [#"{}"#, #"{"nuts":{"10":{"supported":true}}}"#, #"{"nuts":{"10":{"leaves":[]}}}"#] {
            let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: Data(json.utf8))
            XCTAssertEqual(info.nutrootLeafTypes, ["0001", "0002", "0003", "0004"])
        }
        let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self,
            from: Data(#"{"nuts":{"10":{"supported":true,"leaves":["0001","00AB","bad",42]}}}"#.utf8))
        let cached = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: JSONEncoder().encode(info))
        XCTAssertEqual(info.nutrootLeafTypes, ["0001", "00ab"])
        XCTAssertEqual(cached.nutrootLeafTypes, info.nutrootLeafTypes)
        let malformed = try JSONDecoder().decode(CashuSwift.Mint.Info.self,
            from: Data(#"{"nuts":{"10":{"leaves":[42]}}}"#.utf8))
        XCTAssertEqual(malformed.nutrootLeafTypes, [], "a nonempty invalid list must not imply core support")
    }

    func testMethodNamesSurviveMintInfoCacheRoundTrip() throws {
        let data = Data(#"""
        {"nuts": {
            "4": {"methods": [{"method": "apple-pay", "unit": "usd", "method_name": "Apple Pay"}]},
            "5": {"methods": [{"method": "branch", "unit": "sat", "method_name": "Branch"}]}
        }}
        """#.utf8)
        let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: data)
        let cachedData = try JSONEncoder().encode(info)
        let cached = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: cachedData)
        for value in [info, cached] {
            let mint = try XCTUnwrap(value.paymentMethodSetting(direction: .mint, method: "apple-pay", unit: "usd"))
            let melt = try XCTUnwrap(value.paymentMethodSetting(direction: .melt, method: "branch", unit: "sat"))
            XCTAssertEqual(mint.methodName, "Apple Pay")
            XCTAssertEqual(mint.method.rawValue, "apple-pay")
            XCTAssertEqual(melt.methodName, "Branch")
            XCTAssertEqual(melt.method.rawValue, "branch")
        }
    }

    func testMethodNameIsOptional() throws {
        for json in [
            #"{"method":"bolt11","unit":"sat"}"#,
            #"{"method":"branch","unit":"sat","method_name":null}"#
        ] {
            let setting = try JSONDecoder().decode(CashuSwift.Mint.Info.PaymentMethod.self, from: Data(json.utf8))
            XCTAssertNil(setting.methodName)
        }
        XCTAssertNil(CashuSwift.Mint.Info.PaymentMethod(method: .bolt11, unit: "sat").methodName)
    }

    func testInitializerEncodesProtocolFieldName() throws {
        let setting = CashuSwift.Mint.Info.PaymentMethod(method: "branch", unit: "sat", methodName: "Branch")
        let data = try JSONEncoder().encode(setting)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["method_name"] as? String, "Branch")
        XCTAssertEqual(json["method"] as? String, "branch")
        XCTAssertNil(json["methodName"])
    }

    func testNonStringMethodNameIsRejected() {
        let data = Data(#"{"method":"branch","unit":"sat","method_name":42}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CashuSwift.Mint.Info.PaymentMethod.self, from: data)) { error in
            guard case DecodingError.typeMismatch(_, let context) = error else {
                return XCTFail("Expected a type mismatch, received \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "method_name")
        }
    }
}
