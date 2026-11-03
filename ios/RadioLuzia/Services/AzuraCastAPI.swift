import Foundation

actor AzuraCastAPI {
    static let shared = AzuraCastAPI()

    enum APIError: LocalizedError {
        case invalidResponse
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "A rádio enviou uma resposta inválida."
            case .rejected(let message): message
            }
        }
    }

    nonisolated static var isManaged: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RadioBackendURL") as? String else { return false }
        return !value.isEmpty
    }

    nonisolated static var managedBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RadioBackendURL") as? String,
              !value.isEmpty, let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    struct ManagedContent: Decodable, Identifiable, Sendable {
        let id: Int
        let title: String
        let type: String
        let url: URL
    }
    private struct ManagedConfig: Decodable { let contents: [ManagedContent] }

    func managedContents() async throws -> [ManagedContent] {
        guard Self.isManaged else { return [] }
        let config: ManagedConfig = try await get(path: "/api/v1/config")
        return config.contents
    }

    private let baseURL = URL(string: "https://webradio.cloudbr.app")!
    private let decoder = JSONDecoder()

    func nowPlaying() async throws -> NowPlaying {
        try await get(path: !Self.isManaged ? "/api/nowplaying/santaluziapgm" : "/api/v1/nowplaying")
    }

    func requestableSongs(stationID: Int = 2) async throws -> [RequestableSong] {
        try await get(path: "/api/station/\(stationID)/requests")
    }

    func requestSong(_ requestID: String, stationID: Int = 2) async throws -> String {
        guard !Self.isManaged else { throw APIError.rejected("Pedidos não estão disponíveis.") }
        var request = URLRequest(url: baseURL.appending(path: "/api/station/\(stationID)/request/\(requestID)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let payload = (try? JSONDecoder().decode(RequestResponse.self, from: data))
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.rejected(payload?.message ?? "Não foi possível enviar o pedido agora.")
        }
        return payload?.message ?? "Pedido enviado para a programação."
    }

    func podcasts(stationID: Int = 2) async throws -> [Podcast] {
        try await get(path: !Self.isManaged ? "/api/station/\(stationID)/public/podcasts" : "/api/v1/podcasts")
    }

    func podcastEpisodes(_ podcastID: String, stationID: Int = 2) async throws -> [PodcastEpisode] {
        try await get(path: !Self.isManaged ? "/api/station/\(stationID)/public/podcast/\(podcastID)/episodes" : "/api/v1/podcast/\(podcastID)/episodes")
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        if Self.isManaged && Self.managedBaseURL == nil { throw APIError.invalidResponse }
        var request = URLRequest(url: (Self.managedBaseURL ?? baseURL).appending(path: path))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct RequestResponse: Decodable {
    let message: String?
}
