import Darwin
import Foundation

/// Which pages Point fetches to clip: those out on the internet, not on this Mac or the local
/// network. A clip can be asked for by any page or app (`point://clip`), and what Point
/// fetches goes into the vault, which syncs: a page on the local network (a router's admin
/// page, say) mustn't be one it can be made to read. A page the browser sends with the
/// request is read from what was sent, wherever it's from.
public enum ClipAddress {
    /// Whether `url` is a web address out on the internet, by its name alone: not this Mac,
    /// not a name only the local network knows, not a private or reserved IP address.
    public static func isPublic(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        if let address = ipv4(host) { return isPublic(ipv4: address) }
        if let address = ipv6(host) { return isPublic(ipv6: address) }
        // A name: one with no dot is the local network's ("router"), as are these endings.
        guard host.contains(".") else { return false }
        let local = ["localhost", "local", "internal", "lan", "home", "home.arpa", "intranet", "corp"]
        return !local.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether every address `url`'s name has is out on the internet: a public name can be
    /// set to point at the local network. Looked up off the main thread.
    public static func resolvesPublicly(_ url: URL) async -> Bool {
        guard isPublic(url), let host = url.host else { return false }
        return await Task.detached(priority: .userInitiated) {
            var hints = addrinfo()
            hints.ai_socktype = SOCK_STREAM
            var first: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &first) == 0, let first else { return false }
            defer { freeaddrinfo(first) }
            var found = false
            var entry: UnsafeMutablePointer<addrinfo>? = first
            while let current = entry {
                defer { entry = current.pointee.ai_next }
                guard let address = current.pointee.ai_addr else { continue }
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                    guard isPublic(ipv4: ip) else { return false }
                    found = true
                case AF_INET6:
                    let ip = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                        withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
                    }
                    guard isPublic(ipv6: ip) else { return false }
                    found = true
                default:
                    continue
                }
            }
            return found
        }.value
    }

    // MARK: IP addresses

    /// An IPv4 address in any form the system takes: `127.0.0.1`, but also `127.1`,
    /// `0x7f.0.0.1` and `2130706433`, which all mean this Mac.
    static func ipv4(_ host: String) -> UInt32? {
        guard host.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == "x" }) else { return nil }
        var address = in_addr()
        guard inet_aton(host, &address) != 0 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    static func ipv6(_ host: String) -> [UInt8]? {
        guard host.contains(":") else { return nil }
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return nil }
        return withUnsafeBytes(of: address) { Array($0) }
    }

    static func isPublic(ipv4 ip: UInt32) -> Bool {
        let reserved: [(UInt32, UInt32)] = [
            (0x0000_0000, 8),  // 0.0.0.0/8: "this network"
            (0x0A00_0000, 8),  // 10.0.0.0/8: private
            (0x6440_0000, 10), // 100.64.0.0/10: carrier-grade NAT
            (0x7F00_0000, 8),  // 127.0.0.0/8: this Mac
            (0xA9FE_0000, 16), // 169.254.0.0/16: link-local
            (0xAC10_0000, 12), // 172.16.0.0/12: private
            (0xC000_0000, 24), // 192.0.0.0/24: protocol assignments
            (0xC0A8_0000, 16), // 192.168.0.0/16: private
            (0xC612_0000, 15), // 198.18.0.0/15: benchmarking
            (0xE000_0000, 4),  // 224.0.0.0/4: multicast
            (0xF000_0000, 4),  // 240.0.0.0/4: reserved, and broadcast
        ]
        return !reserved.contains { network, bits in ip >> (32 - bits) == network >> (32 - bits) }
    }

    static func isPublic(ipv6 bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) { return false } // ::
        if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return false } // ::1
        if bytes[0] & 0xFE == 0xFC { return false } // fc00::/7: unique local
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return false } // fe80::/10: link-local
        if bytes[0] == 0xFF { return false } // ff00::/8: multicast
        // An IPv4 address written as IPv6 (::ffff:a.b.c.d): as that address.
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return isPublic(ipv4: bytes[12..<16].reduce(0) { $0 << 8 | UInt32($1) })
        }
        return true
    }
}

/// Follows a redirect only to a page out on the internet.
final class PublicRedirectsOnly: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(ClipAddress.isPublic) == true ? request : nil)
    }
}
