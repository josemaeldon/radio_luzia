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

    private let baseURL = URL(string: "https://webradio.cloudbr.app")!
    private let decoder = JSONDecoder()

    func nowPlaying() async throws -> NowPlaying {
        try await get(path: "/api/nowplaying/santaluziapgm")
    }

    func requestableSongs(stationID: Int = 2) async throws -> [RequestableSong] {
        try await get(path: "/api/station/\(stationID)/requests")
    }

    func requestSong(_ requestID: String, stationID: Int = 2) async throws -> String {
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
        try await get(path: "/api/station/\(stationID)/public/podcasts")
    }

    func podcastEpisodes(_ podcastID: Int, stationID: Int = 2) async throws -> [PodcastEpisode] {
        try await get(path: "/api/station/\(stationID)/public/podcast/\(podcastID)/episodes")
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
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
