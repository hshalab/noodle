@testable import NoodleMobile
import SwiftUI
import Testing

@Suite struct ComposerSizeTests {
    /// The message field and the plus beside it are as tall as the bots list's search field.
    @MainActor @Test func theComposerIsAsTallAsSearch() async throws {
        let list = NavigationStack {
            List { Text("Bot") }
                .listStyle(.plain)
                .searchable(text: .constant(""), prompt: "Search")
                .navigationBarTitleDisplayMode(.inline)
        }
        let scene = try #require(UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: list)
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(1))

        // The text field sits inside the glass capsule people see, the first view around it that is taller.
        let field = try #require(Self.searchField(in: window))
        let capsule = try #require(sequence(first: field as UIView, next: \.superview).first { $0.bounds.height > field.bounds.height })
        #expect(ChatView.controlHeight == capsule.bounds.height)
    }

    private static func searchField(in view: UIView) -> UISearchTextField? {
        if let field = view as? UISearchTextField { return field }
        return view.subviews.lazy.compactMap(searchField(in:)).first
    }
}
