import SwiftUI
import Testing
@testable import NoodleBrand

@Suite struct WordmarkTests {
    /// The written word, pen included, fills the website's wordmark box.
    @Test func wordmarkFillsItsBox() {
        let drawn = Wordmark.skeleton.boundingRect.insetBy(dx: -Wordmark.pen / 2, dy: -Wordmark.pen / 2)
        #expect(abs(drawn.minX - Wordmark.bounds.minX) < 1 && abs(drawn.maxX - Wordmark.bounds.maxX) < 1)
        #expect(abs(drawn.minY - Wordmark.bounds.minY) < 1 && abs(drawn.maxY - Wordmark.bounds.maxY) < 1)
    }

    /// Nothing before the pen starts; the whole word, and only the word, once it has finished.
    @Test func wordIsWrittenFromNothingToTheWholeWord() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        #expect(Wordmark(progress: 0, wordWidth: 400).path(in: rect).isEmpty)
        let whole = Wordmark(progress: 1, wordWidth: 400).path(in: rect).boundingRect
        #expect(abs(whole.width - 400 * Wordmark.skeleton.boundingRect.width / Wordmark.bounds.width) < 1)
        #expect(abs(whole.midX - rect.midX) < 20)
    }
}
