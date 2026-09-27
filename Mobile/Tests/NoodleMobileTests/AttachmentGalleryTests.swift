import Foundation
import HubLink
@testable import NoodleMobile
import Testing

/// Opening one file of a message lets you swipe through the other files in it.
struct AttachmentGalleryTests {
    private func file(_ name: String, voice: Bool = false, url: String? = nil) -> LinkAttachment {
        LinkAttachment(id: UUID(), filename: name, mediaType: "application/octet-stream", byteCount: 1,
                       voice: voice ? LinkVoice(transcript: nil, duration: 1, waveform: [], localeIdentifier: nil) : nil,
                       url: url.flatMap(URL.init(string:)))
    }

    @Test func filesOfAMessageSwipeTogetherWithoutLinksOrVoice() {
        let one = file("One.png"), two = file("Two.pdf")
        let voice = file("Voice.m4a", voice: true), link = file("Site.webloc", url: "https://example.com")
        #expect(LinkAttachment.previewGallery(opening: two, among: [one, voice, link, two]).map(\.id) == [one.id, two.id])
        #expect(LinkAttachment.previewGallery(opening: link, among: [one, link, two]).map(\.id) == [link.id])
    }
}
