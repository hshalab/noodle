import SwiftUI
import NoodleBrand
import NoodleWallpaper

/// The first launch, in the main window: the wordmark writes itself, and Continue lifts it
/// to make room for the first bot's setup.
struct WelcomeView: View {
    @Environment(NoodleStore.self) private var store

    var body: some View {
        WordmarkWelcome {
            FirstBotSetupSheet(setup: store.harnessSetup, runtime: store.runtime, placement: .welcome)
        }
        .background {
            ConversationWallpaper(background: store.background(for: nil))
                .overlay(alignment: .top) { ConversationWindowHeaderShade() }
                .ignoresSafeArea()
        }
        // The main window keeps its toolbar, and with it its shape, while the welcome fills it.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                .sharedBackgroundVisibility(.hidden)
        }
    }
}
