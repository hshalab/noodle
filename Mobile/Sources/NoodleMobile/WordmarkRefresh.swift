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
    @State private var gap = PullGap()

    /// The pull at which the word is whole.
    static let threshold: CGFloat = 80
    static let wordWidth: CGFloat = 96

    static func progress(forPull pull: CGFloat) -> Double { Double(min(1, max(0, pull / threshold))) }

    /// Where the top of the list is, in the scroll view's terms.
    private struct Top: Equatable {
        var offset: CGFloat
        var inset: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Top.self) { Top(offset: $0.contentOffset.y, inset: $0.contentInsets.top) } action: { _, new in
                gap.scrolled(offset: new.offset, inset: new.inset)
            }
            .refreshable {
                gap.began()
                await action()
                gap.ended()
            }
            .overlay(alignment: .top) {
                Wordmark(progress: gap.progress, wordWidth: Self.wordWidth)
                    .stroke(.primary, style: StrokeStyle(
                        lineWidth: Wordmark.lineWidth(forWordWidth: Self.wordWidth), lineCap: .round, lineJoin: .round))
                    .frame(height: gap.height)
                    .clipped()
                    .opacity(gap.height > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// The gap above a list being pulled to refresh, which the word is drawn in. It is measured from where
/// the list rests without the refresh, because the system holds the list open only once the finger is
/// lifted, and by its own amount.
struct PullGap {
    private var offset: CGFloat = 0
    private var inset: CGFloat = 0
    /// The top inset without the refresh's, kept from the refresh starting until the list is back.
    private var restingInset: CGFloat = 0
    private var refreshing = false
    private var held = false

    mutating func scrolled(offset: CGFloat, inset: CGFloat) {
        (self.offset, self.inset) = (offset, inset)
        release()
        if !held { restingInset = inset }
    }

    mutating func began() { (refreshing, held) = (true, true) }

    mutating func ended() {
        refreshing = false
        release()
    }

    private mutating func release() {
        if held, !refreshing, inset <= restingInset + 0.5 { held = false }
    }

    var height: CGFloat { max(0, -(offset + restingInset)) }
    var progress: Double { held ? 1 : WordmarkRefresh.progress(forPull: height) }
}
