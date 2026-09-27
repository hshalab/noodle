import SwiftUI

/// A first launch in a window: the wordmark writes itself, and Continue lifts it to make room
/// for `next`, the app's first step. `lifted` skips Continue: the wordmark writes itself
/// already at the top, above `next`. `gap` separates the lifted wordmark from `next`.
public struct WordmarkWelcome<Next: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var written = false
    @State private var ready = false
    @State private var continued = false
    private let lifted: Bool
    private let gap: CGFloat
    private let next: Next

    public init(lifted: Bool = false, gap: CGFloat = 32, @ViewBuilder next: () -> Next) {
        self.lifted = lifted
        self.gap = gap
        self.next = next()
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let wordWidth = min(size.width * 0.34, 360)
            let wordHeight = wordWidth * Wordmark.bounds.height / Wordmark.bounds.width
            let liftedScale = 0.5
            let liftedCentre: CGFloat = 64
            ZStack {
                Wordmark(progress: written ? 1 : 0, wordWidth: wordWidth)
                    .stroke(.primary, style: StrokeStyle(
                        lineWidth: Wordmark.lineWidth(forWordWidth: wordWidth), lineCap: .round, lineJoin: .round))
                    .scaleEffect(continued ? liftedScale : 1)
                    .offset(y: continued ? liftedCentre - size.height / 2 : 0)
                    .accessibilityElement()
                    .accessibilityLabel("Noodle")
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    if continued {
                        Spacer().frame(height: liftedCentre + wordHeight * liftedScale / 2 + gap)
                        next
                            .transition(.opacity.combined(with: .offset(y: 24)))
                        Spacer(minLength: 24)
                    } else {
                        Spacer()
                        Button("Continue") {
                            withAnimation(.spring(duration: 0.7, bounce: 0.1)) { continued = true }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .opacity(ready ? 1 : 0)
                        .offset(y: ready ? 0 : 12)
                        .disabled(!ready)
                        .padding(.bottom, size.height * 0.16)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: write)
    }

    private func write() {
        guard !written else { return }
        if lifted {
            continued = true
            ready = true
            if reduceMotion { written = true } else { withAnimation(.easeInOut(duration: 2.2).delay(0.2)) { written = true } }
        } else if reduceMotion {
            written = true
            ready = true
        } else {
            // A short pause, the swirl and the word in one stroke, then Continue rises in.
            withAnimation(.easeInOut(duration: 3.4).delay(0.55)) { written = true }
            withAnimation(.easeOut(duration: 0.5).delay(4.05)) { ready = true }
        }
    }
}
