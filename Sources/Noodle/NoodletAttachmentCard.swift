import AppKit
import AppletBridge
import NoodleRuntime
import QuickLookThumbnailing
import SwiftUI

struct NoodletAttachmentCard: View {
    @Environment(NoodleStore.self) private var store
    let url: URL
    let shouldLoad: Bool
    @State private var title = "Noodlet"
    @State private var thumbnail: NSImage?
    @State private var unavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: unavailable ? "questionmark.square.dashed" : "square.grid.2x2")
                    .font(.system(size: 42)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            Text(title).font(.headline).lineLimit(1)
            Text(unavailable ? "Noodlet unavailable" : "Noodlet · Click to open")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(idealWidth: 304, maxWidth: 304)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
        .task(id: shouldLoad) {
            guard shouldLoad else { return }
            do {
                let preview = try await Self.load(url, from: store.applets)
                guard !Task.isCancelled else { return }
                title = preview.title
                thumbnail = preview.image
                unavailable = false
            } catch {
                if !Task.isCancelled { unavailable = true }
            }
        }
    }

    /// What each noodlet's card last showed, so the Shared popover shows the same without asking again.
    @MainActor private static var loaded: [URL: (title: String, image: NSImage?)] = [:]

    @MainActor static func shown(_ url: URL) -> (title: String, image: NSImage?)? { loaded[url] }

    /// The live noodlet's title and thumbnail, kept for the conversation's Shared popover.
    @MainActor static func load(_ url: URL, from applets: AppletController) async throws -> (title: String, image: NSImage?) {
        let access = try await oneOfFew { try await applets.resolvePreview(url) }
        defer { withExtendedLifetime(access) {} }
        var image = access.imageData.flatMap(NSImage.init(data:)) ?? NSImage(contentsOf: access.url.appendingPathComponent("preview.png"))
        if image == nil {
            let request = QLThumbnailGenerator.Request(fileAt: access.url,
                size: CGSize(width: 560, height: 300), scale: 1, representationTypes: .all)
            image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
        }
        loaded[url] = (access.title, image)
        return (access.title, image)
    }

    @MainActor private static var asking = 0
    @MainActor private static var waiting: [CheckedContinuation<Void, Never>] = []

    /// Applet answers only a few requests at once, and the Shared popover asks for every noodlet
    /// together, so they take turns and leave room for bots.
    @MainActor private static func oneOfFew<T>(_ body: () async throws -> T) async throws -> T {
        if asking < 2 { asking += 1 } else { await withCheckedContinuation { waiting.append($0) } }
        defer { if waiting.isEmpty { asking -= 1 } else { waiting.removeFirst().resume() } }
        return try await body()
    }
}
