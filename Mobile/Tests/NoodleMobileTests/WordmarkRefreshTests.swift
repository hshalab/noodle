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
