import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Encodes pictures of a surface as H.264 with the Mac's video encoder, tuned for a live view:
/// no frame reordering, key frames only when asked for, and one frame out for each frame in until
/// the picture stops changing. Scaling and colour conversion happen on the GPU, so a frame costs the CPU little more than a copy.
public final class SurfaceEncoder {
    public struct Frame: Sendable {
        /// The frame's NAL units, each with a four-byte big-endian length (AVCC).
        public var sample: Data
        /// SPS and PPS, on key frames only.
        public var parameterSets: [Data]
        public var keyFrame: Bool
        /// Built only on a frame every viewer has shown, so a viewer that missed the frames
        /// since can go on from it without a key frame.
        public var recovery = false
        /// What to acknowledge once every viewer has shown this frame.
        var token: Int?
    }

    private var session: VTCompressionSession?
    private var transfer: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var pixels: (width: Int, height: Int) = (0, 0)
    private var frame: Int64 = 0
    /// When the session's first frame was taken, and the last frame's timestamp from then.
    private var origin: Double?
    private var stamped = CMTime.negativeInfinity
    /// The last picture at its own size, and for how many frames it has stayed the same.
    private var last: CVPixelBuffer?
    /// Whether the session keeps long-term references, which recovery frames are built on.
    private var longTermReferences = false
    /// Counts sessions, so a token from an earlier one is never acknowledged to this one.
    private var generation = 0
    /// Tokens of frames since the last key frame, those acknowledged and not yet passed on, and
    /// whether any has been, which a recovery frame needs.
    private var issued: Set<Int> = []
    private var acknowledged: [Int] = []
    private var canRecover = false
    private var unchanged = 0
    /// Frames still sent once the picture stops changing, so the encoder can sharpen what it
    /// sent while the picture moved before video goes quiet.
    private static let settle = 6

    /// The picture has stayed the same long enough that nothing more is sent for it.
    public var isSettled: Bool { unchanged > Self.settle }
    private let maxPixelSize: Int
    private let fps: Int32

    public init(maxPixelSize: Int = 1600, fps: Int32 = 30) {
        self.maxPixelSize = maxPixelSize
        self.fps = fps
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
    }

    /// The most bits per second a viewer's link takes, when one has said. Video never goes above
    /// what the picture size calls for, and follows a change from the next frame on.
    public var bitRate: Double? {
        didSet { if let session { Self.setBitRate(session, pixels: pixels, cap: bitRate) } }
    }

