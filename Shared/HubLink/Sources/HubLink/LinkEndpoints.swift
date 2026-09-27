import Darwin
import Foundation
import Synchronization
#if os(macOS)
import SystemConfiguration
#endif

extension LinkEndpoint {
    public static let defaultPort: UInt16 = 38_415

    #if os(macOS)
    /// This Mac's own addresses: its Bonjour name, its Tailscale MagicDNS name, then every IPv4
    /// and routable IPv6 address on an active interface. Loopback and link-local addresses are left out: a device on
    /// the same Mac reaches the Hub the same way a device across the room does.
    public static func local(port: UInt16) -> [LinkEndpoint] {
        var hosts: [String] = []
        if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty {
            hosts.append("\(name).local")
        }
        var ipv4: [String] = [], ipv6: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return hosts.map { LinkEndpoint(host: $0, port: port) } }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.ifa_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &value, &buffer, socklen_t(buffer.count)) != nil else { continue }
                let text = String(cString: buffer)
                guard !text.hasPrefix("169.254.") else { continue }
                ipv4.append(text)
                if let name = tailnetName(of: text, resolve: cachedReverseLookup) { hosts.append(name) }
            case AF_INET6:
                var value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                // Link-local addresses need an interface to be usable, and temporary ones rotate.
                let bytes = withUnsafeBytes(of: value) { Array($0) }
                guard !(bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80) else { continue }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &value, &buffer, socklen_t(buffer.count)) != nil else { continue }
                ipv6.append(String(cString: buffer))
            default: continue
            }
        }
        var seen = Set<String>()
        return (hosts + ipv4 + ipv6).filter { seen.insert($0).inserted }.map { LinkEndpoint(host: $0, port: port) }
    }
    #endif

    /// The name Tailscale gives an address in its 100.64.0.0/10 range, which stays reachable
    /// wherever the device is on the tailnet. Nil for any other address.
    static func tailnetName(of address: String, resolve: (String) -> String?) -> String? {
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, octets[0] == 100, octets[1] & 0xC0 == 64,
              let name = resolve(address).map({ $0.hasSuffix(".") ? String($0.dropLast()) : $0 }),
              !name.isEmpty, name != address else { return nil }
        return name
    }

    /// Settings reads the endpoints on every redraw, so each address is looked up rarely.
    private static let reverseLookups = ReverseLookups(now: Date.init, resolve: reverseLookup)

    private static func cachedReverseLookup(_ address: String) -> String? { reverseLookups.name(of: address) }

    private static func reverseLookup(_ address: String) -> String? {
        var socket = sockaddr_in()
        socket.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socket.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address, &socket.sin_addr) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &socket) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        return status == 0 ? String(cString: buffer) : nil
    }

    /// Reads "host", "host:port", "[v6]:port" or a bare IPv6 address.
    public init?(text: String, defaultPort: UInt16) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard rest.isEmpty || rest.hasPrefix(":"), let port = rest.isEmpty ? defaultPort : UInt16(rest.dropFirst()) else { return nil }
            self.init(host: host, port: port)
        } else if text.filter({ $0 == ":" }).count == 1, let colon = text.firstIndex(of: ":") {
            guard let port = UInt16(text[text.index(after: colon)...]) else { return nil }
            self.init(host: String(text[..<colon]), port: port)
        } else {
            self.init(host: text, port: defaultPort)
        }
    }
}

/// Names found for addresses, kept for good. A miss is asked again after a while: Tailscale's
/// resolver may not be up yet when Settings first draws.
final class ReverseLookups: @unchecked Sendable {
    static let missLifetime: TimeInterval = 30

    private let now: () -> Date
    private let resolve: (String) -> String?
    private let answers = Mutex<[String: (name: String?, asked: Date)]>([:])

    init(now: @escaping () -> Date, resolve: @escaping (String) -> String?) {
        self.now = now
        self.resolve = resolve
    }

    func name(of address: String) -> String? {
        let date = now()
        if let known = answers.withLock({ $0[address] }),
           known.name != nil || date.timeIntervalSince(known.asked) <= Self.missLifetime { return known.name }
        let name = resolve(address)
        answers.withLock { $0[address] = (name, date) }
        return name
    }
}
