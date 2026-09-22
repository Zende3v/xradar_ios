import Foundation
import EonaCore

/// Where a driver of the group stands right now.
public enum GroupMemberState: String, Sendable, Hashable {
    /// In the group, not on the road yet.
    case invited
    case driving
    case arrived
    /// Stepped out of the group before arriving.
    case left

    public var label: String {
        switch self {
        case .invited: "Pas encore parti"
        case .driving: "En route"
        case .arrived: "Arrivé"
        case .left: "A quitté le trajet"
        }
    }
}

/// One driver of the group, as the others are allowed to see them. Someone who stopped sharing
/// gives their name and their state, and nothing else: no position, no speed, no progress.
public struct GroupMember: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let state: GroupMemberState
    public let sharing: Bool
    /// Heard from in the last moments; false means "signal perdu", last position kept.
    public let online: Bool
    public let rank: Int?
    public let position: GeoPoint?
    public let bearing: Double?
    public let speedKmh: Int?
    /// 0 to 1 along their own route.
    public let progress: Double
    public let remainingMeters: Int?
    public let etaAt: Date?
    /// Their time and distance, once they are there.
    public let durationSeconds: Int?
    public let distanceMeters: Int?
    /// Their route: empty except in the "suivre ce participant" view.
    public let route: [GeoPoint]

    /// "En route · 112 km/h", "Arrivé · 2e", "Ne partage pas sa position".
    public var detailLabel: String {
        if !sharing { return "Ne partage pas sa position" }
        if state == .arrived {
            return [rank.map { "\($0)\($0 == 1 ? "er" : "e")" }, durationSeconds.map(Self.duration)]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        if state == .left || state == .invited { return state.label }
        if !online { return "Signal perdu" }
        var parts: [String] = []
        if let speedKmh { parts.append("\(speedKmh) km/h") }
        if let remainingMeters { parts.append(Self.distance(remainingMeters)) }
        return parts.isEmpty ? state.label : parts.joined(separator: " · ")
    }

    static func distance(_ metres: Int) -> String {
        if metres < 1000 { return "\(metres) m" }
        return String(format: "%.0f km", Double(metres) / 1000)
    }

    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// One line of the arrival ranking, frozen when the trip ends.
public struct GroupRankEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// nil for someone who never arrived.
    public let rank: Int?
    public let state: GroupMemberState
    public let durationSeconds: Int?
    public let distanceMeters: Int?

    public init(id: String, name: String, rank: Int?, state: GroupMemberState, durationSeconds: Int?, distanceMeters: Int?) {
        self.id = id
        self.name = name
        self.rank = rank
        self.state = state
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    /// "1er", "3e", "—".
    public var rankLabel: String {
        guard let rank else { return "—" }
        return rank == 1 ? "1er" : "\(rank)e"
    }

    /// "1 h 12 · 465 km".
    public var timeLabel: String {
        [durationSeconds.map(GroupMember.duration), distanceMeters.map(GroupMember.distance)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// The link that lets someone watch the group without driving in it.
public struct GroupLink: Sendable, Hashable {
    public let url: URL
    public let token: String
    public let observers: Int
}

/// The group trip as one of its drivers sees it.
public struct TripGroup: Sendable, Hashable {
    public let id: String
    /// What the others type to join, "K7M2PQ".
    public let code: String
    public let isHost: Bool
    public let toLabel: String?
    public let destination: GeoPoint?
    public let maxMembers: Int
    /// Set once the trip is over: the ranking stops moving.
    public let finishedAt: Date?
    public let ranking: [GroupRankEntry]
    public let link: GroupLink?
    public let sharing: Bool
    public let observable: Bool
    public let myState: GroupMemberState
    public let myRank: Int?
    public let members: [GroupMember]

    public var isOver: Bool { finishedAt != nil }
    public var isFull: Bool { members.count >= maxMembers }

    /// Everyone but me.
    public func others(than id: String?) -> [GroupMember] {
        members.filter { $0.id != id }
    }
}

/// The group as someone holding the link sees it: only the drivers who agreed to be seen.
public struct ObservedGroup: Sendable, Hashable {
    public let toLabel: String?
    public let destination: GeoPoint?
    public let finishedAt: Date?
    public let ranking: [GroupRankEntry]
    public let members: [GroupMember]

    public var isOver: Bool { finishedAt != nil }
}

/// "Trajet en groupe" (`/api/trips/group`): up to five drivers, each from their own start, one
/// destination. Like the plain share, the backend holds it in memory and writes nothing down.
public struct TripGroupAPI: Sendable {
    static let timeout: TimeInterval = 8

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    /// Opens a group and hands back its joining code.
    public func create(toLabel: String?, destination: GeoPoint, route: [GeoPoint], token: String?) async -> TripGroup? {
        var json: [String: Any] = ["destination": ["lat": destination.lat, "lon": destination.lon]]
        if let toLabel { json["toLabel"] = toLabel }
        if !route.isEmpty { json["route"] = coordinates(route) }
        return await group("POST", "/api/trips/group", json: json, token: token)
    }

    /// Joins the group behind a code; nil when it is unknown, full or over.
    public func join(code: String, route: [GeoPoint], token: String?) async -> TripGroup? {
        var json: [String: Any] = ["code": code]
        if !route.isEmpty { json["route"] = coordinates(route) }
        return await group("POST", "/api/trips/group/join", json: json, token: token)
    }

    /// My group as it stands, or nil when I am in none.
    public func mine(token: String?) async -> TripGroup? {
        await group("GET", "/api/trips/group", json: nil, token: token)
    }

    /// Where I am and how far along I am — and whether the others may still see it.
    @discardableResult
    public func update(
        position: GeoPoint?,
        bearing: Double?,
        speedKmh: Int?,
        remainingMeters: Int?,
        etaSeconds: Int?,
        progress: Double?,
        distanceMeters: Int?,
        route: [GeoPoint]? = nil,
        arrived: Bool = false,
        sharing: Bool? = nil,
        observable: Bool? = nil,
        token: String?
    ) async -> TripGroup? {
        var json: [String: Any] = [:]
        if let position {
            json["lat"] = position.lat
            json["lon"] = position.lon
        }
        if let bearing { json["bearing"] = bearing }
        if let speedKmh { json["speedKmh"] = speedKmh }
        if let remainingMeters { json["remainingM"] = remainingMeters }
        if let etaSeconds { json["etaS"] = etaSeconds }
        if let progress { json["progress"] = progress }
        if let distanceMeters { json["distanceM"] = distanceMeters }
        if let route, !route.isEmpty { json["route"] = coordinates(route) }
        if arrived { json["arrived"] = true }
        if let sharing { json["sharing"] = sharing }
        if let observable { json["observable"] = observable }
        return await group("PATCH", "/api/trips/group/me", json: json, token: token)
    }

    /// One participant in full — their route included — for "suivre ce participant".
    public func member(_ memberId: String, token: String?) async -> GroupMember? {
        guard let request = try? client.request(
                  "GET",
                  client.url("/api/trips/group/member/\(BackendClient.segment(memberId))"),
                  token: token,
                  timeout: Self.timeout
              ),
              let result = try? await client.send(request), result.isSuccessful,
              let member = result.json?.object("member")
        else { return nil }
        return Self.member(member)
    }

    /// I step out. The host stepping out ends the trip for everyone.
    @discardableResult
    public func leave(token: String?) async -> Bool {
        await plain("POST", "/api/trips/group/leave", token: token)
    }

    /// The host cancels the trip.
    public func cancel(token: String?) async -> TripGroup? {
        await group("DELETE", "/api/trips/group", json: nil, token: token)
    }

    /// The host opens the link that lets others watch, or revokes it.
    public func openLink(token: String?) async -> TripGroup? {
        await group("POST", "/api/trips/group/link", json: nil, token: token)
    }

    public func revokeLink(token: String?) async -> TripGroup? {
        await group("DELETE", "/api/trips/group/link", json: nil, token: token)
    }

    /// One watcher is shown the door; the link keeps working for the others.
    public func removeObserver(_ observerId: String, token: String?) async -> TripGroup? {
        await group("DELETE", "/api/trips/group/observers/\(BackendClient.segment(observerId))", json: nil, token: token)
    }

    /// The group behind a watch link; nil once it is revoked or the trip is over.
    public func watch(_ linkToken: String, token: String?) async -> ObservedGroup? {
        guard let request = try? client.request(
                  "GET",
                  client.url("/api/trips/group/watch/\(BackendClient.segment(linkToken))"),
                  token: token,
                  timeout: Self.timeout
              ),
              let result = try? await client.send(request), result.isSuccessful,
              let group = result.json?.object("group")
        else { return nil }
        return ObservedGroup(
            toLabel: group.nonBlankString("toLabel"),
            destination: Self.point(group.object("destination")),
            finishedAt: Self.date(group.nonBlankString("finishedAt")),
            ranking: (group.objects("ranking") ?? []).map(Self.rank),
            members: (group.objects("members") ?? []).map(Self.member)
        )
    }

    private func plain(_ method: String, _ path: String, token: String?) async -> Bool {
        guard let request = try? client.request(method, client.url(path), token: token, timeout: Self.timeout),
              let result = try? await client.send(request)
        else { return false }
        return result.isSuccessful
    }

    private func group(_ method: String, _ path: String, json: [String: Any]?, token: String?) async -> TripGroup? {
        guard let request = try? client.request(method, client.url(path), json: json, token: token, timeout: Self.timeout),
              let result = try? await client.send(request), result.isSuccessful,
              let group = result.json?.object("group")
        else { return nil }
        return Self.group(group)
    }

    private static func group(_ json: JSON) -> TripGroup? {
        let id = json.string("id")
        guard !id.isEmpty else { return nil }
        let me = json.object("me")
        return TripGroup(
            id: id,
            code: json.string("code"),
            isHost: json.bool("host"),
            toLabel: json.nonBlankString("toLabel"),
            destination: point(json.object("destination")),
            maxMembers: max(1, json.int("maxMembers", 5)),
            finishedAt: date(json.nonBlankString("finishedAt")),
            ranking: (json.objects("ranking") ?? []).map(rank),
            link: link(json.object("link")),
            sharing: me?.bool("sharing", true) ?? true,
            observable: me?.bool("observable", true) ?? true,
            myState: GroupMemberState(rawValue: me?.string("state") ?? "") ?? .invited,
            myRank: (me?.isNull("rank") ?? true) ? nil : me?.int("rank"),
            members: (json.objects("members") ?? []).map(member)
        )
    }

    private static func member(_ json: JSON) -> GroupMember {
        let position = json.object("position")
        let bearing = position?.double("bearing")
        return GroupMember(
            id: json.string("id"),
            name: json.nonBlankString("name") ?? "Un conducteur",
            state: GroupMemberState(rawValue: json.string("state")) ?? .invited,
            sharing: json.bool("sharing", true),
            online: json.bool("online"),
            rank: json.isNull("rank") ? nil : json.int("rank"),
            position: point(position),
            bearing: (bearing?.isFinite ?? false) ? bearing : nil,
            speedKmh: json.isNull("speedKmh") ? nil : json.int("speedKmh"),
            progress: max(0, min(1, json.double("progress", 0))),
            remainingMeters: json.isNull("remainingM") ? nil : json.int("remainingM"),
            etaAt: date(json.nonBlankString("etaAt")),
            durationSeconds: json.isNull("durationS") ? nil : json.int("durationS"),
            distanceMeters: json.isNull("distanceM") ? nil : json.int("distanceM"),
            route: (json.array("route") ?? []).compactMap(JSON.lonLat)
        )
    }

    private static func rank(_ json: JSON) -> GroupRankEntry {
        GroupRankEntry(
            id: json.string("id"),
            name: json.nonBlankString("name") ?? "Un conducteur",
            rank: json.isNull("rank") ? nil : json.int("rank"),
            state: GroupMemberState(rawValue: json.string("state")) ?? .invited,
            durationSeconds: json.isNull("durationS") ? nil : json.int("durationS"),
            distanceMeters: json.isNull("distanceM") ? nil : json.int("distanceM")
        )
    }

    private static func link(_ json: JSON?) -> GroupLink? {
        guard let json, let url = URL(string: json.string("url")) else { return nil }
        let token = json.string("token")
        return token.isEmpty ? nil : GroupLink(url: url, token: token, observers: json.int("observers"))
    }

    private static func point(_ value: JSON?) -> GeoPoint? {
        guard let value else { return nil }
        let lat = value.double("lat")
        let lon = value.double("lon")
        return lat.isFinite && lon.isFinite ? GeoPoint(lat: lat, lon: lon) : nil
    }

    /// The backend writes fractional seconds; the plain reader would refuse them. Built here
    /// rather than kept around: ISO8601DateFormatter is not Sendable.
    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
