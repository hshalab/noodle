import XCTest
@testable import Noodle

final class AppIdentityTests: XCTestCase {
    /// Development-only menus must never reach the production bundle.
    func testOnlyTheLocalBundleAndUnbundledRunsAreDevelopment() {
        XCTAssertTrue(NoodleAppIdentity.isDevelopment(bundleIdentifier: "com.pdparchitect.noodle.local"))
        XCTAssertTrue(NoodleAppIdentity.isDevelopment(bundleIdentifier: nil))
        XCTAssertFalse(NoodleAppIdentity.isDevelopment(bundleIdentifier: "com.pdparchitect.noodle"))
        XCTAssertFalse(NoodleAppIdentity.isDevelopment(bundleIdentifier: "com.pdparchitect.noodle.localhost"))
    }

    /// The bots that are given a calendar or a reminder list reach EventKit from the sandboxed
    /// app, which needs one entitlement per kind: without them the access request is denied
    /// without ever asking the person.
    func testSandboxPolicyGrantsBothCalendarsAndReminders() throws {
        let keys = try Set(Self.sandboxPolicy().keys)
        XCTAssertTrue(keys.contains("com.apple.security.personal-information.calendars"))
        XCTAssertTrue(keys.contains("com.apple.security.personal-information.reminders"))
    }

    /// Joining a Noodle Hub can scan the invitation's QR code with the camera. A sandboxed app
    /// without the entitlement never gets a camera, and one without the usage text is killed.
    func testSandboxPolicyGrantsTheCameraForScanningInvitations() throws {
        XCTAssertTrue(try Set(Self.sandboxPolicy().keys).contains("com.apple.security.device.camera"))
        let info = try String(contentsOf: Self.repository.appendingPathComponent("Support/Info.plist"), encoding: .utf8)
        XCTAssertTrue(info.contains("<key>NSCameraUsageDescription</key>"))
    }

    /// Release verification pins how many entitlements the reviewed policy has, so an unreviewed one
    /// cannot ship: the policy alone, and a public release's, with its iCloud container and the two
    /// keys its provisioning profile adds. The pins have to follow the policy when it changes.
    func testReleaseVerifiersPinTheNumberOfEntitlementsThePolicyHas() throws {
        let expected = [try Self.sandboxPolicy().count, try Self.plist("Support/Noodle-Release.entitlements").count + 2]
        for script in ["scripts/verify-noodle-release.sh"] {
            let text = try String(contentsOf: Self.repository.appendingPathComponent(script), encoding: .utf8)
            let pinned = text
                .components(separatedBy: "expected_count=")
                .dropFirst()
                .compactMap { Int($0.prefix(while: { $0.isNumber })) }
            XCTAssertEqual(pinned, expected, script)
        }
    }

    /// A public release adds exactly the iCloud container to the reviewed policy, to tell devices away
    /// from the Hub about unread replies. Anything else it adds has to be reviewed here first.
    func testPublicReleasesAddOnlyTheICloudContainer() throws {
        let iCloud: NSDictionary = [
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.pdparchitect.noodle"],
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.icloud-container-environment": "Production",
        ]
        for (base, release) in [("Support/Noodle.entitlements", "Support/Noodle-Release.entitlements"),
                                ("Hub/Support/Hub.entitlements", "Hub/Support/Hub-Release.entitlements")] {
            let policy = try Self.plist(base)
            var added = try Self.plist(release)
            for (key, value) in policy {
                XCTAssertEqual(added.removeValue(forKey: key) as? NSObject, value as? NSObject, "\(release): \(key)")
            }
            XCTAssertEqual(added as NSDictionary, iCloud, release)
        }
    }

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func sandboxPolicy() throws -> [String: Any] {
        try plist("Support/Noodle.entitlements")
    }

    private static func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repository.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
