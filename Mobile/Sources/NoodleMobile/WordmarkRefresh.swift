import NoodleBrand
import SwiftUI

extension View {
    /// Pull to refresh that writes the Noodle wordmark as the list is pulled down, instead of the spinner.
    func wordmarkRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(WordmarkRefresh(action: action))
    }
}

/// The word is written as far as the list is pulled, whole at the point where letting go refreshes,
/// and stays whole until the refresh is done.
struct WordmarkRefresh: ViewModifier {
    let action: @MainActor () async -> Void
    /// How far the list is pulled down past its top.
    @State private var pull: CGFloat = 0
    @State private var refreshing = false

    /// The pull at which the word is whole and letting go refreshes.
    static let threshold: CGFloat = 80
    static let wordWidth: CGFloat = 96

    static func progress(forPull pull: CGFloat) -> Double { Double(min(1, max(0, pull / threshold))) }

    static func refreshes(onReleaseAt pull: CGFloat) -> Bool { pull >= threshold }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, new in
                pull = max(0, new)
            }
            .onScrollPhaseChange { old, new in
                if old == .interacting, new != .interacting, !refreshing, Self.refreshes(onReleaseAt: pull) { refresh() }
            }
            // Holds the list down under the word while it refreshes.
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: refreshing ? Self.threshold : 0) }
            .overlay(alignment: .top) {
                Wordmark(progress: refreshing ? 1 : Self.progress(forPull: pull), wordWidth: Self.wordWidth)
                    .stroke(.secondary, style: StrokeStyle(
                        lineWidth: Wordmark.lineWidth(forWordWidth: Self.wordWidth), lineCap: .round, lineJoin: .round))
                    .frame(height: refreshing ? Self.threshold : pull)
                    .clipped()
                    .opacity(refreshing || pull > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: !refreshing && Self.refreshes(onReleaseAt: pull)) { !$0 && $1 }
            .accessibilityAction(named: "Refresh") { refresh() }
    }

    private func refresh() {
        guard !refreshing else { return }
        withAnimation(.snappy) { refreshing = true }
        Task {
            await action()
            withAnimation(.easeOut(duration: 0.3)) { refreshing = false }
        }
    }
}
