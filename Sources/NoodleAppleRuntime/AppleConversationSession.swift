import Foundation
import FoundationModels
import NoodleCore

/// The bot's one native session, resumed on every wake like a Codex thread.
/// Visible chat lives in Messenger; this is the model's own transcript.
@available(macOS 26, *)
struct AppleConversationSession: Codable {
    let transcript: Transcript
    var modelIdentifier: String? = nil

    static func file(in workspace: URL) -> URL {
        workspace.appendingPathComponent(".noodle/apple/transcript.json")
    }

    static func load(from file: URL) throws -> Self? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }

    func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(JSONEncoder().encode(self), to: file)
    }

    /// Images stay in their files. Keep a textual reference in the resumable
    /// transcript rather than serializing pixels or process-local image objects.
    static func persistable(_ transcript: Transcript) -> Transcript {
        #if canImport(FoundationModels, _version: 2)
        if #available(macOS 27, *) {
            return Transcript(entries: transcript.map { entry in
                guard case .prompt(var prompt) = entry else { return entry }
                prompt.segments = prompt.segments.map { segment in
                    guard case .attachment(let attachment) = segment else { return segment }
                    return .text(.init(id: attachment.id, content: "[Image attachment: \(attachment.label ?? "image"). The original file retains the image; these saved bytes contain no image data.]"))
                }
                return .prompt(prompt)
            })
        }
        #endif
        return transcript
    }

    /// macOS 26 fallback: keep complete turns, including their tool calls/results.
    /// Never restore the middle of a tool exchange. The runtime supplies fresh
    /// instructions and tool definitions.
    func recentEntries(reservingPromptBytes: Int = 0) -> [Transcript.Entry] {
        let budget = max(0, 6_000 - reservingPromptBytes)
        var turns: [[Transcript.Entry]] = []
        for entry in transcript {
            switch entry {
            case .instructions: continue
            case .prompt: turns.append([entry])
            default:
                if !turns.isEmpty { turns[turns.count - 1].append(entry) }
            }
        }
        var kept: [[Transcript.Entry]] = []
        var bytes = 0
        for turn in turns.suffix(8).reversed() {
            let count = turn.reduce(0) { $0 + $1.description.utf8.count }
            guard bytes + count <= budget else { break }
            bytes += count
            kept.append(turn)
        }
        return kept.reversed().flatMap { $0 }
    }
}
