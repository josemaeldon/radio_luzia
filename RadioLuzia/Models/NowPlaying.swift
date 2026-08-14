import Foundation

struct NowPlaying: Codable, Sendable {
    let station: Station
    let listeners: Listeners
    let live: LiveStatus
    let nowPlaying: PlayingTrack
    let playingNext: PlayingTrack?
    let songHistory: [PlayingTrack]
    let isOnline: Bool

    enum CodingKeys: String, CodingKey {
        case station, listeners, live
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
    var displayArtist: String { artist.isEmpty ? "Paróquia Santa Luzia" : artist }

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
