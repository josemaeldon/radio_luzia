import Foundation

struct NowPlaying: Codable, Sendable {
    let station: Station
    let listeners: Listeners
    let live: LiveStatus
    let nowPlaying: PlayingTrack
    let playingNext: PlayingTrack?
    let songHistory: [PlayingTrack]
    let isOnline: Bool
    let playback: PrimaryPlayback?

    enum CodingKeys: String, CodingKey {
        case station, listeners, live, playback
        case nowPlaying = "now_playing"
        case playingNext = "playing_next"
        case songHistory = "song_history"
        case isOnline = "is_online"
    }
}

struct Station: Codable, Sendable {
    let id: Int
    let name: String
    let shortcode: String
    let description: String
    let timezone: String
    let listenURL: URL
    let publicPlayerURL: URL?
    let requestsEnabled: Bool
    let mounts: [Mount]

    /// Use the stream selected by AzuraCast, falling back to the highest
    /// bitrate only when the server does not mark a default mount.
    var preferredMount: Mount? {
        mounts.first(where: \.isDefault)
            ?? mounts.first(where: { $0.url == listenURL })
            ?? mounts.max { lhs, rhs in lhs.bitrate < rhs.bitrate }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, shortcode, description, timezone, mounts
        case listenURL = "listen_url"
        case publicPlayerURL = "public_player_url"
        case requestsEnabled = "requests_enabled"
    }
}

struct Mount: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let url: URL
    let bitrate: Int
    let format: String
    let listeners: Listeners
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, url, bitrate, format, listeners
        case isDefault = "is_default"
    }
}

struct Listeners: Codable, Hashable, Sendable {
    let total: Int
    let unique: Int
    let current: Int
}

struct LiveStatus: Codable, Sendable {
    let isLive: Bool
    let streamerName: String
    let broadcastStart: Int?
    let art: URL?

    enum CodingKeys: String, CodingKey {
        case art
        case isLive = "is_live"
        case streamerName = "streamer_name"
        case broadcastStart = "broadcast_start"
    }
}

struct PlayingTrack: Codable, Identifiable, Sendable {
    let shID: Int?
    let playedAt: Int?
    let duration: Double
    let playlist: String?
    let streamer: String?
    let isRequest: Bool
    let song: Song
    let elapsed: Double?
    let remaining: Double?

    var id: String { shID.map(String.init) ?? "\(song.id)-\(playedAt ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case duration, playlist, streamer, song, elapsed, remaining
        case shID = "sh_id"
        case playedAt = "played_at"
        case isRequest = "is_request"
    }
}

struct Song: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let art: URL?
    let text: String
    let artist: String
    let title: String
    let album: String
    let genre: String
    let isrc: String
    let lyrics: String
    let customFields: JSONValue

    var displayTitle: String { title.isEmpty ? text : title }
    var displayArtist: String { artist.isEmpty ? "Luzia Player" : artist }

    enum CodingKeys: String, CodingKey {
        case id, art, text, artist, title, album, genre, isrc, lyrics
        case customFields = "custom_fields"
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
}

struct RequestableSong: Codable, Identifiable, Sendable {
    let requestID: String
    let requestURL: String
    let song: Song
    var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestURL = "request_url"
        case song
    }
}

struct Podcast: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let descriptionShort: String?
    let art: URL?
    let links: PodcastLinks
    enum CodingKeys: String, CodingKey { case id, title, art, links; case descriptionShort = "description_short" }
}

struct PodcastLinks: Codable, Sendable { let `publicFeed`: URL?; enum CodingKeys: String, CodingKey { case `publicFeed` = "public_feed" } }

struct PodcastEpisode: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let descriptionShort: String?
    let art: URL?
    let links: PodcastEpisodeLinks
    enum CodingKeys: String, CodingKey { case id, title, art, links; case descriptionShort = "description_short" }
}

struct PodcastEpisodeLinks: Codable, Sendable { let download: URL? }

struct PrimaryPlaybackItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let url: URL
}

struct PrimaryPlayback: Codable, Equatable, Sendable {
    let contentId: String
    let title: String
    let type: String
    let loop: Bool
    let items: [PrimaryPlaybackItem]

    func item(currentID: String?, advancing: Bool = false) -> PrimaryPlaybackItem? {
        guard !items.isEmpty else { return nil }
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return items.first }
        if !advancing { return items[index] }
        guard loop else { return nil }
        return items[(index + 1) % items.count]
    }
}
