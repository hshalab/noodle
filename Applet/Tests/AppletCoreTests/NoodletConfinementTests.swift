import AppletBridge
@testable import AppletCore
import XCTest

final class NoodletConfinementTests: XCTestCase {
    private func launch(_ root: URL, executable: String = NoodletConfinement.toolchains.values.sorted()[0], readable: [String]? = nil) -> NoodletLaunch {
        NoodletLaunch(executable: executable, arguments: [], environment: ["DYLD_FRAMEWORK_PATH": "/System/Library/Frameworks", "HOME": "/x"],
            directory: root.appendingPathComponent("Builds/A").path, readable: readable ?? [root.appendingPathComponent("Builds/A").path],
            writable: [root.appendingPathComponent("Data/A").path])
    }

    func testOnlyAppleCompilerInsideAppletStorageMayRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try NoodletConfinement.process(launch(root, executable: "/bin/sh"), within: root))
        XCTAssertThrowsError(try NoodletConfinement.process(launch(root, readable: [NSHomeDirectory()]), within: root))
        XCTAssertThrowsError(try NoodletConfinement.process(launch(root, readable: [root.path + "/Builds/../../Escape"]), within: root))
        let process = try NoodletConfinement.process(launch(root), within: root)
        XCTAssertEqual(process.executableURL?.path, "/usr/bin/sandbox-exec")
        // sandbox-exec drops dyld variables, so they are set behind it.
        XCTAssertEqual(process.arguments?[2...3], ["/usr/bin/env", "DYLD_FRAMEWORK_PATH=/System/Library/Frameworks"])
        XCTAssertEqual(process.environment, ["HOME": "/x"])
    }

    /// Seatbelt matches resolved paths, and an Xcode selected by version is reached through a link.
    func testCompilerMayRunFromAToolchainReachedThroughALink() throws {
        guard let installed = NoodletConfinement.toolchains.sorted(by: { $0.key < $1.key }).first(where: { FileManager.default.isExecutableFile(atPath: $0.value) }) else {
            throw XCTSkip("No Apple Swift compiler is installed.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("Developer")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: installed.key))

        let profile = NoodletConfinement.profile(launch(root), toolchain: link.path)
        let resolved = NoodletConfinement.path(installed.key)
        XCTAssertTrue(profile.contains("(allow process-exec (literal \"/usr/bin/env\") (subpath \"\(resolved)\"))"), profile)

        // The rule has to hold in the real sandbox too, not only read well.
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", profile, "/usr/bin/env", link.path + installed.value.dropFirst(installed.key.count), "-version"]
        process.standardOutput = output; process.standardError = output
        try process.run(); process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("Swift version"), text)
    }

    func testDevicesFollowGrantedPermissions() {
        let root = URL(fileURLWithPath: "/tmp/applet")
        var request = launch(root)
        XCTAssertFalse(NoodletConfinement.profile(request, toolchain: "/bin").contains("device-"))
        request.devices = ["microphone", "screen-capture"]
        let profile = NoodletConfinement.profile(request, toolchain: "/bin")
        XCTAssertTrue(profile.contains("(allow device-microphone)"))
        XCTAssertFalse(profile.contains("device-camera"))
        XCTAssertTrue(profile.contains("(deny default)"))
    }

    func testProfileKeepsFilesToTheNamedDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["Builds/A", "Data/A", "Data/B"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
            try Data("secret".utf8).write(to: root.appendingPathComponent(folder + "/file"))
        }
        // The shell stands in for the compiler; the rules are the ones a noodlet gets.
        let profile = NoodletConfinement.profile(launch(root), toolchain: "/bin")
        func run(_ script: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", profile, "/bin/sh", "-c", script]
            process.currentDirectoryURL = root.appendingPathComponent("Builds/A")
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        let path = NoodletConfinement.path(root.path)
        XCTAssertEqual(try run("cat '\(path)/Builds/A/file' && echo own > '\(path)/Data/A/new'"), 0)
        XCTAssertNotEqual(try run("cat '\(path)/Data/B/file'"), 0, "Another noodlet's data")
        XCTAssertNotEqual(try run("echo x > '\(path)/Builds/A/file'"), 0, "The build is read-only")
        XCTAssertNotEqual(try run("ls '\(NSHomeDirectory())'"), 0, "The user's home")
        XCTAssertNotEqual(try run("cat '\(NSHomeDirectory())/Library/Keychains/login.keychain-db'"), 0, "The login Keychain")
    }

    /// A noodlet running where the user cannot see it must not be heard either.
    func testSilentLaunchesLoseTheAudioServer() {
        let root = URL(fileURLWithPath: "/tmp/applet")
        var request = launch(root)
        let server = "\"com.apple.audio.audiohald\""
        XCTAssertFalse(NoodletConfinement.profile(request, toolchain: "/bin").contains(server))
        request.foreground = true
        XCTAssertTrue(NoodletConfinement.profile(request, toolchain: "/bin").contains(server))
        // Recording granted by the user reaches the same audio server, so it keeps it.
        request.foreground = false
        request.devices = ["microphone"]
        XCTAssertTrue(NoodletConfinement.profile(request, toolchain: "/bin").contains(server))
    }

    /// Runs a system tool as a noodlet would, and unconfined, so each check compares
    /// against what the same tool does on this Mac.
    private func compare(_ request: NoodletLaunch, _ tool: String, _ arguments: [String], environment: [String: String] = [:]) throws -> (confined: (Int32, String), plain: (Int32, String)) {
        func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            return (process.terminationStatus, text)
        }
        let profile = NoodletConfinement.profile(request, toolchain: "/usr/bin")
        return (try run("/usr/bin/sandbox-exec", ["-p", profile, tool] + arguments), try run(tool, arguments))
    }

    /// Like a page, a native noodlet reaches the network only when its manifest asks for it.
    func testNetworkFollowsTheManifest() throws {
        var request = launch(URL(fileURLWithPath: "/tmp/applet"))
        // Nothing listens on port 1: refused by the Mac when allowed, by the sandbox when not.
        let closed = ["-vz", "-w1", "127.0.0.1", "1"]
        let denied = try compare(request, "/usr/bin/nc", closed)
        XCTAssertTrue(denied.confined.1.contains("Operation not permitted"), denied.confined.1)
        request.network = true
        let allowed = try compare(request, "/usr/bin/nc", closed)
        XCTAssertTrue(allowed.confined.1.contains("Connection refused"), allowed.confined.1)
    }

    /// Network means internet addresses. Local sockets reach other programs on this Mac.
    func testNetworkLeavesOutLocalSockets() throws {
        var request = launch(URL(fileURLWithPath: "/tmp/applet"))
        request.network = true
        let result = try compare(request, "/usr/bin/nc", ["-U", "-w1", "/private/var/run/usbmuxd"])
        guard result.plain.0 == 0 else { throw XCTSkip("No usbmuxd socket to connect to: \(result.plain.1)") }
        XCTAssertNotEqual(result.confined.0, 0, result.confined.1)
    }

    /// The clipboard holds whatever the user copied last; only a noodlet they opened may read it.
    func testClipboardOnlyInTheForeground() throws {
        var request = launch(URL(fileURLWithPath: "/tmp/applet"))
        request.network = true
        let background = try compare(request, "/usr/bin/pbpaste", [])
        guard background.plain.0 == 0 else { throw XCTSkip("No pasteboard on this Mac: \(background.plain.1)") }
        XCTAssertNotEqual(background.confined.0, 0, "A noodlet out of sight read the clipboard.")
        request.foreground = true
        XCTAssertEqual(try compare(request, "/usr/bin/pbpaste", []).confined.0, 0)
    }

    /// Only services the frameworks need are named; the rest of the system stays out of reach.
    func testServicesAndDriversAreNamed() {
        let profile = NoodletConfinement.profile(launch(URL(fileURLWithPath: "/tmp/applet")), toolchain: "/bin")
        XCTAssertFalse(profile.contains("(allow mach-lookup)"), profile)
        XCTAssertFalse(profile.contains("(allow iokit-open)"), profile)
        XCTAssertTrue(profile.contains("\"com.apple.windowserver.active\""), profile)
    }

    /// FoundationModels reports its model as not ready without the global preferences.
    func testGlobalPreferencesAreReadable() throws {
        let result = try compare(launch(URL(fileURLWithPath: "/tmp/applet")), "/usr/bin/defaults", ["read", "-g"])
        guard result.plain.0 == 0 else { throw XCTSkip("No global preferences on this Mac.") }
        XCTAssertEqual(result.confined.0, 0, result.confined.1)
    }

    /// A granted device brings the services Apple's own sandbox gives it.
    func testDeviceServicesFollowGrantedPermissions() {
        var request = launch(URL(fileURLWithPath: "/tmp/applet"))
        let camera = "\"com.apple.applecamerad\"", speech = "\"com.apple.speech.localspeechrecognition\""
        let none = NoodletConfinement.profile(request, toolchain: "/bin")
        XCTAssertFalse(none.contains(camera) || none.contains(speech), none)
        request.devices = ["camera", "speech-recognition"]
        let granted = NoodletConfinement.profile(request, toolchain: "/bin")
        XCTAssertTrue(granted.contains(camera) && granted.contains(speech), granted)
    }
}
