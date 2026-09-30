import AppKit
import AppletBridge
import AppletCore
import WebKit

/// Explicit signed-app regression fixture with its own runtime, data and socket.
/// Never connects to, closes or replaces the user's existing sessions.
@MainActor enum AppletRenderingTest {
  static func run() async throws {
    setbuf(stdout, nil)
    // Inside Applet's storage, the only place a Swift noodlet may be built.
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("NoodleApplet/Rendering-\(UUID())")
    let suite = "RenderingTest.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let library = AppletLibrary(root: root, defaults: defaults, installExamples: false, watchChanges: false)
    let runtime = AppletRuntime(library: library, defaults: defaults)
    let socket = try AppletConnection.socketURL().deletingLastPathComponent()
      .appendingPathComponent("t\(UUID().uuidString.prefix(6)).sock")
    let server = try AppletConnectionServer(socket: socket, team: AppletConnection.signingTeam()) { request, identity in
      await runtime.handle(request, identity: identity)
    }
    func clearWebsiteData() async {
      runtime.shutdown()
      for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("store.") {
        if let string = value as? String, let id = UUID(uuidString: string) {
          try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
      }
    }
    defer {
      withExtendedLifetime(server) {}
      runtime.shutdown()
      try? FileManager.default.removeItem(at: root)
      defaults.removePersistentDomain(forName: suite)
    }
    func require(_ condition: Bool, _ message: String) throws {
      if !condition { throw AppletError(message) }
    }
    let cli = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/noodlet")
    func call(_ args: [String], succeeds: Bool = true) async throws -> AppletResponse {
      let response = try await Task.detached {
        let process = Process(), pipe = Pipe()
        process.executableURL = cli
        process.arguments = args + ["--socket", socket.path]
        process.currentDirectoryURL = root
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let response = try JSONDecoder().decode(AppletResponse.self, from: data)
        if succeeds { return try response.checked() }
        guard process.terminationStatus == 1, response.error != nil else { throw AppletError("Expected CLI rejection: \(args)") }
        return response
      }.value
      return response
    }
    func value(_ args: [String]) async throws -> [String: Any] {
      let response = try await call(args)
      return try JSONSerialization.jsonObject(with: Data((response.value ?? "{}").utf8)) as? [String: Any] ?? [:]
    }
    /// Watches a session as a paired device does, once its first picture has arrived.
    func watch(_ session: UUID) async throws -> SurfaceSocket {
      let (near, far) = try {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw AppletError("No socket pair") }
        return (SurfaceSocket(fd: fds[0], held: true), SurfaceSocket(fd: fds[1]))
      }()
      let streamed = await runtime.handle(
        AppletRequest(.surfaceStream, sessionID: session), identity: AppletBuildIdentity.current.noodleID, surface: near)
      near.start(with: try JSONEncoder().encode(streamed))
      try require(streamed.error == nil, "Live view refused: \(streamed.error ?? "")")
      let frame = await withTaskGroup(of: SurfacePacket?.self) { group in
        group.addTask {
          for await data in far.frames { if let packet = SurfacePacket.decode(data)?.first { return packet } }
          return nil
        }
        group.addTask { try? await Task.sleep(for: .seconds(5)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
      }
      try require(frame?.keyFrame == true, "A background noodlet sent no live view within 5 seconds")
      return far
    }
    do {
    let source = library.documents.appendingPathComponent("Animation.\(AppletBuildIdentity.current.fileExtension)")
    _ = try NoodletPackage.install([
      "noodlet.json": try JSONEncoder().encode(NoodletManifest(title: "Animation regression")),
      "index.html": Data("""
        <!doctype html><title>RAF regression</title>
        <style>body{margin:0;background:black}canvas{display:block}</style>
        <canvas id="canvas" width="160" height="120"></canvas><canvas id="gpu" width="160" height="120"></canvas>
        <script>
        window.framesSeen=0;window.times=[];window.paused=false;
        window.ctx=canvas.getContext('2d');window.gl=gpu.getContext('webgl2');
        function draw(t){
          if(!document.hidden && !paused){framesSeen++;times.push([t,performance.now()]);
            ctx.fillStyle='#ff0000';ctx.fillRect(0,0,160,120);
            gl.clearColor(0,1,0,1);gl.clear(gl.COLOR_BUFFER_BIT);}
          requestAnimationFrame(draw);
        }
        requestAnimationFrame(draw);
        </script>
        """.utf8)
    ], to: source)
    library.scan()
    let packageID = try library.linkID(for: NoodletPackage(url: source)).uuidString
    let target = ["--id", packageID]
    for mode in ["background", "headless"] {
      let open = try await call(["open", "--mode", mode] + target)
      let exact = target + ["--session", open.sessionID!.uuidString]
      try require(open.mode == mode && open.testClock == false, "Incorrect normal mode")
      try await Task.sleep(for: .milliseconds(150))
      let observed = try await value(["eval", "--text", "return {hidden:document.hidden,frames:framesSeen};"] + exact)
      try require(observed["hidden"] as? Bool == true, "Normal hidden visibility was overridden")
      let status = try await call(["status"] + target)
      try require(status.sessionID == open.sessionID && status.rendering?.nativeVisibilityState == "hidden", "Normal link selection/diagnostics failed")
      _ = try await call(["step"] + exact, succeeds: false)
      _ = try await call(["close"] + exact)
    }
    // A person watching from another device opens the noodlet in the background, never seen on this Mac.
    let watched = library.documents.appendingPathComponent("Watched.\(AppletBuildIdentity.current.fileExtension)")
    _ = try NoodletPackage.install([
      "noodlet.json": try JSONEncoder().encode(NoodletManifest(title: "Live view regression")),
      "index.html": Data("""
        <!doctype html><title>Live view</title>
        <style>body{margin:0;background:black}div,canvas{display:block;width:160px;height:120px}</style>
        <div style="background:#ff0000"></div><canvas id="c" width="160" height="120"></canvas>
        <script>requestAnimationFrame(()=>{const x=c.getContext('2d');x.fillStyle='#00ff00';x.fillRect(0,0,160,120);});
        window.ticks=0;(function tick(){ticks++;requestAnimationFrame(tick);})();</script>
        """.utf8)
    ], to: watched)
    library.scan()
    let watchedTarget = ["--id", try library.linkID(for: NoodletPackage(url: watched)).uuidString]
    // A runner with nothing else in front activates the app at launch, so only a change counts.
    let wasActive = NSApp.isActive
    let cold = try await call(["open", "--mode", "background"] + watchedTarget)
    guard let session = runtime.sessions[cold.sessionID!], let web = session.web else { throw AppletError("Background session missing") }
    let far = try await watch(cold.sessionID!)
    try await Task.sleep(for: .milliseconds(300))
    // What the live view captures, as it captures it.
    let picture = try await session.snapshot()
    let captured = NSBitmapImageRep(data: picture.tiffRepresentation!)!
    func pixels(_ y: ClosedRange<Double>, _ match: (NSColor) -> Bool) -> Int {
      var count = 0
      for py in stride(from: 0, to: captured.pixelsHigh, by: 2) {
        let point = Double(py) * picture.size.height / Double(captured.pixelsHigh)
        guard y.contains(point) else { continue }
        for px in stride(from: 0, to: min(captured.pixelsWide, Int(160 * Double(captured.pixelsWide) / picture.size.width)), by: 2) {
          if let color = captured.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB), match(color) { count += 1 }
        }
      }
      return count
    }
    let redShown = pixels(0...119) { $0.redComponent > 0.8 && $0.greenComponent < 0.2 }
    let greenShown = pixels(120...239) { $0.greenComponent > 0.8 && $0.redComponent < 0.2 }
    print("INFO watched background capture: static red \(redShown), animation-frame green \(greenShown)")
    try require(redShown > 500, "The live view of a background noodlet is blank")
    try require(greenShown > 500, "The live view of a background noodlet lacks what it drew in an animation frame")
    // A game draws every animation frame, so the page must keep getting them while watched.
    func ticks() async throws -> Int { Int(try await web.evaluate("return ticks")) ?? 0 }
    let ticksBefore = try await ticks()
    try await Task.sleep(for: .milliseconds(500))
    let ticksAfter = try await ticks()
    let visibility = try await web.evaluate("return document.visibilityState")
    print("INFO watched background animation: \(ticksAfter - ticksBefore) frames in 500 ms, visibility \(visibility)")
    try require(ticksAfter - ticksBefore >= 5, "A watched background noodlet stopped getting animation frames")
    try require(visibility == "\"visible\"", "A watched background noodlet is hidden from its own page")
    try require(web.window.alphaValue == 0, "A watched background noodlet became visible on this Mac")
    try require(web.window.ignoresMouseEvents, "A watched background noodlet takes clicks on this Mac")
    try require(wasActive || !NSApp.isActive, "A watched background noodlet took focus on this Mac")
    far.close()
    try await Task.sleep(for: .milliseconds(500))
    try require(!web.window.isVisible && web.window.alphaValue == 1, "The noodlet stayed on screen after the live view ended")
    try require(try await web.evaluate("return document.visibilityState") == "\"hidden\"", "The noodlet still counts as seen after the live view ended")
    _ = try await call(["close"] + watchedTarget)
    print("PASS live view: a noodlet opened only in the background draws for its viewer and stays out of sight on this Mac")
    // Watched after a person closed its window, as the phone does: the Hub opens it again in the background.
    // Only Noodle, for the person, brings a noodlet to the foreground.
    var foreground = AppletRequest(.open)
    foreground.noodletID = try library.linkID(for: NoodletPackage(url: watched))
    foreground.mode = "foreground"
    let shown = try await runtime.handle(foreground, identity: AppletBuildIdentity.current.noodleID).checked()
    guard let shownWeb = runtime.sessions[shown.sessionID!]?.web else { throw AppletError("Foreground session missing") }
    shownWeb.window.performClose(nil)
    try await Task.sleep(for: .milliseconds(300))
    try require(runtime.sessions[shown.sessionID!]?.state == "stopped", "Closing the window left the noodlet running")
    let reopened = try await call(["open", "--mode", "background"] + watchedTarget)
    guard let reopenedWeb = runtime.sessions[reopened.sessionID!]?.web else { throw AppletError("Reopened session missing") }
    let reopenedView = try await watch(reopened.sessionID!)
    try await Task.sleep(for: .milliseconds(300))
    let reopenedTicks = Int(try await reopenedWeb.evaluate("return ticks")) ?? 0
    try await Task.sleep(for: .milliseconds(500))
    let reopenedMoved = (Int(try await reopenedWeb.evaluate("return ticks")) ?? 0) - reopenedTicks
    let reopenedVisibility = try await reopenedWeb.evaluate("return document.visibilityState")
    print("INFO closed then watched: \(reopenedMoved) frames in 500 ms, visibility \(reopenedVisibility)")
    try require(reopenedMoved >= 5 && reopenedVisibility == "\"visible\"", "A noodlet watched after its window was closed does not animate")
    reopenedView.close()
    _ = try await call(["close"] + watchedTarget)
    print("PASS live view: a noodlet whose window was closed animates for its viewer")
    // A recording is watched too: a hidden page gets about one frame a second, and so did its video.
    let recorded = try await call(["open", "--mode", "background"] + watchedTarget)
    guard let recordedWeb = runtime.sessions[recorded.sessionID!]?.web else { throw AppletError("Recorded session missing") }
    let recordedTarget = watchedTarget + ["--session", recorded.sessionID!.uuidString]
    _ = try await call(["record", "start", "--duration", "5"] + recordedTarget)
    try await Task.sleep(for: .milliseconds(300))
    let recordedTicks = Int(try await recordedWeb.evaluate("return ticks")) ?? 0
    try await Task.sleep(for: .milliseconds(500))
    let recordedMoved = (Int(try await recordedWeb.evaluate("return ticks")) ?? 0) - recordedTicks
    let recordedVisibility = try await recordedWeb.evaluate("return document.visibilityState")
    print("INFO recorded background: \(recordedMoved) frames in 500 ms, visibility \(recordedVisibility)")
    try require(recordedMoved >= 5 && recordedVisibility == "\"visible\"", "A background noodlet does not animate while recorded")
    try require(recordedWeb.window.alphaValue == 0, "A recorded background noodlet became visible on this Mac")
    _ = try await call(["record", "stop", "--output", root.appendingPathComponent("recorded.mp4").path] + recordedTarget)
    try await Task.sleep(for: .milliseconds(500))
    try require(!recordedWeb.window.isVisible && recordedWeb.window.alphaValue == 1, "The noodlet stayed on screen after its recording ended")
    _ = try await call(["close"] + watchedTarget)
    print("PASS recording: a noodlet opened only in the background animates while recorded")
    // A Swift noodlet draws itself; its picture must keep changing while only another device watches.
    let native = library.documents.appendingPathComponent("NativeWatched.\(AppletBuildIdentity.current.fileExtension)")
    _ = try NoodletPackage.install([
      "noodlet.json": try JSONEncoder().encode(NoodletManifest(title: "Native live view regression", runtime: "swift", entry: "Main.swift")),
      "Main.swift": Data("""
        import SwiftUI
        struct Noodlet: View {
          var body: some View {
            TimelineView(.animation) { context in
              let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
              Color(red: phase, green: 1 - phase, blue: 0).frame(width: 160, height: 120)
            }
          }
        }
        """.utf8),
    ], to: native)
    library.scan()
    let nativeTarget = ["--id", try library.linkID(for: NoodletPackage(url: native)).uuidString]
    let nativeOpen: AppletResponse
    do {
      nativeOpen = try await call(["open", "--mode", "background"] + nativeTarget)
    } catch {
      // The compiler's diagnostics are in the session's log, gone with the fixture.
      print(try? await call(["logs"] + nativeTarget).text ?? "", terminator: "")
      throw error
    }
    guard let nativeRunner = runtime.sessions[nativeOpen.sessionID!]?.native else { throw AppletError("Native session missing") }
    let nativeView = try await watch(nativeOpen.sessionID!)
    func centre() async throws -> [UInt8] {
      let image = try await nativeRunner.liveFrame()
      let bitmap = NSBitmapImageRep(cgImage: image)
      guard let colour = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return [] }
      return [colour.redComponent, colour.greenComponent].map { UInt8($0 * 255) }
    }
    var seen = Set<[UInt8]>()
    for _ in 0..<6 {
      seen.insert(try await centre())
      try await Task.sleep(for: .milliseconds(150))
    }
    print("INFO native watched background: \(seen.count) distinct pictures in 6 frames")
    try require(seen.count >= 3, "A watched background Swift noodlet stopped animating")
    nativeView.close()
    _ = try await call(["close"] + nativeTarget)
    print("PASS live view: a Swift noodlet opened only in the background animates for its viewer")
    // SceneKit and SpriteKit draw on the GPU, which the view's own capture leaves out. SceneKit plays
    // only while the display refreshes its window, so not while it is hidden; neither plays while the
    // display is asleep, as when the Mac is locked. Each noodlet shows the framework's view on the
    // left and SwiftUI's on the right, each a blue scene with a red box an action keeps moving and a
    // green ball physics keeps bouncing.
    // A SceneKit scene also has a corner that turns magenta when its view drew it, and when another
    // renderer did, yellow if the window was in view and cyan if not, so a frame shows how it was taken.
    // Checks gather their failures, so one run shows them all.
    var sceneFailures: [String] = []
    func check(_ condition: Bool, _ message: String) {
      if !condition { sceneFailures.append(message); print("FAIL \(message)") }
    }
    /// Installs a Swift noodlet and opens it as a viewer's device or the person at this Mac would.
    func openSwift(_ name: String, _ source: String, foreground: Bool = false) async throws -> (target: [String], session: AppletSession, runner: NativeRunner) {
      let url = library.documents.appendingPathComponent("\(name).\(AppletBuildIdentity.current.fileExtension)")
      _ = try NoodletPackage.install([
        "noodlet.json": try JSONEncoder().encode(NoodletManifest(title: name, runtime: "swift", entry: "Main.swift")),
        "Main.swift": Data(source.utf8),
      ], to: url)
      library.scan()
      let id = try library.linkID(for: NoodletPackage(url: url))
      let target = ["--id", id.uuidString]
      let opened: AppletResponse
      do {
        if foreground {
          var request = AppletRequest(.open)
          request.noodletID = id
          request.mode = "foreground"
          opened = try await runtime.handle(request, identity: AppletBuildIdentity.current.noodleID).checked()
        } else {
          opened = try await call(["open", "--mode", "background"] + target)
        }
      } catch {
        print(try? await call(["logs"] + target).text ?? "", terminator: "")
        throw error
      }
      guard let session = runtime.sessions[opened.sessionID!], let runner = session.native else { throw AppletError("\(name) session missing") }
      return (target, session, runner)
    }
    /// Per half of a live frame: how many pixels show the scene's blue, where its red box is across
    /// and its green ball up, in pixels, or -1 when not shown, and who drew it: the view itself, or
    /// another renderer while the window was in view or out of it.
    enum Drawn { case byView, forShownView, forHiddenView, unmarked }
    typealias Side = (blue: Int, box: Int, ball: Int, drawn: Drawn)
    func halves(_ runner: NativeRunner) async throws -> (width: Int, height: Int, sides: [Side]) {
      let bitmap = NSBitmapImageRep(cgImage: try await runner.liveFrame())
      let half = bitmap.pixelsWide / 2
      return (bitmap.pixelsWide, bitmap.pixelsHigh, (0..<2).map { side in
        var blue = 0, redX = 0, red = 0, greenY = 0, green = 0, magenta = 0, yellow = 0, cyan = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
          for x in stride(from: side * half, to: (side + 1) * half, by: 4) {
            // As drawn: the display's colour space would move magenta's green above the threshold.
            guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
            let (r, g, b) = (colour.redComponent > 0.8, colour.greenComponent > 0.8, colour.blueComponent > 0.8)
            let (noR, noG, noB) = (colour.redComponent < 0.2, colour.greenComponent < 0.2, colour.blueComponent < 0.2)
            if b && noR && noG { blue += 1 }
            if r && noG && noB { red += 1; redX += x - side * half }
            if g && noR && noB { green += 1; greenY += y }
            if r && b && noG { magenta += 1 }
            if r && g && noB { yellow += 1 }
            if g && b && noR { cyan += 1 }
          }
        }
        let drawn: Drawn = [magenta, yellow, cyan].max() == 0 ? .unmarked
          : magenta >= max(yellow, cyan) ? .byView : yellow >= cyan ? .forShownView : .forHiddenView
        return (blue, red == 0 ? -1 : redX / red, green == 0 ? -1 : greenY / green, drawn)
      })
    }
    /// Plays a noodlet, out of sight or in front, the framework's view left and SwiftUI's right.
    /// While the display is asleep, as when the Mac is locked, nothing on it is refreshed and no
    /// view draws itself: a run shows which it had.
    func plays(_ name: String, _ source: String, views: [String], foreground: Bool, marked: Bool) async throws {
      let (target, session, runner) = try await openSwift(name, source, foreground: foreground)
      let viewer = try await watch(session.id)
      try await Task.sleep(for: .milliseconds(300))
      let displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
      var frames: [[Side]] = []
      for _ in 0..<6 {
        frames.append(try await halves(runner).sides)
        try await Task.sleep(for: .milliseconds(150))
      }
      let how = (foreground ? "foreground" : "background") + (displayAsleep ? " with the display asleep" : "")
      for (side, view) in views.enumerated() {
        let blue = frames.map { $0[side].blue }.min() ?? 0
        let places = Set(frames.map { $0[side].box / 8 }.filter { $0 >= 0 }).count
        let heights = Set(frames.map { $0[side].ball / 8 }.filter { $0 >= 0 }).count
        print("INFO watched \(how) \(view): at least \(blue) scene pixels, box in \(places) places and ball at \(heights) heights in 6 frames")
        check(blue > 500, "The live view of a \(how) \(view) lacks its scene")
        check(places >= 3, "A watched \(how) \(view) stops its actions")
        check(heights >= 3, "A watched \(how) \(view) stops its physics")
        guard marked else { continue }
        // A view the display refreshes draws itself, while its window is in view; any other is drawn
        // for it. Someone at this Mac may cover the window, so only a frame taken the wrong way counts.
        let drawn = { (kind: Drawn) in frames.filter { $0[side].drawn == kind }.count }
        let (byView, forShown, forHidden) = (drawn(.byView), drawn(.forShownView), drawn(.forHiddenView))
        print("INFO watched \(how) \(view): of 6 frames \(byView) drawn by the view, \(forShown) for it in view, \(forHidden) for it out of view")
        check(byView + forShown + forHidden == 6, "The live view of a \(how) \(view) does not show who drew it")
        if foreground && !displayAsleep {
          check(forShown == 0, "A watched \(how) \(view) in view is drawn for it in \(forShown) of 6 frames instead of by itself")
          if byView == 0 { print("INFO the \(view) window was out of view throughout, so it never drew itself") }
        } else {
          check(byView == 0, "A watched \(how) \(view) that is not refreshed is drawn by the view itself in \(byView) of 6 frames")
        }
      }
      viewer.close()
      _ = try await call(["close"] + target)
    }
    let sceneKit = """
      import SwiftUI
      import SceneKit
      final class Marking: NSObject, SCNSceneRendererDelegate {
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
          let marker = renderer.scene?.rootNode.childNode(withName: "marker", recursively: false)
          // The view draws with its own settings, jittering on; a renderer drawing for it has its own,
          // and draws on the main thread, where it can tell whether the window is in view.
          let byView = (renderer as? SCNRenderer)?.isJitteringEnabled ?? true
          let shown = !byView && Thread.isMainThread && MainActor.assumeIsolated {
            NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) }
          }
          marker?.geometry?.firstMaterial?.diffuse.contents = byView ? NSColor.magenta : shown ? NSColor.yellow : NSColor.cyan
        }
      }
      let marking = Marking()
      func playing() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.blue
        let marker = SCNNode(geometry: SCNBox(width: 0.6, height: 0.6, length: 0.6, chamferRadius: 0))
        marker.name = "marker"
        marker.geometry?.firstMaterial?.lightingModel = .constant
        marker.geometry?.firstMaterial?.diffuse.contents = NSColor.black
        marker.position = SCNVector3(x: -1.8, y: 2.8, z: 0)
        scene.rootNode.addChildNode(marker)
        let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        box.geometry?.firstMaterial?.lightingModel = .constant
        box.geometry?.firstMaterial?.diffuse.contents = NSColor.red
        box.position.x = -2
        box.runAction(.repeatForever(.sequence([.moveBy(x: 4, y: 0, z: 0, duration: 1), .moveBy(x: -4, y: 0, z: 0, duration: 1)])))
        scene.rootNode.addChildNode(box)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position.z = 6
        scene.rootNode.addChildNode(camera)
        let ball = SCNNode(geometry: SCNSphere(radius: 0.4))
        ball.geometry?.firstMaterial?.lightingModel = .constant
        ball.geometry?.firstMaterial?.diffuse.contents = NSColor.green
        ball.position.y = 2
        ball.physicsBody = .dynamic()
        ball.physicsBody?.restitution = 1
        ball.physicsBody?.damping = 0
        scene.rootNode.addChildNode(ball)
        let floor = SCNNode(geometry: SCNBox(width: 10, height: 0.2, length: 10, chamferRadius: 0))
        floor.position.y = -2
        floor.physicsBody = .static()
        floor.physicsBody?.restitution = 1
        scene.rootNode.addChildNode(floor)
        return scene
      }
      struct Game: NSViewRepresentable {
        func makeNSView(context: Context) -> SCNView {
          let view = SCNView()
          view.scene = playing()
          view.delegate = marking
          view.isJitteringEnabled = true
          view.isPlaying = true
          return view
        }
        func updateNSView(_ view: SCNView, context: Context) {}
      }
      struct Noodlet: View {
        let scene = playing()
        var body: some View {
          HStack(spacing: 0) {
            Game()
            SceneView(scene: scene, options: [.jitteringEnabled], delegate: marking)
          }
        }
      }
      """
    let spriteKit = """
      import SwiftUI
      import SpriteKit
      func playing() -> SKScene {
        let scene = SKScene(size: CGSize(width: 400, height: 400))
        scene.scaleMode = .fill
        scene.backgroundColor = .blue
        scene.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: 400, height: 400))
        let box = SKSpriteNode(color: .red, size: CGSize(width: 50, height: 50))
        box.position = CGPoint(x: 60, y: 60)
        box.run(SKAction.repeatForever(SKAction.sequence([SKAction.moveBy(x: 280, y: 0, duration: 1), SKAction.moveBy(x: -280, y: 0, duration: 1)])))
        scene.addChild(box)
        let ball = SKShapeNode(circleOfRadius: 25)
        ball.fillColor = .green
        ball.strokeColor = .green
        ball.position = CGPoint(x: 300, y: 340)
        ball.physicsBody = SKPhysicsBody(circleOfRadius: 25)
        ball.physicsBody?.restitution = 1
        ball.physicsBody?.linearDamping = 0
        ball.physicsBody?.friction = 0
        scene.addChild(ball)
        return scene
      }
      struct Game: NSViewRepresentable {
        func makeNSView(context: Context) -> SKView {
          let view = SKView()
          view.presentScene(playing())
          return view
        }
        func updateNSView(_ view: SKView, context: Context) {}
      }
      struct Noodlet: View {
        let scene = playing()
        var body: some View {
          HStack(spacing: 0) {
            Game()
            SpriteView(scene: scene)
          }
        }
      }
      """
    for foreground in [false, true] {
      try await plays("SceneKit live view", sceneKit, views: ["SCNView", "SceneView"], foreground: foreground, marked: true)
      try await plays("SpriteKit live view", spriteKit, views: ["SKView", "SpriteView"], foreground: foreground, marked: false)
    }
    // Keys a viewer plays reach a game however it reads them. Each press of an arrow moves the red
    // box one unit its way, so a key delivered twice moves it twice as far. Several presses, as each
    // may meet the game's own handling differently.
    let keyedScene = """
      import SwiftUI
      import SceneKit
      let box: SCNNode = {
        let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        box.geometry?.firstMaterial?.lightingModel = .constant
        box.geometry?.firstMaterial?.diffuse.contents = NSColor.red
        return box
      }()
      let scene: SCNScene = {
        let scene = SCNScene()
        scene.background.contents = NSColor.blue
        scene.rootNode.addChildNode(box)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position.z = 6
        scene.rootNode.addChildNode(camera)
        return scene
      }()
      func steer(_ key: UInt16) { box.position.x += key == 123 ? -1 : key == 124 ? 1 : 0 }

      """
    let keyed = [
      ("SCNView reading keyDown", """
        final class KeyView: SCNView {
          override var acceptsFirstResponder: Bool { true }
          override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
          override func keyDown(with event: NSEvent) { steer(event.keyCode) }
          override func keyUp(with event: NSEvent) {}
        }
        struct Game: NSViewRepresentable {
          func makeNSView(context: Context) -> SCNView { let view = KeyView(); view.scene = scene; return view }
          func updateNSView(_ view: SCNView, context: Context) {}
        }
        struct Noodlet: View {
          var body: some View { HStack(spacing: 0) { Game(); Game() } }
        }
        """),
      ("SceneView reading onKeyPress", """
        struct Noodlet: View {
          @FocusState var focused: Bool
          var body: some View {
            HStack(spacing: 0) {
              SceneView(scene: scene).focusable().focused($focused)
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
                  steer(press.key == .leftArrow ? 123 : 124)
                  return .handled
                }
              SceneView(scene: scene)
            }
            .onAppear { focused = true }
          }
        }
        """),
      ("SCNView with a key monitor", """
        var monitor: Any?
        struct Game: NSViewRepresentable {
          func makeNSView(context: Context) -> SCNView {
            if monitor == nil {
              monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                steer(event.keyCode)
                return event
              }
            }
            let view = SCNView()
            view.scene = scene
            return view
          }
          func updateNSView(_ view: SCNView, context: Context) {}
        }
        struct Noodlet: View {
          var body: some View { HStack(spacing: 0) { Game(); Game() } }
        }
        """),
    ]
    for (index, (game, body)) in keyed.enumerated() {
      let (target, session, runner) = try await openSwift("Keys \(index)", keyedScene + body)
      let viewer = try await watch(session.id)
      try await Task.sleep(for: .milliseconds(300))
      var last = try await halves(runner), moves: [Double] = []
      for key in ["ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight"] {
        for pressed in [true, false] { try await runtime.deliver(.hold(key: key, pressed: pressed), to: session) }
        try await Task.sleep(for: .milliseconds(300))
        let now = try await halves(runner)
        // A unit at the box's depth, in pixels: the camera sees 2·6·tan 30° units top to bottom.
        let unit = Double(now.height) / (12 * tan(Double.pi / 6))
        moves.append(last.sides[0].box < 0 || now.sides[0].box < 0 ? 0 : Double(now.sides[0].box - last.sides[0].box) / unit)
        last = now
      }
      let moved = moves.map { String(format: "%+.2f", $0) }.joined(separator: " ")
      print("INFO played left, right, left, right, \(game): box moved \(moved) units")
      check(zip(moves, [-1.0, 1, -1, 1]).allSatisfy { abs($0 - $1) < 0.3 }, "Played keys move a watched \(game) \(moved) units, not one each way")
      viewer.close()
      _ = try await call(["close"] + target)
    }
    try require(sceneFailures.isEmpty, sceneFailures.joined(separator: "; "))
    print("PASS live view: SceneKit and SpriteKit in Swift noodlets draw, play and take keys for their viewer, in the background and in front")
    let open = try await call(["open", "--mode", "headless", "--test-clock"] + target)
    let exact = target + ["--session", open.sessionID!.uuidString]
    try require(open.testClock == true && open.dataScope == "test", "Clock did not use test data")
    let selected = try await call(["status"] + target)
    try require(selected.sessionID == open.sessionID, "Historical session displaced new headless open")
    let initial = try await value(["eval", "--text", "return {frames:framesSeen,hidden:document.hidden,gl:!!gl};"] + exact)
    try require(initial["frames"] as? Int == 0 && initial["hidden"] as? Bool == false && initial["gl"] as? Bool == true, "Synthetic setup failed")
    _ = try await call(["step", "--frames", "60"] + exact)
    let frames = try await value(["eval", "--text", "return {frames:framesSeen,time:performance.now(),aligned:times.every(v=>v[0]===v[1])};"] + exact)
    try require(frames["frames"] as? Int == 60 && frames["aligned"] as? Bool == true, "RAF delivery/timestamps failed")
    try require(abs((frames["time"] as? Double ?? 0) - 1000) < 0.001, "Clock did not advance one second")
    let capture = root.appendingPathComponent("stepped.png")
    let shot = try await call(["screenshot", "--output", capture.path] + exact)
    try require(shot.rendering?.synthetic == true && shot.rendering?.animationFrameCount == 60, "Capture lost synthetic diagnostics")
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: capture))!
    var red = 0, green = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.redComponent > 0.8 && color.greenComponent < 0.2 { red += 1 }
        if color.greenComponent > 0.8 && color.redComponent < 0.2 { green += 1 }
      }
    }
    try require(red > 500 && green > 500, "Captured image lacks rendered Canvas/WebGL pixels: \(red)/\(green)")
    let afterShot = try await value(["eval", "--text", "return {frames:framesSeen};"] + exact)
    try require(afterShot["frames"] as? Int == 60, "Capture unexpectedly advanced test clock")
    _ = try await call(["eval", "--text", "paused=true;window.called=[];requestAnimationFrame(()=>{called.push('a');cancelAnimationFrame(cancelled);requestAnimationFrame(()=>called.push('next'));});let cancelled=requestAnimationFrame(()=>called.push('cancelled'));requestAnimationFrame(()=>{throw Error('fixture callback failure')});requestAnimationFrame(()=>called.push('sibling'));await noodle.storage.set('clock-marker',123);"] + exact)
    _ = try await call(["step", "--frames", "2"] + exact)
    let callbacks = try await value(["eval", "--text", "return {called,frames:framesSeen};"] + exact)
    try require(callbacks["called"] as? [String] == ["a", "sibling", "next"] && callbacks["frames"] as? Int == 60, "Callback cancellation, exceptions or game pause failed")
    _ = try await call(["open", "--mode", "background"] + target, succeeds: false)
    _ = try await call(["hide"] + exact)
    let restarted = try await call(["restart"] + exact)
    try require(restarted.testClock == true && restarted.sessionID != open.sessionID, "Restart lost clock or identity")
    let closed = try await call(["close"] + target)
    try require(closed.sessionID == restarted.sessionID, "Close targeted historical session")
    let latest = try await call(["status"] + target)
    try require(latest.sessionID == restarted.sessionID && latest.state == "stopped", "Stopped history selected wrong session")
    let normal = try await call(["open", "--mode", "background"] + target)
    let clean = try await value(["eval", "--text", "return {marker:await noodle.storage.get('clock-marker')};"] + target)
    try require(clean["marker"] is NSNull && normal.dataScope == "user", "Test data escaped into normal storage")
    _ = try await call(["close"] + target)
    // Model a provider restart: only durable records remain in this isolated runtime.
    runtime.sessions.removeAll()
    let archived = try await call(["inspect"] + exact, succeeds: false)
    try require(archived.errorCode == "session-not-running" && archived.sessionID == open.sessionID
      && archived.noodletID == open.noodletID && archived.state == "stopped"
      && archived.mode == "headless" && archived.dataScope == "test" && archived.testClock == true
      && archived.viewAvailable == false && archived.rendering == nil, "Archived inspection lost saved session metadata")
    let archivedStatus = try await call(["status"] + exact)
    try require(archivedStatus.sessionID == open.sessionID && archivedStatus.state == "stopped", "Archived status stopped working")
    print("PASS signed CLI: archived inspection error retains identity/state/mode without claiming a live view")
    print("PASS signed CLI: historical/headless targeting, native visibility, synthetic RAF/clock, cancellation/errors, Canvas/WebGL pixels, restart, exact close and test-data isolation")
    print("APPLET RENDERING TEST PASSED")
    } catch {
      await clearWebsiteData()
      throw error
    }
    await clearWebsiteData()
  }
}
