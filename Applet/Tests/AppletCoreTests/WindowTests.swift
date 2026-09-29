import XCTest
@testable import AppletCore

final class WindowTests: XCTestCase {
    func decode(_ text: String) throws -> NoodletWindowOptions { try JSONDecoder().decode(NoodletWindowOptions.self, from: Data(text.utf8)) }
    func testWindowCompatibilityAndInvalidBounds() throws {
        let defaults = try decode("{}")
        XCTAssertEqual(defaults.type, .standard)
        XCTAssertTrue(defaults.resizable)
        XCTAssertFalse(defaults.rememberFrame)
        XCTAssertEqual(defaults.size(), CGSize(width:900,height:620))
        for text in [#"{"type":"unknown"}"#, #"{"background":"unknown"}"#, #"{"width":119}"#, #"{"minWidth":500,"maxWidth":400}"#, #"{"height":700,"maxHeight":500}"#] {
            XCTAssertThrowsError(try decode(text).validate())
        }
        let options = try decode(#"{"type":"floating","background":"translucent","resizable":false,"rememberFrame":true,"width":320,"height":350,"minWidth":260,"maxWidth":480}"#)
        try options.validate()
        XCTAssertEqual(options.size(width:200).width, 260)
        XCTAssertEqual(options.size(width:900).width, 480)
        XCTAssertEqual(try JSONDecoder().decode(NoodletWindowOptions.self, from: JSONEncoder().encode(options)).background, .translucent)
    }
    func testTitlebarCanDropTheNativeButtons() throws {
        XCTAssertEqual(try decode("{}").titlebar, .visible)
        XCTAssertEqual(try decode(#"{"titlebar":true}"#).titlebar, .visible)
        XCTAssertEqual(try decode(#"{"titlebar":false}"#).titlebar, .hidden)
        XCTAssertEqual(try decode(#"{"titlebar":"none"}"#).titlebar, .none)
        XCTAssertThrowsError(try decode(#"{"titlebar":"unknown"}"#))
        // The Swift runtime reads the options back as JSON, so each value keeps its manifest form.
        for text in [#"{"titlebar":true}"#, #"{"titlebar":false}"#, #"{"titlebar":"none"}"#] {
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decode(text))) as! [String: Any]
            let original = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            XCTAssertEqual(json["titlebar"] as? NSObject, original["titlebar"] as? NSObject, text)
        }
    }
}
