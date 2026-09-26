import CoreGraphics
import Foundation

/// A companion's side of its live views: while anyone watches, it captures the surface on a
/// steady beat, encodes each picture away from the main thread while the next is captured, and
/// pushes it to every viewer at once. A beat that comes while the encoder is still busy is skipped. A viewer that falls
/// behind misses frames instead of getting old ones late, and picks up again at the next key
/// frame. What viewers do comes back on their sockets and reaches the surface in order.
@MainActor public final class SurfaceStreamer {
    private struct Viewer {
        let socket: SurfaceSocket
        var fit: CGSize?
        /// Skipping frames until a key frame, as a new viewer and one that fell behind do.
        var waiting = true
        /// Bits per second the viewer's link takes, once it has said.
        var rate: Double?
    }

    /// Frames a viewer may have queued before it counts as behind.
    private static let behind = 3

    private let capture: @MainActor () async throws -> (image: CGImage, size: CGSize)?
    private let apply: @MainActor (SurfaceInput) async throws -> Void
    private let encoder: EncoderQueue
    private let fps: Int
    private var viewers: [ObjectIdentifier: Viewer] = [:]
    private var sequence: UInt64 = 0
    private var loop: Task<Void, Never>?
    private var wantsKeyFrame = false
    private var encoding = false

    public init(fps: Int = 30, maxPixelSize: Int = 1600,
                capture: @escaping @MainActor () async throws -> (image: CGImage, size: CGSize)?,
                apply: @escaping @MainActor (SurfaceInput) async throws -> Void) {
        self.capture = capture
        self.apply = apply
        encoder = EncoderQueue(SurfaceEncoder(maxPixelSize: maxPixelSize, fps: Int32(fps)))
        self.fps = fps
    }

    /// Someone is watching, which keeps bots off the surface until they leave.
    public var isWatched: Bool { !viewers.isEmpty }

    /// Told when the first viewer arrives and when the last one leaves.
    public var watchingChanged: (@MainActor (Bool) -> Void)?

    /// Starts pushing video to `socket` and taking its viewer's controls, until either side closes it.
    public func attach(_ socket: SurfaceSocket) {
        let id = ObjectIdentifier(socket)
        let first = viewers.isEmpty
        viewers[id] = Viewer(socket: socket)
        wantsKeyFrame = true
        if first { watchingChanged?(true) }
        if loop == nil { start() }
        Task { [weak self] in
            for await frame in socket.frames {
                guard let control = SurfaceControl(frame) else { continue }
                await self?.handle(control, from: id)
            }
            self?.leave(id)
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        viewers.values.forEach { $0.socket.close() }
        let watched = isWatched
        viewers = [:]
        if watched { watchingChanged?(false) }
    }

    private func leave(_ id: ObjectIdentifier) {
        guard viewers.removeValue(forKey: id) != nil else { return }
        encoder.setBitRate(rate)
        if viewers.isEmpty { watchingChanged?(false) }
    }

    private func handle(_ control: SurfaceControl, from id: ObjectIdentifier) async {
        switch control {
        case .input(let input):
            try? await apply(input)
        case .view(let width, let height):
            viewers[id]?.fit = CGSize(width: width, height: height)
        case .keyFrame:
            viewers[id]?.waiting = true
            wantsKeyFrame = true
        case .rate(let bitsPerSecond):
            viewers[id]?.rate = bitsPerSecond
            encoder.setBitRate(rate)
        }
    }

    private func start() {
        loop = Task { [weak self, fps] in
            var pacer = SurfacePacer(fps: fps)
            let start = ContinuousClock.now
            while let self, !Task.isCancelled, self.isWatched {
                await self.step()
                let due = pacer.next(after: (ContinuousClock.now - start) / .seconds(1))
                try? await Task.sleep(until: start + .seconds(due), clock: .continuous)
            }
            self?.loop = nil
        }
    }

    /// The largest window any viewer shows the surface in, or none when one has not said.
    private var fit: CGSize? {
        let fits = viewers.values.map(\.fit)
        guard !fits.isEmpty, fits.allSatisfy({ $0 != nil }) else { return nil }
        return fits.compactMap { $0 }.reduce(.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
    }

    /// One encoding serves every viewer, so it goes at the pace of the slowest link.
    private var rate: Double? { viewers.values.compactMap(\.rate).min() }

    private func step() async {
        guard !encoding, let picture = try? await capture() else { return }
        let keyFrame = wantsKeyFrame
        wantsKeyFrame = false
        encoding = true
        Task {
            let encoded = await encoder.encode(picture.image, size: picture.size, keyFrame: keyFrame, fitting: fit)
            encoding = false
            if let encoded { send(encoded, size: picture.size) } else if keyFrame { wantsKeyFrame = true }
        }
    }

    private func send(_ encoded: (sample: Data, parameterSets: [Data], keyFrame: Bool), size: CGSize) {
        sequence += 1
        let packet = SurfacePacket(sequence: sequence, keyFrame: encoded.keyFrame, width: size.width, height: size.height,
                                   parameterSets: encoded.parameterSets, sample: encoded.sample)
        let frame = SurfacePacket.encode([packet])
        for (id, viewer) in viewers {
            if viewer.waiting, !packet.keyFrame { continue }
            if viewer.socket.pending >= Self.behind {
                viewers[id]?.waiting = true
                wantsKeyFrame = true
                continue
            }
            viewers[id]?.waiting = false
            viewer.socket.send(frame)
        }
    }
}

/// The encoder on a queue of its own, so encoding a frame never holds the main thread.
/// Nothing touches the encoder except on that queue.
private final class EncoderQueue: @unchecked Sendable {
    private let encoder: SurfaceEncoder
    private let queue = DispatchQueue(label: "com.pdparchitect.noodle.surface-encoder", qos: .userInteractive)

    init(_ encoder: SurfaceEncoder) { self.encoder = encoder }

    func encode(_ image: CGImage, size: CGSize, keyFrame: Bool,
                fitting: CGSize?) async -> (sample: Data, parameterSets: [Data], keyFrame: Bool)? {
        await withCheckedContinuation { done in
            queue.async { [self] in
                done.resume(returning: try? encoder.encode(image, size: size, keyFrame: keyFrame, fitting: fitting))
            }
        }
    }

    func setBitRate(_ bitRate: Double?) {
        queue.async { [self] in encoder.bitRate = bitRate }
    }
}
