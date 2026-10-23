import Foundation

/// A room the New Chat screen's join mode can pass to
/// `Client.joinRoomByIdOrAlias(roomIdOrAlias:serverNames:)` (MATRIX-75).
///
/// Lives beside ``MatrixUriScheme`` because it reuses that parser for
/// `matrix:` URIs and adds the forms people paste: a bare alias or room ID,
/// and a `https://matrix.to/#/` link.
public struct MatrixJoinTarget: Hashable, Sendable {
    /// A room alias (`#room:server`) or room ID (`!opaque:server` or, from
    /// room version 12, `!opaque`).
    public let roomIdOrAlias: String
    /// Servers to route the join through. Only used for room IDs; the
    /// homeserver resolves an alias by itself.
    public let viaServers: [String]

    public init(roomIdOrAlias: String, viaServers: [String]) {
        self.roomIdOrAlias = roomIdOrAlias
        self.viaServers = viaServers
    }

    /// Parses what a person typed or pasted into the join field.
    ///
    /// Accepts `#alias:server`, `!roomid:server` (optionally followed by
    /// `?via=a&via=b`), `matrix:r/…` and `matrix:roomid/…` URIs, and
    /// `https://matrix.to/#/…` links to a room. User links and anything else
    /// return `nil`.
    public init?(parsing input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("matrix:") {
            guard let uri = try? MatrixUriScheme(parseUrl: trimmed) else { return nil }
            switch uri.kind {
            case let .roomAlias(alias):
                self.init(identifier: alias, via: uri.routingVia)
            case let .roomId(roomId):
                self.init(identifier: roomId, via: uri.routingVia)
            case .user:
                return nil
            }
            return
        }

        if let fragment = Self.matrixToFragment(trimmed) {
            self.init(identifierAndQuery: fragment)
            return
        }

        self.init(identifierAndQuery: trimmed)
    }

    /// Splits `identifier?via=…` and validates the identifier.
    private init?(identifierAndQuery value: String) {
        let parts = value.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let head = parts.first else { return nil }

        // matrix.to permalinks to an event append `/$eventId`; the room is
        // the first path segment.
        let identifier = head.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""

        var via: [String] = []
        if parts.count == 2 {
            for item in parts[1].split(separator: "&") {
                let pair = item.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, pair[0] == "via" else { continue }
                let server = String(pair[1]).removingPercentEncoding ?? String(pair[1])
                if !server.isEmpty { via.append(server) }
            }
        }

        self.init(identifier: identifier, via: via)
    }

    private init?(identifier rawIdentifier: String, via: [String]) {
        let identifier = rawIdentifier.removingPercentEncoding ?? rawIdentifier
        guard !identifier.contains(where: \.isWhitespace) else { return nil }

        if identifier.hasPrefix("#") {
            guard Self.hasLocalpartAndServer(identifier) else { return nil }
            self.init(roomIdOrAlias: identifier, viaServers: via)
        } else if identifier.hasPrefix("!") {
            guard identifier.count > 1 else { return nil }
            // A room ID without `via` still routes through its own server
            // when it names one. Room version 12 IDs carry no server, and the
            // join then relies on the homeserver already knowing the room.
            var servers = via
            if servers.isEmpty, let server = Self.serverPart(of: identifier) {
                servers = [server]
            }
            self.init(roomIdOrAlias: identifier, viaServers: servers)
        } else {
            return nil
        }
    }

    /// The fragment of a matrix.to link, or `nil` if `value` is not one.
    private static func matrixToFragment(_ value: String) -> String? {
        let prefixes = ["https://matrix.to/#/", "http://matrix.to/#/", "matrix.to/#/"]
        guard let prefix = prefixes.first(where: { value.lowercased().hasPrefix($0) }) else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    private static func hasLocalpartAndServer(_ identifier: String) -> Bool {
        guard let colon = identifier.firstIndex(of: ":") else { return false }
        let localpart = identifier[identifier.index(after: identifier.startIndex) ..< colon]
        let server = identifier[identifier.index(after: colon)...]
        return !localpart.isEmpty && !server.isEmpty
    }

    private static func serverPart(of identifier: String) -> String? {
        guard let colon = identifier.firstIndex(of: ":") else { return nil }
        let server = identifier[identifier.index(after: colon)...]
        return server.isEmpty ? nil : String(server)
    }
}
