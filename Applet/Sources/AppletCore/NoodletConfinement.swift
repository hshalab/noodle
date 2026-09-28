import AppletBridge
import Foundation

/// One toolchain process Applet wants run: the compiler, or a native noodlet.
public struct NoodletLaunch: Codable, Sendable {
  public var id: String
  public var executable: String
  public var arguments: [String]
  public var environment: [String: String]
  public var directory: String
  public var readable: [String]
  public var writable: [String]
  /// Manifest permissions the user granted that need a sandbox operation.
  public var devices: [String]
  /// Whether the user opened this noodlet. Only then is it heard and may it read
  /// the clipboard; everything else runs silent and out of reach of what was copied.
  public var foreground: Bool
  /// Whether the manifest asks for the network.
  public var network: Bool
  /// A granted microphone reaches the same audio server, so that grant keeps its audio.
  public var reachesAudioServer: Bool { foreground || devices.contains("microphone") }
  public init(
    id: String = UUID().uuidString, executable: String, arguments: [String],
    environment: [String: String], directory: String, readable: [String], writable: [String],
    devices: [String] = [], foreground: Bool = false, network: Bool = false
  ) {
    self.id = id
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.directory = directory
    self.readable = readable
    self.writable = writable
    self.devices = devices
    self.foreground = foreground
    self.network = network
  }
}

/// Native noodlet code is untrusted. App Sandbox refuses a nested sandbox, so the
/// unsandboxed host service applies this profile instead; outside a bundle Applet
/// applies it directly. Files are limited to the system, the toolchain and the
/// directories named in the launch. User-selected files arrive through Applet.
public enum NoodletConfinement {
  /// Apple developer directories and the compiler front end each one provides.
  public static let toolchains = [
    "/Applications/Xcode.app/Contents/Developer":
      "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend",
    "/Library/Developer/CommandLineTools": "/Library/Developer/CommandLineTools/usr/bin/swift-frontend",
  ]
  static let system = [
    "/System", "/usr", "/bin", "/sbin", "/dev", "/Library/Apple", "/Library/Fonts", "/private/etc",
    "/private/var/db/timezone",
  ]

  public static func profile(_ launch: NoodletLaunch, toolchain: String) -> String {
    let reads = system + [toolchain] + launch.readable + launch.writable
    var rules = [
      "(version 1)", "(deny default)", "(import \"system.sb\")", "(allow process-fork)",
      "(allow signal (target same-sandbox))", "(allow sysctl-read)",
      // Resolved like the reads below: /Applications/Xcode.app is a link wherever Xcode is selected by version.
      "(allow process-exec (literal \"/usr/bin/env\") (subpath \(quoted(path(toolchain)))))",
      "(allow file-read-metadata)",
      "(allow file-read* file-map-executable\n  "
        + reads.map { "(subpath \(quoted(path($0))))" }.joined(separator: "\n  ") + ")",
      "(allow file-read* file-write-data file-ioctl (literal \"/dev/null\") (literal \"/dev/tty\") (subpath \"/dev/fd\"))",
      // Foundation stages atomic writes here, under a name no other process can list.
      "(allow file-read* file-write* (regex #\"^/private/var/folders/[^/]+/[^/]+/T/TemporaryItems(/NSIRD_swift-frontend_[^/]+(/.*)?)?$\"))",
      // FoundationModels reports its model as not ready without the global domain.
      "(allow user-preference-read (preference-domain \"kCFPreferencesAnyApplication\"))",
      "(allow ipc-posix-shm)",
      "(allow iokit-open-user-client (iokit-user-client-class " + quotedList(drivers) + "))",
      "(allow mach-lookup (xpc-service-name \"com.apple.audio.AudioConverterService\"))",
    ]
    // Without the audio server the process finds no output device, so a noodlet
    // running where the user cannot see it cannot be heard either.
    var names = services + (launch.reachesAudioServer ? ["com.apple.audio.audiohald"] : [])
    if launch.foreground { names.append("com.apple.pasteboard.1") }
    if launch.network {
      names.append("com.apple.dnssd.service")
      // Addresses only: a local socket is another program on this Mac, such as an SSH agent.
      rules.append("(allow network-outbound (remote ip) (literal \"/private/var/run/mDNSResponder\"))")
    }
    // Apple's own sandbox gives each device these services.
    if launch.devices.contains("microphone") {
      rules.append("(allow device-microphone)")
      rules.append("(allow iokit-open-user-client (iokit-user-client-class \"IOAudioControlUserClient\" \"IOAudioEngineUserClient\"))")
      names.append("com.apple.cmio.registerassistantservice.system-extensions")
    }
    if launch.devices.contains("camera") {
      rules.append("(allow device-camera)")
      names += [
        "com.apple.applecamerad", "com.apple.appleh13camerad", "com.apple.cmio.registerassistantservice",
        "com.apple.cmio.registerassistantservice.system-extensions",
      ]
    }
    if launch.devices.contains("speech-recognition") {
      rules.append(
        "(allow mach-lookup (xpc-service-name \"com.apple.speech.localspeechrecognition\" "
          + "\"com.apple.SpeechRecognitionCore.brokerd\" \"com.apple.siri.embeddedspeech\"))")
    }
    rules.append("(allow mach-lookup (global-name " + quotedList(Array(Set(names)).sorted()) + "))")
    if !launch.writable.isEmpty {
      rules.append(
        "(allow file-write*\n  "
          + launch.writable.map { "(subpath \(quoted(path($0))))" }.joined(separator: "\n  ") + ")")
    }
    return rules.joined(separator: "\n")
  }
  /// What AppKit, SwiftUI, SpriteKit, Metal, Core ML, Vision, speech synthesis,
  /// WebKit and FoundationModels were seen to reach, each probed in this sandbox.
  /// Anything else fails like a missing framework feature.
  static let services = [
    "com.apple.CARenderServer", "com.apple.CoreServices.coreservicesd", "com.apple.accessibility.voices",
    "com.apple.appleneuralengine", "com.apple.audio.AudioComponentRegistrar", "com.apple.audio.AudioSession",
    "com.apple.coreservices.launchservicesd", "com.apple.cvmsServ", "com.apple.dock.fullscreen",
    "com.apple.dock.server", "com.apple.iconservices", "com.apple.iconservices.store", "com.apple.lsd.mapdb",
    "com.apple.modelmanager", "com.apple.pluginkit.pkd", "com.apple.tccd", "com.apple.tccd.system",
    "com.apple.window_proxies", "com.apple.windowmanager.server", "com.apple.windowserver.active",
    // Light and dark appearance changes arrive as distributed notifications.
    "com.apple.distributed_notifications@Uv3",
  ]
  /// The GPU, shared surfaces and power state.
  static let drivers = [
    "AGXDeviceUserClient", "IOSurfaceRootUserClient", "IOSurfaceAcceleratorClient", "RootDomainUserClient",
  ]

