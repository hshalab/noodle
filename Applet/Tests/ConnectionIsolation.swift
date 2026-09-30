import Foundation

/// Headless signed fixture. Uses only temporary sockets, never a real app group,
/// user library, Launch Services, or UI. Compile alongside AppletBridge sources.
@main struct ConnectionIsolation {
    static func main() async {
        do {
            let args = CommandLine.arguments
            if args[1] == "identity" {
                print(AppletBuildIdentity.current.rawValue)
                return
            }
            let socket = URL(fileURLWithPath: args[2]), team = args[3]
            if args[1] == "server" {
                // "hold" keeps every request busy for a while, as Applet's library scan does.
                let hold = args.count > 4 && args[4] == "hold"
                let server = try AppletConnectionServer(socket: socket, team: team) { _, identity in
                    if hold { try? await Task.sleep(for: .milliseconds(300)) }
                    var response = AppletResponse(); response.text = identity; return response
                }
                try await Task.sleep(for: .seconds(30))
                withExtendedLifetime(server) {}
            } else if args[1] == "burst" {
                // As many requests at once as the Shared popover has noodlet rows.
                let count = Int(args[4]) ?? 8
                let failures = await withTaskGroup(of: String?.self) { group in
                    for _ in 0..<count {
                        group.addTask {
                            do { _ = try await AppletConnection.call(.init(.list), socket: socket, team: team).checked(); return nil }
                            catch { return error.localizedDescription }
                        }
                    }
                    return await group.reduce(into: [String]()) { if let failure = $1 { $0.append(failure) } }
                }
                print("answered \(count - failures.count) of \(count)")
                for failure in Set(failures) { print("failed: \(failure)") }
            } else {
                let provider = args.count > 4 ? args[4] : AppletConnection.providerID
                let result = try await AppletConnection.call(.init(.list), socket: socket, team: team, providerID: provider).checked()
                print(result.text ?? "missing peer")
            }
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
