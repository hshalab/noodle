import HubLink
import SwiftUI

extension EnvironmentValues {
    /// Lifts a message out of the conversation with its reactions and actions, as a long press does in Messages.
    @Entry var focusMessage: @MainActor (MessageFocus) -> Void = { _ in }
}

/// A message held up over the conversation, where its text bubble was on screen.
struct MessageFocus: Identifiable {
    let message: LinkMessage
    /// The text bubble's frame in the window.
    let frame: CGRect
    let folded: Bool

    var id: UUID { message.id }
}

/// The text of a message in its bubble: inline markdown, and long messages folded until read.
struct MessageText: View {
    let text: String
    let folded: Bool
    let foreground: Color
    let background: Color
    var expand: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.markdown(text, onTint: onTint))
                .lineLimit(folded ? MessageFolding.foldedLines : nil)
            if folded {
                Button("Read more", action: expand)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(foreground)
        .tint(onTint ? foreground : .accentColor)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Your bubble is the tint, so its links take the text's colour.
    private var onTint: Bool { background == .accentColor }

    /// Inline markdown, with only web and mail links left tappable, as on the Mac.
    /// On a tinted bubble links are underlined, since they share the text's colour.
    static func markdown(_ body: String, onTint: Bool = false) -> AttributedString {
        guard var text = try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(body)
        }
        for run in text.runs {
            if let link = run.link, !["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                text[run.range].link = nil
            } else if onTint, run.link != nil {
                text[run.range].underlineStyle = .single
            }
        }
        return text
    }
}

/// As in Messages: the conversation blurs, the message lifts where it was, its reactions float above it
/// and its actions below, each moved on screen when the message sits too near an edge.
struct MessageActions: View {
    nonisolated static let reactions = ["❤️", "👍", "👎", "😂", "🎉", "❓", "👀", "⏳", "✅", "🙏", "🔥", "💡"]
    nonisolated private static let reactionSize: CGFloat = 44
    nonisolated private static let gap: CGFloat = 8
    nonisolated private static let menuWidth: CGFloat = 220

    let focus: MessageFocus
    let react: (String) -> Void
    let close: () -> Void
    @State private var shown = false
    @State private var menuHeight: CGFloat = 52

    private var isYours: Bool { focus.message.author == .you }

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.frame(in: .global)
            let layout = layout(in: area)
            ZStack(alignment: .topLeading) {
                Color.clear
                bubble
                    .frame(width: focus.frame.width, height: layout.bubble.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(shown ? 1.03 : 1)
                    .offset(x: layout.bubble.minX - area.minX, y: (shown ? layout.bubble.minY : focus.frame.minY) - area.minY)
                reactionBar
                    .frame(width: layout.bar.width)
                    .scaleEffect(shown ? 1 : 0.4, anchor: isYours ? .bottomTrailing : .bottomLeading)
                    .opacity(shown ? 1 : 0)
                    .offset(x: layout.bar.minX - area.minX, y: layout.bar.minY - area.minY)
                menu
                    .frame(width: Self.menuWidth)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { menuHeight = $0 }
                    .scaleEffect(shown ? 1 : 0.4, anchor: isYours ? .topTrailing : .topLeading)
                    .opacity(shown ? 1 : 0)
                    .offset(x: layout.menu.minX - area.minX, y: layout.menu.minY - area.minY)
            }
        }
        .background {
            Rectangle().fill(.ultraThinMaterial).opacity(shown ? 1 : 0).ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Close")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shown) { _, now in now }
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { shown = true } }
    }

    /// Where the message, the reactions and the actions go: the message stays put unless the others
    /// would leave the screen, and a message too tall to fit shows its start.
    private func layout(in area: CGRect) -> (bubble: CGRect, bar: CGRect, menu: CGRect) {
        Self.layout(message: focus.frame, yours: isYours, menuHeight: menuHeight, in: area)
    }

    nonisolated static func layout(message: CGRect, yours: Bool, menuHeight: CGFloat, in area: CGRect) -> (bubble: CGRect, bar: CGRect, menu: CGRect) {
        let barWidth = min(area.width - 24, CGFloat(reactions.count) * reactionSize + 12)
        let barHeight = reactionSize + 12
        let height = max(44, min(message.height, area.height - barHeight - menuHeight - 2 * gap))
        let lowest = area.maxY - menuHeight - gap - height
        let top = max(area.minY + barHeight + gap, min(message.minY, lowest))
        let bubble = CGRect(x: message.minX, y: top, width: message.width, height: height)
        func edge(_ width: CGFloat) -> CGFloat {
            let x = yours ? bubble.maxX - width : bubble.minX
            return min(max(x, area.minX + 12), area.maxX - 12 - width)
        }
        return (bubble,
                CGRect(x: edge(barWidth), y: bubble.minY - gap - barHeight, width: barWidth, height: barHeight),
                CGRect(x: edge(menuWidth), y: bubble.maxY + gap, width: menuWidth, height: menuHeight))
    }

    private var bubble: some View {
        MessageText(text: focus.message.body, folded: focus.folded,
                    foreground: isYours ? .white : .primary,
                    background: isYours ? .accentColor : Color(.secondarySystemBackground))
            .allowsHitTesting(false)
    }

    private var reactionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Self.reactions, id: \.self) { emoji in
                    let mine = focus.message.reactions.contains(LinkReaction(author: .you, emoji: emoji))
                    Button { choose { react(emoji) } } label: {
                        Text(emoji).font(.system(size: 28))
                            .frame(width: Self.reactionSize, height: Self.reactionSize)
                            .background { if mine { Circle().fill(.tint.opacity(0.3)) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mine ? .isSelected : [])
                }
            }
            .padding(6)
        }
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var menu: some View {
        VStack(spacing: 0) {
            Button { choose { UIPasteboard.general.string = focus.message.body } } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.body)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func choose(_ action: () -> Void) {
        action()
        dismiss()
    }

    private func dismiss() {
        withAnimation(.spring(duration: 0.25)) { shown = false } completion: { close() }
    }
}
