import Foundation
import WebKit

/// What each noodlet has saved: its data directory and, for HTML, its WebKit store.
@MainActor enum AppletStorage {
  static func sizes(root: URL) -> [String: Int] {
    let data = root.appendingPathComponent("Data")
    var sizes: [String: Int] = [:]
    for key in (try? FileManager.default.contentsOfDirectory(atPath: data.path)) ?? [] {
      let files = FileManager.default.enumerator(
        at: data.appendingPathComponent(key), includingPropertiesForKeys: [.fileSizeKey])
      var total = 0
      while let file = files?.nextObject() as? URL {
        total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      }
      sizes[key] = total
    }
    return sizes
  }
  static func remove(_ key: String, root: URL, defaults: UserDefaults) async {
    for folder in ["Data", "Homes"] {
      try? FileManager.default.removeItem(at: root.appendingPathComponent("\(folder)/\(key)"))
    }
    // WebKit crashes when removing a store is the first thing a process asks of it, as launch
    // does for a noodlet that is gone. A web view with no website data sets WebKit up first.
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let bootstrap = WKWebView(frame: .zero, configuration: configuration)
    defer { withExtendedLifetime(bootstrap) {} }
    for scope in ["user", "test"] {
      let name = "store.\(key).\(scope)"
      if let id = defaults.string(forKey: name).flatMap(UUID.init(uuidString:)) {
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
      }
      defaults.removeObject(forKey: name)
    }
  }
}
