import AppKit

/// Standalone AppKit checks: no guest, network, user library or window.
@main struct PreviewSnapshotTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await run()
            exit(0)
        }
        app.run()
    }

    /// A 1024x768 desktop frame: dark wallpaper plus whatever `draw` adds.
    static func frame(_ draw: (CGContext) -> Void = { _ in }) -> CGImage {
        let context = CGContext(data: nil, width: 1024, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))
        draw(context)
        return context.makeImage()!
    }

    @MainActor static func run() async {
        func require(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            print("PASS: \(message)")
        }
        func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
        let content = frame { context in
            context.setFillColor(CGColor(red: 0.07, green: 0.23, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 768))
            context.setFillColor(CGColor(red: 0.9, green: 0.72, blue: 0.29, alpha: 1))
            context.fill(CGRect(x: 512, y: 0, width: 512, height: 768))
        }

        var began = now()
        let delayed = await ComputerPreviewSnapshot.capture(timeout: 5) { now() - began < 0.75 ? frame() : content }
        require(delayed != nil && now() - began >= 0.75, "wait for the desktop to draw useful content")
        if let delayed {
            require(delayed.starts(with: [137, 80, 78, 71]), "text/UI snapshots prefer lossless PNG")
            let bitmap = NSBitmapImageRep(data: delayed)!
            require(bitmap.pixelsWide == 1024 && bitmap.pixelsHigh == 768, "a frame keeps its own size")
        }

        began = now()
        let blank = await ComputerPreviewSnapshot.capture(timeout: 1) { frame() }
        require(blank == nil && now() - began < 1.5, "an empty desktop returns the icon fallback within its timeout")

        let spinner = await ComputerPreviewSnapshot.capture(timeout: 1) {
            frame { context in
                context.setStrokeColor(CGColor(gray: 1, alpha: 1))
                context.stroke(CGRect(x: 40, y: 0, width: 944, height: 720))
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 505, y: 380, width: 6, height: 6))
            }
        }
        require(spinner == nil, "a window border, dark wallpaper and tiny spinner are not ready content")

        let unavailable = await ComputerPreviewSnapshot.capture(timeout: 1) { throw CocoaError(.fileReadUnknown) }
        require(unavailable == nil, "an unreachable desktop returns the icon fallback")

        let terminal = await ComputerPreviewSnapshot.capture(timeout: 3) {
            frame { context in
                let text = NSAttributedString(string: "agent@computer /workspace $ ls\ndocuments  projects  hello.txt\nagent@computer /workspace $",
                                              attributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                                                           .foregroundColor: NSColor.white])
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                text.draw(in: NSRect(x: 60, y: 400, width: 900, height: 200))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        require(terminal != nil, "real terminal text on a dark desktop remains useful")
        if let terminal {
            require(terminal.starts(with: [137, 80, 78, 71]), "desktop terminal text is stored without JPEG artifacts")
        }

        // Deterministic incompressible content exercises the byte cap and JPEG fallback.
        let noise = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var seed: UInt32 = 7
        for y in 0..<noise.pixelsHigh { for x in 0..<noise.pixelsWide {
            let pixel = noise.bitmapData! + y * noise.bytesPerRow + x * 4
            for channel in 0..<3 { seed = seed &* 1664525 &+ 1013904223; pixel[channel] = UInt8(truncatingIfNeeded: seed >> 24) }
            pixel[3] = 255
        } }
        let noiseImage = NSImage(size: NSSize(width: 1600, height: 1200)); noiseImage.addRepresentation(noise)
        let encodedNoise = ComputerPreviewSnapshot.encode(noiseImage)
        require(encodedNoise != nil && encodedNoise!.count <= 512_000, "detailed images stay under the existing wire limit")
        require(encodedNoise!.starts(with: [255, 216]), "oversized PNG uses bounded high-quality JPEG fallback")
        let small = NSImage(size: NSSize(width: 200, height: 150))
        small.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 200, height: 150).fill(); small.unlockFocus()
        let smallSource = NSBitmapImageRep(data: small.tiffRepresentation!)!
        let smallEncoded = NSBitmapImageRep(data: ComputerPreviewSnapshot.encode(small)!)!
        require(smallEncoded.pixelsWide == smallSource.pixelsWide, "small images are never artificially upscaled")
        if CommandLine.arguments.count == 2, let observed = NSImage(contentsOfFile: CommandLine.arguments[1]) {
            require(!ComputerPreviewSnapshot.isUseful(observed), "reject the loading frame captured from the real desktop")
        }

        var valid = true
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); valid = false }
        let removed = await ComputerPreviewSnapshot.capture(timeout: 3, valid: { valid }) { frame() }
        require(removed == nil, "computer removal cancels pending capture")

        let task = Task { @MainActor in await ComputerPreviewSnapshot.capture(timeout: 5) { frame() } }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        require(await task.value == nil, "cancelled request does not produce a snapshot")

        print("SNAPSHOT TESTS PASSED")
    }
}
