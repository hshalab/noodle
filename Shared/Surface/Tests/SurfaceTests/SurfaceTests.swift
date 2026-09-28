import CoreGraphics
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import Surface
import VideoToolbox
import XCTest

final class SurfaceTests: XCTestCase {
    private func image(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1 - gray, alpha: 1)
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    func testInputRoundTripsThroughJSON() throws {
        let inputs: [SurfaceInput] = [.pointer(.down, x: 10, y: 20, clickCount: 2), .scroll(x: 5, y: 6, dx: 0, dy: -40),
                                      .key(.enter), .text("héllo")]
        for input in inputs {
            XCTAssertEqual(try JSONDecoder().decode(SurfaceInput.self, from: JSONEncoder().encode(input)), input)
        }
        for control in inputs.map(SurfaceControl.input) + [.view(width: 1200, height: 800), .keyFrame, .rate(bitsPerSecond: 1_000_000)] {
            XCTAssertEqual(SurfaceControl(control.encoded), control)
        }
    }

    /// Packets travel as bytes, starting with a byte no JSON starts with.
    func testPacketsRoundTripAsBytes() throws {
        let packets = [SurfacePacket(sequence: 1, keyFrame: true, width: 1280, height: 800, parameterSets: [Data([1, 2]), Data([3])], sample: Data([9, 8, 7])),
                       SurfacePacket(sequence: 2, keyFrame: false, width: 1280, height: 800, parameterSets: [], sample: Data(repeating: 5, count: 1000))]
        let data = SurfacePacket.encode(packets)
        XCTAssertEqual(data.first, SurfacePacket.formatByte)
        XCTAssertNotEqual(data.first, UInt8(ascii: "{"))
        XCTAssertEqual(SurfacePacket.decode(data), packets)
        XCTAssertNil(SurfacePacket.decode(data.dropLast()), "a cut-short packet read as whole")
        XCTAssertNil(SurfacePacket.decode(Data("{}".utf8)))
    }

