import Testing
import UIKit
@testable import NoodleMobile

@Suite struct AppBundleTests {
    @Test func homeScreenNameIsNoodle() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(name == "Noodle Dev")
    }

    @Test func versionComesFromTheVersionFile() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version?.split(separator: ".").count == 3)
    }

    /// Invitation links and QR codes are noodle://join-hub links, the same as on the Mac.
    @Test func invitationLinksOpenTheApp() {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        #expect(types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("noodle") == true })
    }

    /// The notification extension ships inside the app, as its own bundle, and shares the app's group,
    /// where the Hubs the phone joined are kept; without it a notification could not name the bot.
    @Test func theNotificationExtensionSharesTheAppsGroup() throws {
        let app = try #require(Bundle.main.bundleIdentifier)
        let group = try #require(AppGroup.identifier)
        #expect(group == "group.\(app)")
        let container = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
        #expect(AppGroup.hubs?.path.hasPrefix(container.path) == true)
        let plugIn = try #require(Bundle.main.builtInPlugInsURL?.appendingPathComponent("NoodleMobileNotifications.appex"))
        let bundle = try #require(Bundle(url: plugIn))
        #expect(bundle.bundleIdentifier == "\(app).notifications")
        #expect(bundle.object(forInfoDictionaryKey: "NoodleAppGroup") as? String == group)
        let point = (bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String
        #expect(point == "com.apple.usernotifications.service")
    }

    // TODO(NEXT_VERSION): remove with AppGroup.moveHubs and its call in NoodleMobileApp.init.
    /// Hubs joined before the extension move to the shared group once, with everything in their folders.
    @Test func hubsJoinedEarlierMoveToTheGroup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = root.appendingPathComponent("Old/Hubs"), new = root.appendingPathComponent("Group/Hubs")
        try FileManager.default.createDirectory(at: old.appendingPathComponent("hub"), withIntermediateDirectories: true)
        try Data("key".utf8).write(to: old.appendingPathComponent("hub/device.key"))

        AppGroup.moveHubs(from: old, to: new)
        #expect(try Data(contentsOf: new.appendingPathComponent("hub/device.key")) == Data("key".utf8))
        #expect(!FileManager.default.fileExists(atPath: old.path))

        // Never over Hubs already in the group.
        try FileManager.default.createDirectory(at: old.appendingPathComponent("other"), withIntermediateDirectories: true)
        AppGroup.moveHubs(from: old, to: new)
        #expect(!FileManager.default.fileExists(atPath: new.appendingPathComponent("other").path))
    }

    /// iOS refuses the camera and the Hub's local address to an app that does not say why it needs them.
    @Test func permissionsSayWhyTheyAreNeeded() {
        for key in ["NSCameraUsageDescription", "NSLocalNetworkUsageDescription", "NSMicrophoneUsageDescription"] {
            #expect((Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false, "\(key)")
        }
    }
}
