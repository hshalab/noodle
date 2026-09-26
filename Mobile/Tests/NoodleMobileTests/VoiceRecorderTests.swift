import AVFoundation
@testable import NoodleMobile
import Speech
import Testing

@MainActor @Suite struct VoiceRecorderTests {
    // The engine delivers tapped audio on its own thread, never on the main actor.
    @Test func theMicrophoneTapRunsOffTheMainActor() async throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let stream = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(64))
        let sink = try VoiceAudioSink(url: url, targetFormat: target, continuation: stream.continuation)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: source)
        try engine.enableManualRenderingMode(.offline, format: source, maximumFrameCount: 4096)
        VoiceRecorder.tap(engine.mainMixerNode, into: sink)
        let sound = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 16_000))
        sound.frameLength = 16_000
        player.scheduleBuffer(sound, completionHandler: nil)
        try engine.start()
        player.play()
        let output = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4096))
        for _ in 0..<4 { _ = try engine.renderOffline(4096, to: output) }
        for _ in 0..<50 where sink.snapshot().duration == 0 { try await Task.sleep(for: .milliseconds(20)) }
        engine.stop()
        sink.finish()
        #expect(sink.snapshot().duration > 0)
    }
}
