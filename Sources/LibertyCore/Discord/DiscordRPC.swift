import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Minimal Discord Rich Presence client over Discord's local IPC socket.
/// Needs a Discord application ID (discord.com/developers → New Application).
public final class DiscordRPC {
    enum Opcode: UInt32 {
        case handshake = 0
        case frame = 1
        case close = 2
    }

    public struct Activity: Equatable {
        public var details: String
        public var state: String
        public var start: Date?
        public var largeImage: String?
        public var largeText: String?

        public init(details: String, state: String, start: Date? = nil, largeImage: String? = "logo", largeText: String? = "Liberty Loader") {
            self.details = details
            self.state = state
            self.start = start
            self.largeImage = largeImage
            self.largeText = largeText
        }
    }

    /// Liberty Loader's own Discord application. Empty until one is registered; users can also set their own in Settings.
    public static let bundledApplicationID = ""

    public let applicationID: String
    private var socket: Int32 = -1

    public init(applicationID: String) {
        self.applicationID = applicationID
    }

    deinit { disconnect() }

    public var isConnected: Bool { socket >= 0 }

    // MARK: Encoding (pure, tested)

    static func frame(_ op: Opcode, _ payload: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        var data = Data()
        var opLE = op.rawValue.littleEndian
        var lengthLE = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &opLE) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &lengthLE) { data.append(contentsOf: $0) }
        data.append(json)
        return data
    }

    static func activityPayload(_ activity: Activity?, pid: Int32, nonce: String) -> [String: Any] {
        var args: [String: Any] = ["pid": Int(pid)]
        if let activity {
            var body: [String: Any] = ["details": activity.details, "state": activity.state]
            if let start = activity.start { body["timestamps"] = ["start": Int(start.timeIntervalSince1970)] }
            var assets: [String: Any] = [:]
            if let image = activity.largeImage { assets["large_image"] = image }
            if let text = activity.largeText { assets["large_text"] = text }
            if !assets.isEmpty { body["assets"] = assets }
            args["activity"] = body
        }
        return ["cmd": "SET_ACTIVITY", "args": args, "nonce": nonce]
    }

    // MARK: Connection

    /// Connects to the first available `discord-ipc-N` socket. Returns false when Discord isn't running.
    @discardableResult
    public func connect() -> Bool {
        #if canImport(Darwin)
        if isConnected { return true }
        let dirs = [ProcessInfo.processInfo.environment["TMPDIR"], NSTemporaryDirectory(), "/tmp"].compactMap { $0 }
        for dir in dirs {
            for n in 0..<10 {
                let path = (dir as NSString).appendingPathComponent("discord-ipc-\(n)")
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                let capacity = MemoryLayout.size(ofValue: address.sun_path)
                guard path.utf8.count < capacity else { Darwin.close(fd); continue }
                withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, path, capacity) }
                }
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                if result == 0 {
                    socket = fd
                    var noSigPipe: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                    // Never block the app for long if Discord stops answering.
                    var timeout = timeval(tv_sec: 2, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                    if send(.handshake, ["v": 1, "client_id": applicationID]) {
                        _ = readFrame()
                        return true
                    }
                    disconnect()
                } else {
                    Darwin.close(fd)
                }
            }
        }
        #endif
        return false
    }

    public func disconnect() {
        #if canImport(Darwin)
        if socket >= 0 { Darwin.close(socket) }
        #endif
        socket = -1
    }

    /// Sets (or clears, with nil) the activity. Reconnects once if the socket dropped.
    @discardableResult
    public func setActivity(_ activity: Activity?) -> Bool {
        let payload = Self.activityPayload(activity, pid: ProcessInfo.processInfo.processIdentifier, nonce: UUID().uuidString)
        if !isConnected && !connect() { return false }
        if send(.frame, payload) { _ = readFrame(); return true }
        disconnect()
        guard connect() else { return false }
        return send(.frame, payload)
    }

    private func send(_ op: Opcode, _ payload: [String: Any]) -> Bool {
        #if canImport(Darwin)
        guard isConnected, let data = Self.frame(op, payload) else { return false }
        return data.withUnsafeBytes { raw in
            Darwin.write(socket, raw.baseAddress, raw.count) == raw.count
        }
        #else
        return false
        #endif
    }

    /// Reads and discards one reply frame (Discord answers every command).
    private func readFrame() -> Bool {
        #if canImport(Darwin)
        guard isConnected else { return false }
        var header = [UInt8](repeating: 0, count: 8)
        guard Darwin.read(socket, &header, 8) == 8 else { return false }
        let length = Int(UInt32(header[4]) | UInt32(header[5]) << 8 | UInt32(header[6]) << 16 | UInt32(header[7]) << 24)
        guard length > 0, length < 1_000_000 else { return true }
        var body = [UInt8](repeating: 0, count: length)
        return Darwin.read(socket, &body, length) > 0
        #else
        return false
        #endif
    }
}
