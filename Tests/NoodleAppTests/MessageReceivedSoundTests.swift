import XCTest
@testable import Noodle

final class MessageReceivedSoundTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sounds: URL!

    override func setUpWithError() throws {
        suiteName = "MessageReceivedSoundTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sounds = FileManager.default.temporaryDirectory
            .appendingPathComponent("MessageReceivedSoundTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: sounds)
    }

    func testBlowIsTheDefaultAndEveryChoiceIsASystemSound() {
        XCTAssertEqual(MessageReceivedSound.selected(in: defaults), "Blow")
        for name in MessageReceivedSound.names {
            XCTAssertNotNil(NSSound(named: name), name)
        }
    }

    func testNoneSilencesBothTheNotificationAndTheInAppSound() {
        defaults.set(MessageReceivedSound.none, forKey: MessageReceivedSound.defaultsKey)
        XCTAssertNil(MessageReceivedSound.selected(in: defaults))
        XCTAssertNil(MessageReceivedSound.notificationSound(in: defaults, soundsDirectory: sounds))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sounds.path))
    }

    func testNotificationsUseTheChosenSoundFromTheAppsSoundsFolder() throws {
        defaults.set("Tink", forKey: MessageReceivedSound.defaultsKey)
        XCTAssertNotNil(MessageReceivedSound.notificationSound(in: defaults, soundsDirectory: sounds))
        let copy = sounds.appendingPathComponent("Tink.aiff")
        XCTAssertEqual(try Data(contentsOf: copy),
                       try Data(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")))
    }

    func testForegroundPlaysOneInAppSoundPerBatchAndBackgroundLeavesItToNotifications() {
        XCTAssertTrue(MessageReceivedSound.playsInApp(newMessages: 3, presentsNotifications: false))
        XCTAssertFalse(MessageReceivedSound.playsInApp(newMessages: 3, presentsNotifications: true))
        XCTAssertFalse(MessageReceivedSound.playsInApp(newMessages: 0, presentsNotifications: false))
    }
}
