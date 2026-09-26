import Surface
import XCTest

/// Live video over a simulated link of a given speed: frames leave one after another and arrive
/// once the link has carried their bytes, so video sent faster than the link waits in line.
private struct Link {
    struct Result {
        /// How long each frame took from being sent to arriving, after the first seconds.
        var latencies: [Double] = []
        var shown = 0
        var bits = 0.0
        var seconds = 0.0
        var fps: Double { Double(shown) / seconds }
        var bitRate: Double { bits / seconds }
        var worstLatency: Double { latencies.sorted().dropLast(latencies.count / 20).last ?? 0 }
    }

    /// Link speed in bits per second at a given time.
    var speed: (Double) -> Double
    var delay = 0.01
    var fps = 30.0
    /// A key frame is this many times the size of the others.
    var keyFrameSize = 4.0

    func run(_ flow: inout SurfaceFlow, for duration: Double, measuringFrom start: Double) -> Result {
        var queue: [(sent: Double, bytes: Int, remaining: Double, shown: Bool)] = []
        var result = Result()
        var pacer = SurfacePacer(fps: Int(fps))
        var next = 0.0, wantsKeyFrame = true, lastKeyFrame = 0.0
        let step = 0.0005
        for tick in 0..<Int(duration / step) {
            let now = Double(tick) * step
            var budget = speed(now) / 8 * step
            while budget > 0, !queue.isEmpty {
                let carried = min(budget, queue[0].remaining)
                queue[0].remaining -= carried
                budget -= carried
                if queue[0].remaining <= 0 {
                    let frame = queue.removeFirst()
                    if frame.sent >= start, frame.shown {
                        result.latencies.append(now - frame.sent + delay)
                        result.shown += 1
                        result.bits += Double(frame.bytes * 8)
                    }
                }
            }
            guard now >= next else { continue }
            next = pacer.next(after: now)
            let keyFrame = wantsKeyFrame || now - lastKeyFrame >= 2
            let bytes = Int(flow.bitRate / 8 / fps * (keyFrame ? keyFrameSize : 1))
            let backlog = Int(queue.reduce(0) { $0 + $1.remaining })
            // The encoder makes one key frame for each request, whether or not it gets through.
            if keyFrame { wantsKeyFrame = false; lastKeyFrame = now }
            switch flow.admit(bytes: bytes, keyFrame: keyFrame, backlog: backlog, now: now) {
            case .send:
                queue.append((now, bytes, Double(bytes), true))
            case .skip:
                break
            case .skipUntilKeyFrame:
                wantsKeyFrame = true
            }
        }
        result.seconds = duration - start
        return result
    }
}

final class SurfaceFlowTests: XCTestCase {
    private let megabit = 1_000_000.0

    /// Video starting faster than the link can carry slows to what it can, rather than piling up
    /// seconds of frames that arrive late.
    func testVideoSlowsToALinkThatCannotKeepUp() {
        var flow = SurfaceFlow(bitRate: 8 * megabit, range: 0.5 * megabit...20 * megabit)
        let result = Link(speed: { _ in 3 * self.megabit }).run(&flow, for: 20, measuringFrom: 5)
        XCTAssertLessThan(result.worstLatency, 0.15)
        XCTAssertGreaterThan(result.fps, 25)
        XCTAssertGreaterThan(result.bitRate, 0.6 * 3 * megabit)
    }

    /// When the link suddenly slows, video catches up within a second instead of staying behind.
    func testVideoRecoversWhenTheLinkSlows() {
        var flow = SurfaceFlow(bitRate: 8 * megabit, range: 0.5 * megabit...20 * megabit)
        let link = Link(speed: { $0 < 5 ? 10 * self.megabit : 2 * self.megabit })
        let result = link.run(&flow, for: 15, measuringFrom: 6)
        XCTAssertLessThan(result.worstLatency, 0.15)
        XCTAssertGreaterThan(result.fps, 25)
    }

    /// With room to spare, video climbs back to full quality.
    func testVideoSpeedsUpWhenTheLinkHasRoom() {
        var flow = SurfaceFlow(bitRate: 1 * megabit, range: 0.5 * megabit...8 * megabit)
        let result = Link(speed: { _ in 50 * self.megabit }).run(&flow, for: 15, measuringFrom: 10)
        XCTAssertGreaterThan(flow.bitRate, 7 * megabit)
        XCTAssertGreaterThan(result.fps, 29)
    }

    /// A viewer that missed a frame cannot decode what follows, so it waits for the next key frame
    /// the line has room for.
    func testAViewerThatMissedAFrameWaitsForAKeyFrame() {
        var flow = SurfaceFlow(bitRate: 1 * megabit, range: 0.5 * megabit...8 * megabit)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 0, now: 0), .send)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 1_000_000, now: 0.03), .skipUntilKeyFrame)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 0, now: 2), .skip)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 1_000_000, now: 2.01), .skipUntilKeyFrame,
                       "a key frame that could not go did not ask for another")
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 0, now: 2.03), .send)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 0, now: 2.06), .send)
    }

    /// Frames stay on a steady beat however long each one takes, and a slow one gives up the
    /// beats it missed rather than rushing to make them up.
    func testThePacerKeepsABeat() {
        var pacer = SurfacePacer(fps: 10)
        XCTAssertEqual(pacer.next(after: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(pacer.next(after: 0.13), 0.2, accuracy: 1e-9)
        XCTAssertEqual(pacer.next(after: 0.21), 0.3, accuracy: 1e-9)
        XCTAssertEqual(pacer.next(after: 0.55), 0.6, accuracy: 1e-9)
        XCTAssertEqual(pacer.next(after: 0.6), 0.7, accuracy: 1e-9)
    }
}
