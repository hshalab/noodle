@testable import NoodleMobile
import Testing

@Suite struct WordmarkRefreshTests {
    /// The word is written as far as the list is pulled, and is whole from the threshold on.
    @Test func theWordFollowsThePull() {
        #expect(WordmarkRefresh.progress(forPull: 0) == 0)
        #expect(WordmarkRefresh.progress(forPull: WordmarkRefresh.threshold / 2) == 0.5)
        #expect(WordmarkRefresh.progress(forPull: WordmarkRefresh.threshold) == 1)
        #expect(WordmarkRefresh.progress(forPull: WordmarkRefresh.threshold * 2) == 1)
    }
}

@Suite struct PullGapTests {
    /// The refresh starts while the finger is still down, before the system holds the list open, and the
    /// word keeps to the gap the list really leaves instead of spilling over the first rows.
    @Test func theWordKeepsToTheGapWhileStillHeld() {
        var gap = PullGap()
        gap.scrolled(offset: -100, inset: 100)
        gap.scrolled(offset: -200, inset: 100)
        gap.began()
        #expect(gap.height == 100)
        #expect(gap.progress == 1)

        // Let go: the system holds the list open by however much it likes.
        gap.scrolled(offset: -164, inset: 164)
        #expect(gap.height == 64)
        #expect(gap.progress == 1)

        // Done: the word stays whole as the list goes back up.
        gap.ended()
        gap.scrolled(offset: -164, inset: 130)
        #expect(gap.height == 64)
        #expect(gap.progress == 1)
        gap.scrolled(offset: -100, inset: 100)
        #expect(gap.height == 0)

        // Back at rest, the word follows the pull again.
        gap.scrolled(offset: -140, inset: 100)
        #expect(gap.height == 40)
        #expect(gap.progress == 0.5)
    }
}
