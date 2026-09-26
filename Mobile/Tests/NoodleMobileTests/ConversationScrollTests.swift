import Foundation
import HubLink
@testable import NoodleMobile
import SwiftUI
import Testing

@Suite struct ConversationScrollTests {
    private func message(from author: LinkMessage.Author) -> LinkMessage {
        LinkMessage(id: UUID(), conversationID: UUID(), author: author, body: "Hi", createdAt: Date(), delivered: true)
    }

    @Test func yourMessageShowsAtTheBottomWhereverYouWere() {
        #expect(ConversationScroll.target(for: message(from: .you), wasAtBottom: true) == .bottom)
        #expect(ConversationScroll.target(for: message(from: .you), wasAtBottom: false) == .bottom)
    }

    @Test func aReplyShowsFromItsTopOnlyWhenYouWereAtTheBottom() {
        #expect(ConversationScroll.target(for: message(from: .bot(UUID())), wasAtBottom: true) == .top)
        #expect(ConversationScroll.target(for: message(from: .bot(UUID())), wasAtBottom: false) == nil)
        #expect(ConversationScroll.target(for: message(from: .system), wasAtBottom: false) == nil)
    }

    @Test func atTheBottomAllowsForTheComposerAndShortConversations() {
        // 1000 of content in a 600 viewport, 100 of it under the composer: the end shows at offset 500.
        #expect(ConversationScroll.isAtBottom(contentOffset: 500, contentHeight: 1000, viewportHeight: 600, bottomInset: 100))
        #expect(!ConversationScroll.isAtBottom(contentOffset: 400, contentHeight: 1000, viewportHeight: 600, bottomInset: 100))
        #expect(ConversationScroll.isAtBottom(contentOffset: -50, contentHeight: 200, viewportHeight: 600, bottomInset: 100))
    }

    @Test func aPictureOfKnownSizeHoldsItsPlaceBeforeItLoads() {
        // Without a size, as from an older Hub, the placeholder stands in until the picture arrives.
        #expect(AttachmentView.pictureFrame(for: nil) == nil)
        #expect(AttachmentView.pictureFrame(for: LinkPixelSize(width: 1200, height: 900)) == CGSize(width: 240, height: 180))
        #expect(AttachmentView.pictureFrame(for: LinkPixelSize(width: 900, height: 1600)) == CGSize(width: 180, height: 320))
        // Small pictures fill the width, as they do once loaded.
        #expect(AttachmentView.pictureFrame(for: LinkPixelSize(width: 12, height: 12)) == CGSize(width: 240, height: 240))
        // A long strip stays big enough to tap.
        #expect(AttachmentView.pictureFrame(for: LinkPixelSize(width: 20_000, height: 10)) == CGSize(width: 240, height: 44))
    }
}