    /// The Mac's encoder makes H.264 a viewer can decode, at the surface's shape.
    func testEncodedFramesDecode() throws {
        let encoder = SurfaceEncoder(maxPixelSize: 640, fps: 30)
        let first = try XCTUnwrap(try encoder.encode(image(width: 1280, height: 800, gray: 0.2), size: CGSize(width: 640, height: 400)))
        XCTAssertTrue(first.keyFrame)
        XCTAssertEqual(first.parameterSets.count, 2)
        let second = try XCTUnwrap(try encoder.encode(image(width: 1280, height: 800, gray: 0.3), size: CGSize(width: 640, height: 400)))
        XCTAssertFalse(second.keyFrame)
        let packet = SurfacePacket(sequence: 1, keyFrame: true, width: 640, height: 400, parameterSets: first.parameterSets, sample: first.sample)
        let format = try XCTUnwrap(SurfaceSamples.format(packet))
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        XCTAssertEqual(dimensions.width, 640)
        XCTAssertEqual(dimensions.height, 400)
        let sample = try XCTUnwrap(SurfaceSamples.sample(packet, format: format))
        var session: VTDecompressionSession?
        XCTAssertEqual(VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                                    imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &session), noErr)
        var decoded: CVImageBuffer?
        let status = VTDecompressionSessionDecodeFrame(try XCTUnwrap(session), sampleBuffer: sample, flags: [], infoFlagsOut: nil) { _, _, buffer, _, _ in
            decoded = buffer
        }
        XCTAssertEqual(status, noErr)
        VTDecompressionSessionWaitForAsynchronousFrames(session!)
        XCTAssertEqual(decoded.map(CVPixelBufferGetWidth), 640)
    }

    /// A red square top left on white, in the layout WebKit snapshots come in or in another.
    private func marked(width: Int, height: Int, webKitLayout: Bool) -> CGImage {
        let info = webKitLayout ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                                : CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // Core Graphics counts rows from the bottom.
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    /// The colour at a point of a decoded frame, as the display would show it.
    private func decodedColour(_ encoded: (sample: Data, parameterSets: [Data], keyFrame: Bool),
                               at point: (x: Double, y: Double)) throws -> (red: Int, green: Int, blue: Int) {
        let packet = SurfacePacket(sequence: 1, keyFrame: true, width: 1, height: 1, parameterSets: encoded.parameterSets, sample: encoded.sample)
        let format = try XCTUnwrap(SurfaceSamples.format(packet))
        let sample = try XCTUnwrap(SurfaceSamples.sample(packet, format: format))
        var session: VTDecompressionSession?
        let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
        XCTAssertEqual(VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                                    imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session), noErr)
        var decoded: CVImageBuffer?
        VTDecompressionSessionDecodeFrame(try XCTUnwrap(session), sampleBuffer: sample, flags: [], infoFlagsOut: nil) { _, _, buffer, _, _ in
            decoded = buffer
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session!)
        let buffer = try XCTUnwrap(decoded)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let x = Int(point.x * Double(CVPixelBufferGetWidth(buffer))), y = Int(point.y * Double(CVPixelBufferGetHeight(buffer)))
        let pixel = CVPixelBufferGetBaseAddress(buffer)!.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        return (Int(pixel[2]), Int(pixel[1]), Int(pixel[0]))
    }

    /// Scaled down, the picture keeps its colours and which way up it is, whichever layout it came in.
    func testEncodedFramesShowThePicture() throws {
        for webKitLayout in [true, false] {
            let encoder = SurfaceEncoder(maxPixelSize: 640, fps: 30)
            let encoded = try XCTUnwrap(try encoder.encode(marked(width: 1280, height: 800, webKitLayout: webKitLayout),
                                                           size: CGSize(width: 640, height: 400)))
            let red = try decodedColour(encoded, at: (0.25, 0.25)), white = try decodedColour(encoded, at: (0.75, 0.75))
            XCTAssert(red.red > 200 && red.green < 60 && red.blue < 60, "top left \(red), WebKit layout \(webKitLayout)")
            XCTAssert(white.red > 220 && white.green > 220 && white.blue > 220, "bottom right \(white), WebKit layout \(webKitLayout)")
        }
    }

    /// Two ends of a live view's connection, as a companion and the Hub hold them.
    private func pair() throws -> (SurfaceSocket, SurfaceSocket) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let ends = (SurfaceSocket(fd: fds[0]), SurfaceSocket(fd: fds[1]))
        addTeardownBlock { ends.0.close(); ends.1.close() }
        return ends
    }

    private func packets(from socket: SurfaceSocket, until done: @escaping ([SurfacePacket]) -> Bool) async throws -> [SurfacePacket] {
        let task = Task {
            var received: [SurfacePacket] = []
            for await frame in socket.frames {
                received += SurfacePacket.decode(frame) ?? []
                if done(received) { break }
            }
            return received
        }
        let timeout = Task { try await Task.sleep(for: .seconds(10)); task.cancel() }
        defer { timeout.cancel() }
        return await task.value
    }

    /// Frames cross in order both ways, and closing one end ends the other.
    func testASocketCarriesFramesBothWays() async throws {
        let (companion, hub) = try pair()
        companion.send(Data([1, 2, 3]))
        companion.send(Data(repeating: 7, count: 200_000))
        hub.send(Data("{}".utf8))
        var down: [Data] = []
        for await frame in hub.frames { down.append(frame); if down.count == 2 { break } }
        XCTAssertEqual(down, [Data([1, 2, 3]), Data(repeating: 7, count: 200_000)])
        for await frame in companion.frames { XCTAssertEqual(frame, Data("{}".utf8)); break }
        companion.close()
        var more = 0
        for await _ in hub.frames { more += 1 }
        XCTAssertEqual(more, 0)
    }

    /// Video starts at a key frame as soon as someone watches, fits the viewer's window in
    /// steps, and what the viewer does reaches the surface in the order they did it.
    @MainActor func testTheStreamerPushesVideoAndTakesInput() async throws {
        let picture = image(width: 1600, height: 1000, gray: 0.5)
        var applied: [SurfaceInput] = []
        let streamer = SurfaceStreamer(fps: 60, maxPixelSize: 1600, capture: { (picture, CGSize(width: 800, height: 500)) },
                                       apply: { applied.append($0) })
        defer { streamer.stop() }
        let (companion, hub) = try pair()
        XCTAssertFalse(streamer.isWatched)
        streamer.attach(companion)
        XCTAssertTrue(streamer.isWatched)

        let first = try await packets(from: hub) { $0.count >= 3 }
        XCTAssertEqual(first.first?.keyFrame, true, "video did not start at a key frame")
        XCTAssertEqual(first.first?.size, CGSize(width: 800, height: 500))
        XCTAssertEqual(first.first.flatMap(SurfaceSamples.format).map(CMVideoFormatDescriptionGetDimensions)?.width, 1600)

        // 400 × 400 rounds up to a 512 box; the surface keeps its shape inside it.
        hub.send(SurfaceControl.view(width: 400, height: 400).encoded)
        let fitted = try await packets(from: hub) { received in
            received.contains { $0.keyFrame && SurfaceSamples.format($0).map(CMVideoFormatDescriptionGetDimensions)?.width == 512 }
        }
        let key = CMVideoFormatDescriptionGetDimensions(try XCTUnwrap(fitted.last { $0.keyFrame }.flatMap(SurfaceSamples.format)))
        XCTAssertEqual(key.width, 512)
        XCTAssertEqual(key.height, 320)

        let click: [SurfaceInput] = [.pointer(.down, x: 5, y: 5), .pointer(.up, x: 5, y: 5), .text("go")]
        click.forEach { hub.send(SurfaceControl.input($0).encoded) }
        for _ in 0..<100 where applied.count < click.count { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(applied, click)

        hub.close()
        for _ in 0..<100 where streamer.isWatched { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(streamer.isWatched, "the view stayed watched after its viewer left")
    }

    /// A surface that stops changing settles in a few frames and then sends nothing, until it
    /// changes again or a viewer asks for a key frame.
    @MainActor func testAStillSurfaceStopsSendingUntilItChanges() async throws {
        let still = image(width: 800, height: 500, gray: 0.5), changed = image(width: 800, height: 500, gray: 0.8)
        var picture = still
        let streamer = SurfaceStreamer(fps: 60, maxPixelSize: 800, capture: { (picture, CGSize(width: 800, height: 500)) }, apply: { _ in })
        defer { streamer.stop() }
        let (companion, hub) = try pair()
        streamer.attach(companion)
        // One reader for the whole test: a quiet stream must stay open to show what comes later.
        var received: [SurfacePacket] = []
        let reader = Task { @MainActor in for await frame in hub.frames { received += SurfacePacket.decode(frame) ?? [] } }
        defer { reader.cancel() }
        func wait(_ label: String, until done: () -> Bool) async throws {
            for _ in 0..<250 where !done() { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(done(), label)
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(received.first?.keyFrame, true)
        XCTAssertLessThan(received.count, 15, "a still surface sent \(received.count) frames in a second")

        let quiet = received.count
        picture = changed
        try await wait("a change was not sent") { received.count > quiet }
        try await Task.sleep(for: .milliseconds(500))
        let settled = received.count
        hub.send(SurfaceControl.keyFrame.encoded)
        try await wait("a key frame asked for on a still surface never came") { received.dropFirst(settled).contains(where: \.keyFrame) }
    }

    /// A settled surface is looked at only now and then, and at full pace again as soon as the
    /// viewer does something, since that is when it is about to change.
    @MainActor func testAStillSurfaceIsCapturedLessUntilTheViewerActs() async throws {
        let picture = image(width: 800, height: 500, gray: 0.5)
        var captures = 0
        let streamer = SurfaceStreamer(fps: 60, maxPixelSize: 800, capture: {
            captures += 1
            return (picture, CGSize(width: 800, height: 500))
        }, apply: { _ in })
        defer { streamer.stop() }
        let (companion, hub) = try pair()
        streamer.attach(companion)
        let reader = Task { for await _ in hub.frames {} }
        defer { reader.cancel() }
        func captured(over interval: Duration) async throws -> Int {
            let before = captures
            try await Task.sleep(for: interval)
            return captures - before
        }
        // The attach itself counts as the viewer acting.
        try await Task.sleep(for: .seconds(1.5))
        let still = try await captured(over: .seconds(1))
        XCTAssertLessThan(still, 20, "a still surface was captured \(still) times a second")

        hub.send(SurfaceControl.input(.pointer(.move, x: 1, y: 1)).encoded)
        let acting = try await captured(over: .milliseconds(500))
        XCTAssertGreaterThan(acting, still, "input did not bring back the full pace")
    }

    /// A viewer that falls behind misses frames rather than getting old ones late, and always
    /// picks up again at a key frame, since the frames between depend on the ones before.
    @MainActor func testASlowViewerSkipsToTheNextKeyFrame() async throws {
        let pictures = (0..<8).map { noise(width: 800, height: 500, seed: CGFloat($0) / 8) }
        var next = 0
        let streamer = SurfaceStreamer(fps: 60, maxPixelSize: 800, capture: {
            next += 1
            return (pictures[next % pictures.count], CGSize(width: 800, height: 500))
        }, apply: { _ in })
        defer { streamer.stop() }
        // A small buffer and a reader that stops reading for a while, as a slow network would be.
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        var buffer: Int32 = 4096
        for fd in fds {
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &buffer, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buffer, socklen_t(MemoryLayout<Int32>.size))
        }
        let companion = SurfaceSocket(fd: fds[0]), reader = fds[1]
        defer { companion.close(); close(reader) }
        streamer.attach(companion)
        // Until the viewer is behind, then long enough for frames to pass it by.
        for _ in 0..<500 where companion.pending < 3 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertGreaterThanOrEqual(companion.pending, 3, "the viewer never fell behind")
        try await Task.sleep(for: .milliseconds(500))
        let received = await Task.detached { () -> [SurfacePacket] in
            func read(_ count: Int) -> Data? {
                var data = Data(count: count), offset = 0
                while offset < count {
                    let got = data.withUnsafeMutableBytes { Darwin.read(reader, $0.baseAddress!.advanced(by: offset), count - offset) }
                    guard got > 0 else { return nil }
                    offset += got
                }
                return data
            }
            var packets: [SurfacePacket] = []
            while packets.count < 40, let header = read(4), let frame = read(header.reduce(0) { ($0 << 8) | Int($1) }) {
                packets += SurfacePacket.decode(frame) ?? []
            }
            return packets
        }.value
        XCTAssertEqual(received.first?.keyFrame, true)
        var gaps = 0
        for (before, after) in zip(received, received.dropFirst()) where after.sequence != before.sequence + 1 {
            gaps += 1
            XCTAssertTrue(after.keyFrame, "after missing frames, video resumed at \(after.sequence), which is not a key frame")
        }
        XCTAssertGreaterThan(gaps, 0, "a viewer that fell behind got every frame late")
    }

    /// A viewer on a slow link asks for less, and the video it gets shrinks to fit.
    @MainActor func testTheStreamerKeepsToTheRateAViewerAsksFor() async throws {
        // Rate control is the hardware encoder's; the software one in a virtual machine keeps its own pace.
        try skipWithoutHardwareEncoder()
        let pictures = (0..<8).map { noise(width: 800, height: 500, seed: CGFloat($0) / 8) }
        var next = 0
        let streamer = SurfaceStreamer(fps: 30, maxPixelSize: 800, capture: {
            next += 1
            return (pictures[next % pictures.count], CGSize(width: 800, height: 500))
        }, apply: { _ in })
        defer { streamer.stop() }
        let (companion, hub) = try pair()
        streamer.attach(companion)
        // The encoder keeps to a rate by dropping frames as well as by shrinking them, so count bytes a second.
        func bytesPerSecond() async throws -> Double {
            let start = ContinuousClock.now
            let frames = try await packets(from: hub) { _ in ContinuousClock.now - start > .seconds(2) }.filter { !$0.keyFrame }
            return Double(frames.reduce(0) { $0 + $1.sample.count }) / ((ContinuousClock.now - start) / .seconds(1))
        }
        let full = try await bytesPerSecond()
        hub.send(SurfaceControl.rate(bitsPerSecond: 100_000).encoded)
        let slowed = try await bytesPerSecond()
        XCTAssertLessThan(slowed, full / 2, "video stayed at \(Int(slowed)) bytes a second, from \(Int(full)), after the viewer asked for less")
    }

    /// The Hub passes video to a viewer only as fast as the viewer's link takes it: when the link
    /// stalls it asks the companion for less and a key frame, and passes nothing on until the
    /// line has cleared and that key frame comes.
    func testTheRelaySlowsVideoForAViewerThatFallsBehind() async throws {
        let (companion, hub) = try pair()
        let link = FakeLink()
        let relay = Task {
            await hub.relay(to: { frame in
                link.lock.withLock {
                    link.forwarded += SurfacePacket.decode(frame) ?? []
                    if link.stalled { link.backlog += frame.count }
                }
            }, backlog: { link.lock.withLock { link.stalled ? link.backlog : 0 } })
        }
        func frame(_ sequence: UInt64, key: Bool, bytes: Int) -> Data {
            SurfacePacket.encode([SurfacePacket(sequence: sequence, keyFrame: key, width: 800, height: 500,
                                                parameterSets: key ? [Data([1]), Data([2])] : [], sample: Data(count: bytes))])
        }
        companion.send(frame(1, key: true, bytes: 1_000_000))
        companion.send(frame(2, key: false, bytes: 20_000))
        var controls: [SurfaceControl] = []
        for await data in companion.frames {
            if let control = SurfaceControl(data) { controls.append(control) }
            if controls.contains(.keyFrame) { break }
        }
        guard case .rate(let rate)? = controls.first(where: { if case .rate = $0 { true } else { false } }) else {
            return XCTFail("the relay never asked for less video, only \(controls)")
        }
        XCTAssertLessThan(rate, 20_000_000)

        link.lock.withLock { link.stalled = false }
        companion.send(frame(3, key: false, bytes: 20_000))
        companion.send(frame(4, key: true, bytes: 100_000))
        companion.send(frame(5, key: false, bytes: 20_000))
        for _ in 0..<250 where link.lock.withLock({ link.forwarded.count }) < 3 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(link.lock.withLock { link.forwarded.map(\.sequence) }, [1, 4, 5])
        companion.close()
        await relay.value
    }

    /// Frames are captured on a steady beat: time spent capturing one does not push the next back.
    @MainActor func testTheStreamerKeepsItsBeatWhileCapturingTakesTime() async throws {
        // A virtual machine's timers are too coarse to hold a 50 ms beat.
        var virtual: Int32 = 0, size = MemoryLayout<Int32>.size
        sysctlbyname("kern.hv_vmm_present", &virtual, &size, nil, 0)
        try XCTSkipIf(virtual == 1, "this Mac is a virtual machine")
        let picture = image(width: 160, height: 100, gray: 0.5)
        var starts: [ContinuousClock.Instant] = []
        let streamer = SurfaceStreamer(fps: 20, maxPixelSize: 160, capture: {
            starts.append(.now)
            try await Task.sleep(for: .milliseconds(30))
            return (picture, CGSize(width: 160, height: 100))
        }, apply: { _ in })
        defer { streamer.stop() }
        let (companion, _) = try pair()
        streamer.attach(companion)
        for _ in 0..<250 where starts.count < 12 { try await Task.sleep(for: .milliseconds(20)) }
        let intervals = zip(starts, starts.dropFirst()).map { ($1 - $0) / .milliseconds(1) }.sorted()
        XCTAssertLessThan(intervals[intervals.count / 2], 60, "frames came every \(Int(intervals[intervals.count / 2])) ms instead of every 50")
    }

    private func skipWithoutHardwareEncoder() throws {
        var encoders: CFArray?
        VTCopyVideoEncoderList(nil, &encoders)
        try XCTSkipUnless((encoders as? [[String: Any]] ?? []).contains {
            $0[kVTVideoEncoderList_CodecType as String] as? CMVideoCodecType == kCMVideoCodecType_H264
                && $0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool == true
        }, "this Mac has no hardware H.264 encoder")
    }

    /// Encoding happens away from the main thread, which the surface and its app need for themselves.
    @MainActor func testEncodingLeavesTheMainThreadFree() async throws {
        let pictures = (0..<4).map { noise(width: 3200, height: 2000, seed: CGFloat($0) / 4) }
        var next = 0
        let streamer = SurfaceStreamer(fps: 30, maxPixelSize: 1600, capture: {
            next += 1
            return (pictures[next % pictures.count], CGSize(width: 1600, height: 1000))
        }, apply: { _ in })
        defer { streamer.stop() }
        let (companion, hub) = try pair()
        streamer.attach(companion)
        _ = try await packets(from: hub) { $0.count >= 3 }
        let drain = Task.detached { for await _ in hub.frames {} }
        defer { drain.cancel() }
        // Time the main thread spends working, which other processes on a busy machine cannot add to.
        func working() -> Double {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let thread = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, thread) }
            _ = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
            }
            return Double(info.user_time.seconds + info.system_time.seconds) * 1000
                + Double(info.user_time.microseconds + info.system_time.microseconds) / 1000
        }
        XCTAssertEqual(pthread_main_np(), 1)
        let before = working()
        try await Task.sleep(for: .seconds(1))
        let held = working() - before
        XCTAssertLessThan(held, 100, "the main thread worked \(Int(held)) ms of one second")
    }

    private func noise(width: Int, height: Int, seed: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var generator = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                context.setFillColor(red: .random(in: 0...1, using: &generator), green: seed, blue: .random(in: 0...1, using: &generator), alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 8, height: 8))
            }
        }
        return context.makeImage()!
    }

    /// A point on the viewer lands on the same spot of the surface, letterboxing included.
    func testViewerPointsMapToSurfacePoints() {
        let surface = CGSize(width: 1280, height: 800)
        let view = CGSize(width: 640, height: 600)
        XCTAssertEqual(SurfaceGeometry.surfacePoint(CGPoint(x: 320, y: 300), in: view, surface: surface), CGPoint(x: 640, y: 400))
        XCTAssertNil(SurfaceGeometry.surfacePoint(CGPoint(x: 320, y: 10), in: view, surface: surface), "a click in the letterbox reaches nothing")
    }
}

/// A viewer's link as the relay sees it: what got through, and what is still waiting while it stalls.
private final class FakeLink: @unchecked Sendable {
    let lock = NSLock()
    var stalled = true
    var backlog = 0
    var forwarded: [SurfacePacket] = []
}
