import Foundation

/// How fast one viewer's video may go, worked out from what it has not received yet. Video
/// sent faster than the link carries waits in line and arrives late, so as soon as frames start
/// queueing the rate drops to what the link drains, and while the line stays empty it climbs
/// back. A viewer too far behind for that skips ahead to the next key frame instead.
///
/// It keeps no clock and does no I/O: callers say what time it is and how much is waiting.
public struct SurfaceFlow: Sendable {
    public enum Decision: Equatable, Sendable {
        case send
        /// Not this frame: the viewer is waiting for a key frame.
        case skip
        /// The viewer is too far behind and misses this frame, so it needs a key frame to go on.
        case skipUntilKeyFrame
    }

    /// Bits per second the encoder should aim for.
    public private(set) var bitRate: Double
    private let range: ClosedRange<Double>
    private var sent = 0
    private var last: (time: Double, delivered: Int, backlog: Int)?
    /// Bits per second the link carried while it had something to carry.
    private var drain: Double?
    /// What had been sent at the last cut.
    private var cutMark = 0
    private var waiting = false

    /// Waiting longer than this means the link is full.
    private static let congested = 0.05
    /// Waiting less than this means there is room.
    private static let clear = 0.01
    /// Waiting longer than this is too late to show, so the viewer skips ahead.
    private static let tooLate = 0.25

    public init(bitRate: Double, range: ClosedRange<Double>) {
        self.range = range
        self.bitRate = bitRate.clamped(to: range)
    }

    /// Whether to send a frame of `bytes` now, with `backlog` bytes sent before still on their way.
    public mutating func admit(bytes: Int, keyFrame: Bool, backlog: Int, now: Double) -> Decision {
        let delivered = sent - backlog
        let elapsed = last.map { now - $0.time } ?? 0
        if let last, elapsed > 0, last.backlog > 0 {
            // Only a busy link shows how fast it goes; an idle one only shows how fast video came.
            let carried = Double(delivered - last.delivered) * 8 / elapsed
            drain = drain.map { $0 * 0.8 + carried * 0.2 } ?? carried
        }
        last = (now, delivered, backlog)
        let speed = max(drain ?? bitRate, range.lowerBound)
        let delay = Double(backlog) * 8 / speed
        // Frames already in line say nothing new about the link, so one cut holds until they are through.
        if delivered >= cutMark {
            if delay > Self.congested {
                // Below what the link carries, by enough to clear the line in half a second.
                let target = max(speed - Double(backlog) * 8 / 0.5, speed / 2)
                bitRate = min(bitRate, target).clamped(to: range)
                cutMark = sent
            } else if delay > Self.clear, bitRate > speed * 0.9 {
                // A line starting to form: stay under the link, with room for the next key frame.
                bitRate = (speed * 0.9).clamped(to: range)
                cutMark = sent
            } else if delay < Self.clear {
                bitRate = (bitRate * (1 + 0.3 * elapsed)).clamped(to: range)
            }
        }
        // A key frame is the largest there is, so a viewer starting again waits for a clear line
        // rather than filling it straight back up.
        if waiting, !keyFrame { return .skip }
        if waiting, delay > Self.congested { return .skipUntilKeyFrame }
        if delay > Self.tooLate {
            waiting = true
            return .skipUntilKeyFrame
        }
        waiting = false
        sent += bytes
        return .send
    }
}

/// A steady beat for capturing frames. Each frame is due a fixed interval after the one before,
/// however long capturing and encoding took, and a frame that ran over gives up the beats it
/// missed rather than rushing to make them up.
public struct SurfacePacer: Sendable {
    private let interval: Double
    private var due: Double?

    public init(fps: Int) { interval = 1 / Double(max(1, fps)) }

    /// When the next frame is due, the work for the last one having finished at `now`.
    public mutating func next(after now: Double) -> Double {
        let next = (due ?? now) + interval
        due = next > now ? next : next + ((now - next) / interval).rounded(.down) * interval + interval
        return due!
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

/// How far behind a viewer is, from the frames it says it has shown. Video sent longer ago than
/// the shortest round trip, and not shown yet, is waiting somewhere on the way: in the network
/// as much as on this Mac, where the network stack takes megabytes without saying. A viewer
/// that never says leaves it at nothing.
public final class SurfaceDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private let origin = ContinuousClock.now
    private var unshown: [(sequence: UInt64, bytes: Int, sent: Double)] = []
    /// The shortest round trip lately, and when it was seen.
    private var fastest: (seconds: Double, at: Double)?
    /// How long the shortest round trip stands, so a path that gets slower is learnt again.
    private static let memory = 10.0
    /// Frames kept for a viewer that never says what it has shown.
    private static let limit = 1024

    public init() {}

    /// The viewer has shown the frame `sequence` and every one sent before it.
    public func shown(_ sequence: UInt64) { shown(sequence, at: now) }

    var now: Double { (ContinuousClock.now - origin) / .seconds(1) }

    func sent(_ sequence: UInt64, bytes: Int, at time: Double) {
        lock.withLock {
            unshown.append((sequence, bytes, time))
            if unshown.count > Self.limit { unshown.removeFirst(unshown.count - Self.limit) }
        }
    }

    func shown(_ sequence: UInt64, at time: Double) {
        lock.withLock {
            guard let index = unshown.lastIndex(where: { $0.sequence <= sequence }) else { return }
            if unshown[index].sequence == sequence {
                let trip = time - unshown[index].sent
                if fastest.map({ trip <= $0.seconds || time - $0.at > Self.memory }) ?? true { fastest = (trip, time) }
            }
            unshown.removeFirst(index + 1)
        }
    }

    /// Bytes sent longer ago than the shortest round trip that the viewer has not shown.
    func late(at time: Double) -> Int {
        lock.withLock {
            guard let fastest else { return 0 }
            return unshown.reduce(0) { $0 + ($1.sent < time - fastest.seconds ? $1.bytes : 0) }
        }
    }
}

public extension SurfaceSocket {
    /// Passes this companion's video on to one viewer, through `send`, only as fast as the
    /// viewer's link takes it; `backlog` is the bytes sent that have not left yet, and `delivery`
    /// what the viewer says it has shown, which also counts what the network holds. It asks the
    /// companion for less video as the line grows and for a key frame after skipping frames, and
    /// returns when the companion ends the view.
    func relay(to send: @escaping @Sendable (Data) -> Void, backlog: @escaping @Sendable () -> Int,
               delivery: SurfaceDelivery = SurfaceDelivery()) async {
        // The encoder never goes above what its picture size calls for, so this only caps.
        var flow = SurfaceFlow(bitRate: 20_000_000, range: 300_000...20_000_000)
        var asked = flow.bitRate
        for await frame in frames {
            let packets = SurfacePacket.decode(frame)
            let now = delivery.now
            let decision = flow.admit(bytes: frame.count, keyFrame: packets?.first?.keyFrame ?? false,
                                      backlog: max(backlog(), delivery.late(at: now)), now: now)
            // The new rate goes first, so a key frame asked for comes at it.
            if abs(flow.bitRate - asked) > asked / 10 {
                asked = flow.bitRate
                self.send(SurfaceControl.rate(bitsPerSecond: asked).encoded)
            }
            switch decision {
            case .send:
                if let sequence = packets?.last?.sequence { delivery.sent(sequence, bytes: frame.count, at: now) }
                send(frame)
            case .skip: break
            case .skipUntilKeyFrame: self.send(SurfaceControl.keyFrame.encoded)
            }
        }
    }
}
