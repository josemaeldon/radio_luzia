import Foundation

actor AzuraCastAPI {
    static let shared = AzuraCastAPI()
    nonisolated static let isManaged = true

    enum APIError: LocalizedError {
        case invalidResponse
        case rejected(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Não foi possível carregar a configuração publicada do conteúdo."
            case .rejected(let message): message
            }
        }
    }

    nonisolated static var managedBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RadioBackendURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    struct ManagedContent: Decodable, Identifiable, Sendable {
        let id: Int
        let title: String
        let type: String
        let url: URL
    }
    private struct ManagedConfig: Decodable { let contents: [ManagedContent] }
    private let baseURL: URL?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL? = AzuraCastAPI.managedBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func managedContents() async throws -> [ManagedContent] {
        let config: ManagedConfig = try await get(path: "/api/v1/config")
        return config.contents
    }
    func nowPlaying() async throws -> NowPlaying {
        let model: NowPlaying = try await get(path: "/api/v1/nowplaying")
        guard model.isOnline, model.station.listenURL.scheme == "https",
              model.station.mounts.count == 1,
              model.station.mounts[0].isDefault,
              model.station.mounts[0].url == model.station.listenURL,
              !model.station.requestsEnabled else { throw APIError.invalidResponse }
        if let playback = model.playback {
            guard !playback.items.isEmpty,
                  playback.items.allSatisfy({ $0.url.scheme == "https" && $0.url.host != nil }),
                  playback.items.first?.url == model.station.listenURL else { throw APIError.invalidResponse }
        }
        return model
    }
    func requestableSongs(stationID: Int = 2) async throws -> [RequestableSong] { [] }
    func requestSong(_ requestID: String, stationID: Int = 2) async throws -> String {
        throw APIError.rejected("Pedidos não estão disponíveis.")
    }
    func podcasts(stationID: Int = 2) async throws -> [Podcast] {
        try await get(path: "/api/v1/podcasts")
    }
    func podcastEpisodes(_ podcastID: String, stationID: Int = 2) async throws -> [PodcastEpisode] {
        try await get(path: "/api/v1/podcast/\(podcastID)/episodes")
    }
    func publishedEpisode(_ episodeID: String, podcastID: String) async throws -> PodcastEpisode {
        let episodes = try await podcastEpisodes(podcastID)
        guard let episode = episodes.first(where: { $0.id == episodeID }),
              let url = episode.links.download, url.scheme == "https", url.host != nil else { throw APIError.invalidResponse }
        return episode
    }
    private func get<T: Decodable>(path: String) async throws -> T {
        guard let baseURL, baseURL.scheme == "https", baseURL.host != nil else { throw APIError.invalidResponse }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError.invalidResponse }
        return try decoder.decode(T.self, from: data)
    }
}