  /// Refuses anything but an Apple compiler working inside Applet's own storage.
  public static func process(_ launch: NoodletLaunch, within root: URL) throws -> Process {
    guard let toolchain = toolchains.first(where: { $0.value == launch.executable })?.key else {
      throw AppletError("Only the installed Apple Swift compiler may run confined.")
    }
    let base = path(root.path)
    for candidate in launch.readable + launch.writable + [launch.directory] {
      guard path(candidate).hasPrefix(base + "/") else {
        throw AppletError("Confined paths must stay inside Applet's storage.")
      }
    }
    // sandbox-exec is protected, so dyld variables only survive when set after it.
    let late = launch.environment.filter { $0.key.hasPrefix("DYLD_") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    process.arguments =
      ["-p", profile(launch, toolchain: toolchain), "/usr/bin/env"]
      + late.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + [launch.executable]
      + launch.arguments
    process.environment = launch.environment.filter { !$0.key.hasPrefix("DYLD_") }
    process.currentDirectoryURL = URL(fileURLWithPath: launch.directory)
    return process
  }

  // Seatbelt matches the kernel's resolved spelling, such as /private/var.
  static func path(_ path: String) -> String {
    if let resolved = realpath(path, nil) {
      defer { free(resolved) }
      return String(cString: resolved)
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path != "/" else { return "/" }
    let parent = Self.path(url.deletingLastPathComponent().path)
    return (parent == "/" ? "" : parent) + "/" + url.lastPathComponent
  }
  private static func quoted(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return String(decoding: try! encoder.encode(value), as: UTF8.self)
  }
  private static func quotedList(_ values: [String]) -> String { values.map(quoted).joined(separator: " ") }
}

/// Deliberately no executable of Applet's choosing. The host runs only an
/// installed Apple compiler, confined to paths inside Applet's storage.
@objc public protocol NoodletHostService {
  func launch(
    _ request: Data, input: FileHandle?, output: FileHandle, error: FileHandle,
    withReply reply: @escaping (String?) -> Void)
  func terminate(_ id: String)
}

@objc public protocol NoodletHostClient {
  func exited(_ id: String, status: Int32, signalled: Bool)
}