    /// The encoded frame, with the parameter sets when it is a key frame. `size` is the surface's
    /// size in points. `keyFrame` asks for one now, as when a new viewer arrives. `fitting` is the
    /// most pixels a viewer shows, rounded up in steps of 128 so resizing a window does not
    /// restart the encoder at every pixel; a new size starts at a key frame. Nothing comes back
    /// once the picture has settled, unless `keyFrame` asks for one. `time` is when the picture
    /// was taken, in seconds on any steady clock: rate control gives each frame the bits for the
    /// time since the last, so a surface captured slowly or after a pause gets sharper frames.
    /// Without it, frames count as coming at the encoder's frame rate.
    public func encode(_ image: CGImage, size: CGSize, keyFrame: Bool = false,
                       fitting: CGSize? = nil, at time: Double? = nil, recover: Bool = false) throws -> Frame? {
        var scale = min(1, Double(maxPixelSize) / Double(max(image.width, image.height)))
        if let fitting, fitting.width > 0, fitting.height > 0 {
            let box = (width: (fitting.width / 128).rounded(.up) * 128, height: (fitting.height / 128).rounded(.up) * 128)
            scale = min(scale, box.width / Double(image.width), box.height / Double(image.height))
        }
        // H.264 wants even dimensions.
        let width = max(2, Int(Double(image.width) * scale) & ~1), height = max(2, Int(Double(image.height) * scale) & ~1)
        if session == nil || pixels != (width, height) { try start(width: width, height: height) }
        guard let session, let source = Self.pixelBuffer(image) else { return nil }
        unchanged = last.map { Self.same(source, $0) } == true ? unchanged + 1 : 0
        last = source
        if isSettled, !keyFrame, !recover, frame > 0 { return nil }
        guard let buffer = scaled(source) else { return nil }
        var result: (Data, [Data], Bool, Int?)?
        var properties: [CFString: Any] = [:]
        if !acknowledged.isEmpty {
            properties[kVTEncodeFrameOptionKey_AcknowledgedLTRTokens] = acknowledged.map { NSNumber(value: $0 & 0xFFFF_FFFF) }
            acknowledged = []
            canRecover = true
        }
        // A frame built on one every viewer has shown, when there is one; a key frame otherwise.
        let recovering = recover && !keyFrame && frame > 0 && canRecover
        if keyFrame || frame == 0 || (recover && !recovering) { properties[kVTEncodeFrameOptionKey_ForceKeyFrame] = true }
        if recovering { properties[kVTEncodeFrameOptionKey_ForceLTRRefresh] = true }
        let taken = time ?? Double(frame) / Double(fps)
        origin = origin ?? taken
        var stamp = CMTime(seconds: taken - origin!, preferredTimescale: 90_000)
        if stamp <= stamped { stamp = stamped + CMTime(value: 1, timescale: 90_000) }
        stamped = stamp
        frame += 1
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: stamp,
                                                     duration: .invalid, frameProperties: properties as CFDictionary,
                                                     infoFlagsOut: nil) { status, _, sample in
            guard status == noErr, let sample else { return }
            result = Self.unpack(sample).map { unpacked in
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
                return (unpacked.0, unpacked.1, unpacked.2, (attachments?.first?[kVTSampleAttachmentKey_RequireLTRAcknowledgementToken] as? NSNumber)?.intValue)
            }
        }
        guard status == noErr else { throw SurfaceEncoderError(status: status) }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: stamp)
        guard let (sample, sets, isKey, token) = result else { return nil }
        if isKey { (issued, acknowledged, canRecover) = ([], [], false) }
        let tagged = token.map { generation << 32 | $0 }
        if let tagged { issued.insert(tagged) }
        return Frame(sample: sample, parameterSets: sets, keyFrame: isKey, recovery: recovering && !isKey, token: tagged)
    }

    private func start(width: Int, height: Int) throws {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil,
                                                refcon: nil, compressionSessionOut: &created)
        guard status == noErr, let created else { throw SurfaceEncoderError(status: status) }
        if transfer == nil {
            var made: VTPixelTransferSession?
            guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &made) == noErr, let made else {
                VTCompressionSessionInvalidate(created)
                throw SurfaceEncoderError(status: kVTAllocationFailedErr)
            }
            // Averaging keeps small text legible where dropping pixels would break its strokes.
            VTSessionSetProperty(made, key: kVTPixelTransferPropertyKey_DownsamplingMode, value: kVTDownsamplingMode_Average)
            VTSessionSetProperty(made, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
            VTSessionSetProperty(made, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
            VTSessionSetProperty(made, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
            transfer = made
        }
        pool = nil
        let attributes = [kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                          kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                          kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferPoolCreate(nil, nil, attributes, &pool) == kCVReturnSuccess else {
            VTCompressionSessionInvalidate(created)
            throw SurfaceEncoderError(status: kVTAllocationFailedErr)
        }
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        // The link loses nothing, and a key frame costs as much as a hundred others, so one comes
        // only for a viewer that needs it.
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 0 as CFNumber)
        VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        Self.setBitRate(created, pixels: (width, height), cap: bitRate)
        longTermReferences = VTSessionSetProperty(created, key: kVTCompressionPropertyKey_EnableLTR, value: kCFBooleanTrue) == noErr
        VTCompressionSessionPrepareToEncodeFrames(created)
        session = created
        pixels = (width, height)
        frame = 0
        origin = nil
        stamped = .negativeInfinity
        generation += 1
        (issued, acknowledged, canRecover) = ([], [], false)
    }

    /// Frames every viewer has shown, by their tokens, which recovery frames may be built on.
    /// Tokens from before the last key frame or of another session are left out.
    public func acknowledge(_ tokens: [Int]) {
        guard longTermReferences else { return }
        acknowledged += tokens.filter(issued.contains)
        issued.subtract(tokens)
    }

    private static func setBitRate(_ session: VTCompressionSession, pixels: (width: Int, height: Int), cap: Double?) {
        // Sharp text matters more than smooth motion for a desktop or page.
        let full = Double(pixels.width * pixels.height * 3)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: Int(min(full, cap ?? full)) as CFNumber)
    }

    /// The picture at the encoder's size, in the encoder's own format.
    private func scaled(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        guard let transfer, let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer,
              VTPixelTransferSessionTransferImage(transfer, from: source, to: buffer) == noErr else { return nil }
        return buffer
    }

    /// The picture at its own size, as the GPU can take it. A picture laid out as the Mac's
    /// screen is, as WebKit's snapshots are, is copied as it is; any other is drawn first.
    private static func pixelBuffer(_ image: CGImage) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let alpha = image.alphaInfo
        if image.bitsPerPixel == 32, image.bitsPerComponent == 8, image.bitmapInfo.contains(.byteOrder32Little),
           alpha == .premultipliedFirst || alpha == .noneSkipFirst, image.colorSpace?.model == .rgb,
           let data = image.dataProvider?.data, CFDataGetLength(data) >= image.bytesPerRow * image.height,
           let bytes = CFDataGetBytePtr(data) {
            for row in 0..<image.height {
                memcpy(base.advanced(by: row * rowBytes), bytes.advanced(by: row * image.bytesPerRow), image.width * 4)
            }
            return buffer
        }
        guard let context = CGContext(data: base, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private static func same(_ one: CVPixelBuffer, _ other: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(one), height = CVPixelBufferGetHeight(one)
        guard width == CVPixelBufferGetWidth(other), height == CVPixelBufferGetHeight(other) else { return false }
        CVPixelBufferLockBaseAddress(one, .readOnly)
        CVPixelBufferLockBaseAddress(other, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(one, .readOnly)
            CVPixelBufferUnlockBaseAddress(other, .readOnly)
        }
        guard let a = CVPixelBufferGetBaseAddress(one), let b = CVPixelBufferGetBaseAddress(other) else { return false }
        let aRow = CVPixelBufferGetBytesPerRow(one), bRow = CVPixelBufferGetBytesPerRow(other)
        return (0..<height).allSatisfy { memcmp(a.advanced(by: $0 * aRow), b.advanced(by: $0 * bRow), width * 4) == 0 }
    }

    private static func unpack(_ sample: CMSampleBuffer) -> (Data, [Data], Bool)? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var length = 0, pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer else { return nil }
        let data = Data(bytes: pointer, count: length)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let keyFrame = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        var sets: [Data] = []
        if keyFrame, let format = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                               parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            for index in 0..<count {
                var set: UnsafePointer<UInt8>?, size = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &set,
                                                                      parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                      nalUnitHeaderLengthOut: nil) == noErr, let set {
                    sets.append(Data(bytes: set, count: size))
                }
            }
        }
        return (data, sets, keyFrame)
    }
}

public struct SurfaceEncoderError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "The video encoder failed (\(status))." }
}

/// Turns packets back into sample buffers a display layer or decompression session can take.
public enum SurfaceSamples {
    public static func format(_ packet: SurfacePacket) -> CMVideoFormatDescription? {
        guard packet.parameterSets.count >= 2 else { return nil }
        var format: CMVideoFormatDescription?
        let sets = packet.parameterSets.map { [UInt8]($0) }
        let status = sets[0].withUnsafeBufferPointer { sps in
            sets[1].withUnsafeBufferPointer { pps in
                let pointers = [sps.baseAddress!, pps.baseAddress!]
                let sizes = [sets[0].count, sets[1].count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                                                                           parameterSetSizes: sizes, nalUnitHeaderLength: 4,
                                                                           formatDescriptionOut: &format)
            }
        }
        return status == noErr ? format : nil
    }

    public static func sample(_ packet: SurfacePacket, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        let length = packet.sample.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              packet.sample.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                                                            dataLength: length) }) == noErr else { return nil }
        var sample: CMSampleBuffer?
        var sizes = [length]
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0,
                                        sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}
