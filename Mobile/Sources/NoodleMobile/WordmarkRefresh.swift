import NoodleBrand
import SwiftUI

extension View {
    /// Pull to refresh that writes the Noodle wordmark as the list is pulled down. The system's
    /// refresh still holds the list and gives the feel; the app clears its spinner.
    func wordmarkRefreshable(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(WordmarkRefresh(action: action))
    }
}

/// The word is written as far as the list is pulled, whole from `threshold` on, and stays whole in
/// the gap the refresh holds open until it is done.
struct WordmarkRefresh: ViewModifier {
    let action: @MainActor () async -> Void
    /// How far the list is pulled down past where it rests; negative once it is scrolled up.
    @State private var pull: CGFloat = 0
    @State private var refreshing = false

    /// The pull at which the word is whole.
    static let threshold: CGFloat = 80
    /// The gap the system's refresh holds open above the list.
    static let heldGap: CGFloat = 60
    static let wordWidth: CGFloat = 96

    static func progress(forPull pull: CGFloat) -> Double { Double(min(1, max(0, pull / threshold))) }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, new in
                pull = new
            }
            .refreshable {
                refreshing = true
                await action()
                withAnimation(.easeOut(duration: 0.25)) { refreshing = false }
            }
            .overlay(alignment: .top) {
                // While refreshing the insets include the held gap, so the pull is only what is beyond it.
                let gap = max(0, refreshing ? Self.heldGap + pull : pull)
                Wordmark(progress: refreshing ? 1 : Self.progress(forPull: pull), wordWidth: Self.wordWidth)
                    .stroke(.primary, style: StrokeStyle(
                        lineWidth: Wordmark.lineWidth(forWordWidth: Self.wordWidth), lineCap: .round, lineJoin: .round))
                    .frame(height: gap)
                    .clipped()
                    .opacity(gap > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
