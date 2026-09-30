@testable import Surface
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
    /// The Hub sees only what the viewer says it has shown, a round trip after it arrives, as
    /// over QUIC, whose stack takes megabytes without saying; otherwise it sees the line itself.
    var confirmed = false
    /// Key frames only when asked for, as the encoder makes them now, rather than every two seconds.
    var keyFramesOnRequest = false
    /// For this long at the start, frames come at this rate whatever the Hub asks for, as when the
    /// companion encodes before the Hub's first word on the rate reaches it.
    var burst: (seconds: Double, bitRate: Double) = (0, 0)
    /// Up to this much longer for each word from the viewer, as the device and the air add.
    var jitter = 0.0

    func run(_ flow: inout SurfaceFlow, for duration: Double, measuringFrom start: Double) -> Result {
        var queue: [(sent: Double, bytes: Int, remaining: Double, shown: Bool, sequence: UInt64)] = []
        let delivery = SurfaceDelivery()
        var confirmations: [(at: Double, sequence: UInt64)] = []
        var sequence: UInt64 = 0
        var wobble: UInt64 = 1
        // The viewer says it will say what it shows as soon as its channel opens.
        if confirmed { confirmations.append((delay, 0)) }
        var result = Result()
        var pacer = SurfacePacer(fps: Int(fps))
        var next = 0.0, wantsKeyFrame = true, lastKeyFrame = 0.0
        let step = 0.0005
        for tick in 0..<Int(duration / step) {
            let now = Double(tick) * step
            while let first = confirmations.first, first.at <= now {
                delivery.shown(first.sequence, at: first.at)
                confirmations.removeFirst()
            }
            var budget = speed(now) / 8 * step
            while budget > 0, !queue.isEmpty {
                let carried = min(budget, queue[0].remaining)
                queue[0].remaining -= carried
                budget -= carried
                if queue[0].remaining <= 0 {
                    let frame = queue.removeFirst()
                    // Words from the viewer come in order, however much each wavers.
                    wobble = wobble &* 6364136223846793005 &+ 1442695040888963407
                    let late = jitter * Double(wobble >> 11) / Double(1 << 53)
                    confirmations.append((max(now + 2 * delay + late, confirmations.last?.at ?? 0), frame.sequence))
                    if frame.sent >= start, frame.shown {
                        result.latencies.append(now - frame.sent + delay)
                        result.shown += 1
                        result.bits += Double(frame.bytes * 8)
                    }
                }
            }
            guard now >= next else { continue }
            next = pacer.next(after: now)
            let keyFrame = wantsKeyFrame || (!keyFramesOnRequest && now - lastKeyFrame >= 2)
            let rate = now < burst.seconds ? burst.bitRate : flow.bitRate
            let bytes = Int(rate / 8 / fps * (keyFrame ? keyFrameSize : 1))
            let backlog = Int(queue.reduce(0) { $0 + $1.remaining })
            // The encoder makes one key frame for each request, whether or not it gets through.
            if keyFrame { wantsKeyFrame = false; lastKeyFrame = now }
            // Over QUIC nothing waits where the Hub can see it; the network holds it all.
            let decision = confirmed ? flow.admit(bytes: bytes, keyFrame: keyFrame, pending: 0, delivery: delivery, now: now)
                                     : flow.admit(bytes: bytes, keyFrame: keyFrame, backlog: backlog, now: now)
            switch decision {
            case .send:
                sequence += 1
                delivery.sent(sequence, bytes: bytes, at: now)
                queue.append((now, bytes, Double(bytes), true, sequence))
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

    /// A view starts live on a link no faster than it starts at, or slower, though the Hub
    /// learns of the link only from what the viewer says it has shown.
    func testAViewStartsLiveOnASlowLink() {
        for speed in [2.0, 1.0] {
            var flow = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...20 * megabit)
            // The first frame comes at the companion's own rate, before the Hub's word on the rate reaches it.
            let link = Link(speed: { _ in speed * self.megabit }, delay: 0.02, confirmed: true, keyFramesOnRequest: true,
                            burst: (0.01, 6 * megabit))
            let result = link.run(&flow, for: 4, measuringFrom: 1)
            // A frame takes a tenth of a second to cross a 1 Mbit/s link, and lateness is judged
            // with room for the link to waver.
            XCTAssertLessThan(result.worstLatency, 0.3, "on a \(speed) Mbit/s link, frames arrived up to \(result.worstLatency) s late")
            XCTAssertGreaterThan(result.fps, 20, "on a \(speed) Mbit/s link")
        }
    }

    /// Learning of the link only from what the viewer has shown, video still stays live when the
    /// link slows, and climbs back when it has room.
    func testConfirmedVideoFollowsTheLink() {
        var flow = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...20 * megabit)
        let slowing = Link(speed: { $0 < 5 ? 10 * self.megabit : 2 * self.megabit }, delay: 0.02, confirmed: true, keyFramesOnRequest: true)
        let result = slowing.run(&flow, for: 15, measuringFrom: 7)
        XCTAssertLessThan(result.worstLatency, 0.2, "after the link slowed, frames arrived up to \(result.worstLatency) s late")
        XCTAssertGreaterThan(result.fps, 25)

        // A near link wavers by more than its round trip takes.
        for (delay, jitter) in [(0.02, 0.0), (0.001, 0.03)] {
            var fast = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...8 * megabit)
            _ = Link(speed: { _ in 50 * self.megabit }, delay: delay, confirmed: true, keyFramesOnRequest: true, jitter: jitter)
                .run(&fast, for: 3, measuringFrom: 2)
            XCTAssertGreaterThan(fast.bitRate, 7 * megabit,
                                 "on a fast link wavering by \(jitter) s, video only reached \(fast.bitRate) bits a second in three seconds")
        }
    }

    /// Frames held back while the Hub waits for the viewer's first word, a key frame among them,
    /// leave it asking for one to go on from once the viewer speaks, instead of the view freezing.
    func testFramesHeldBackAtTheStartAreMadeUpFor() {
        let delivery = SurfaceDelivery()
        delivery.shown(0, at: 0)
        var flow = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...20 * megabit)
        XCTAssertEqual(flow.admit(bytes: 100_000, keyFrame: true, pending: 0, delivery: delivery, now: 0), .send)
        delivery.sent(1, bytes: 100_000, at: 0)
        XCTAssertEqual(flow.admit(bytes: 40_000, keyFrame: false, pending: 0, delivery: delivery, now: 0.03), .skip)
        XCTAssertEqual(flow.admit(bytes: 33_000, keyFrame: true, pending: 0, delivery: delivery, now: 0.06), .skip)
        delivery.shown(1, at: 0.1)
        XCTAssertEqual(flow.admit(bytes: 8_000, keyFrame: false, pending: 0, delivery: delivery, now: 0.1), .skipUntilKeyFrame,
                       "frames held back at the start were not made up for")
        XCTAssertEqual(flow.admit(bytes: 20_000, keyFrame: true, pending: 0, delivery: delivery, now: 0.13), .send)
    }

    /// For a viewer that says what it shows, a frame the network stack has not taken yet is not
    /// a line: two frames can reach the Hub together, and what the viewer says covers the rest.
    func testAFrameNotYetTakenIsNoLineForAViewerThatSpeaks() {
        let delivery = SurfaceDelivery()
        delivery.shown(0, at: 0)
        var flow = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...20 * megabit)
        XCTAssertEqual(flow.admit(bytes: 30_000, keyFrame: true, pending: 0, delivery: delivery, now: 0), .send)
        delivery.sent(1, bytes: 30_000, at: 0)
        XCTAssertEqual(flow.admit(bytes: 8_000, keyFrame: false, pending: 0, delivery: delivery, now: 0.05), .send)
        delivery.sent(2, bytes: 8_000, at: 0.05)
        XCTAssertEqual(flow.admit(bytes: 8_000, keyFrame: false, pending: 8_000, delivery: delivery, now: 0.051), .send)
        XCTAssertGreaterThanOrEqual(flow.bitRate, 2 * megabit, "a frame the stack had not taken yet cut the rate")
    }

    /// An answer that never comes is asked for again, instead of leaving the view frozen.
    func testAnAnswerThatNeverComesIsAskedForAgain() {
        var flow = SurfaceFlow(bitRate: 2 * megabit, range: 0.3 * megabit...20 * megabit)
        XCTAssertEqual(flow.admit(bytes: 10_000, keyFrame: true, backlog: 0, now: 0), .send)
        XCTAssertEqual(flow.admit(bytes: 10_000, keyFrame: false, backlog: 1_000_000, now: 0.03), .skipUntilKeyFrame)
        var time = 0.03, asked = 0
        while time < 2 {
            time += 1.0 / 30
            if flow.admit(bytes: 5_000, keyFrame: false, backlog: 0, now: time) == .skipUntilKeyFrame { asked += 1 }
        }
        XCTAssertEqual(asked, 1, "in two seconds without an answer it asked again \(asked) times")
    }

    /// A viewer that missed a frame cannot decode what follows, so it waits for the next key frame
    /// the line has room for, and asks again for one that came too soon only once there is room.
    func testAViewerThatMissedAFrameWaitsForAKeyFrame() {
        var flow = SurfaceFlow(bitRate: 1 * megabit, range: 0.5 * megabit...8 * megabit)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 0, now: 0), .send)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 1_000_000, now: 0.03), .skipUntilKeyFrame)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 0, now: 0.5), .skip)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 1_000_000, now: 0.51), .skip)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 0, now: 0.52), .skipUntilKeyFrame,
                       "a key frame that could not go was not asked for again once there was room")
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: true, backlog: 0, now: 0.53), .send)
        XCTAssertEqual(flow.admit(bytes: 4000, keyFrame: false, backlog: 0, now: 0.56), .send)
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
