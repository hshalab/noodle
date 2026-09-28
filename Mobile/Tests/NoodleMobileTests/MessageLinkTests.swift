import Foundation
import SwiftUI
@testable import NoodleMobile
import Testing

@Suite struct MessageLinkTests {
    /// On your blue bubble the tint would hide a link, so it is underlined in the text's colour instead.
    @Test func linksInYourBubbleAreUnderlined() {
        let text = MessageText.markdown("Similar to [this](https://example.com) one", onTint: true)
        let styles: [(link: URL?, underline: Text.LineStyle?)] = text.runs.map { ($0.link, $0.underlineStyle) }
        #expect(styles.filter { $0.link != nil }.map(\.underline) == [Text.LineStyle.single])
        #expect(styles.filter { $0.link == nil }.allSatisfy { $0.underline == nil })
    }

    @Test func linksInABotBubbleKeepTheTint() throws {
        let text = MessageText.markdown("Similar to [this](https://example.com) one", onTint: false)
        let underline: Text.LineStyle? = try #require(text.runs.first { $0.link != nil }).underlineStyle
        #expect(underline == nil)
    }
}
