import XCTest
@testable import RadioLuzia

final class NowPlayingTests: XCTestCase {
    func testDecodesRepresentativeAzuraCastPayload() throws {
        let data = #"{"station":{"id":2,"name":"Paróquia Santa Luzia","shortcode":"santaluziapgm","description":"Web Rádio","timezone":"America/Belem","listen_url":"https://example.com/192","public_player_url":"https://example.com/public","requests_enabled":true,"mounts":[]},"listeners":{"total":3,"unique":2,"current":2},"live":{"is_live":false,"streamer_name":"","broadcast_start":null,"art":null},"now_playing":{"sh_id":10,"played_at":1000,"duration":240,"playlist":"Músicas","streamer":"","is_request":false,"song":{"id":"song","art":null,"custom_fields":{},"text":"Artista - Faixa","artist":"Artista","title":"Faixa","album":"Álbum","genre":"Gospel","isrc":"","lyrics":""},"elapsed":60,"remaining":180},"playing_next":null,"song_history":[],"is_online":true}"#.data(using: .utf8)!

        let result = try JSONDecoder().decode(NowPlaying.self, from: data)
        XCTAssertEqual(result.station.name, "Paróquia Santa Luzia")
        XCTAssertEqual(result.nowPlaying.song.title, "Faixa")
        XCTAssertEqual(result.nowPlaying.elapsed, 60)
        XCTAssertTrue(result.isOnline)
    }

    func testCustomFieldsAcceptsAzuraCastArrayShape() throws {
        let data = #"{"id":"song","art":null,"custom_fields":[],"text":"Faixa","artist":"","title":"Faixa","album":"","genre":"","isrc":"","lyrics":""}"#.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: data)
        XCTAssertEqual(song.customFields, .array([]))
    }
}

private final class ManagedAPIProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension NowPlayingTests {
    private func managedPayload(url: String = "https://audio.example.com/primary.mp3") throws -> Data {
        let original = #"{"station":{"id":2,"name":"Paróquia Santa Luzia","shortcode":"santaluziapgm","description":"Web Rádio","timezone":"America/Belem","listen_url":"https://example.com/192","public_player_url":"https://example.com/public","requests_enabled":true,"mounts":[]},"listeners":{"total":3,"unique":2,"current":2},"live":{"is_live":false,"streamer_name":"","broadcast_start":null,"art":null},"now_playing":{"sh_id":10,"played_at":1000,"duration":240,"playlist":"Músicas","streamer":"","is_request":false,"song":{"id":"song","art":null,"custom_fields":{},"text":"Artista - Faixa","artist":"Artista","title":"Faixa","album":"Álbum","genre":"Gospel","isrc":"","lyrics":""},"elapsed":60,"remaining":180},"playing_next":null,"song_history":[],"is_online":true}"#.data(using: .utf8)!
        var json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        var station = json["station"] as! [String: Any]
        station["listen_url"] = url
        station["requests_enabled"] = false
        station["mounts"] = [["id": 42, "name": "Principal publicado", "url": url, "bitrate": 0, "format": "audio", "is_default": true, "listeners": ["total": 0, "unique": 0, "current": 0]]]
        json["station"] = station
        return try JSONSerialization.data(withJSONObject: json)
    }

    @MainActor
    func testAPIControlsPrimaryAndClearsRemovedContentWithoutLegacyFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManagedAPIProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ManagedAPIProtocol.requests = []
        ManagedAPIProtocol.status = 200
        ManagedAPIProtocol.payload = try managedPayload()
        let api = AzuraCastAPI(baseURL: URL(string: "https://backend.test")!, session: session)
        let player = RadioPlayer(api: api)
        let first = await player.refreshMetadata()
        XCTAssertTrue(first)
        XCTAssertEqual(player.selectedMount?.id, 42)
        XCTAssertEqual(player.selectedMount?.url.absoluteString, "https://audio.example.com/primary.mp3")
        ManagedAPIProtocol.payload = try managedPayload(url: "https://audio.example.com/changed.mp3")
        let changed = await player.refreshMetadata()
        XCTAssertTrue(changed)
        XCTAssertEqual(player.selectedMount?.url.absoluteString, "https://audio.example.com/changed.mp3")
        ManagedAPIProtocol.status = 503
        ManagedAPIProtocol.payload = Data("{}".utf8)
        let removed = await player.refreshMetadata(showError: false)
        XCTAssertFalse(removed)
        XCTAssertNil(player.nowPlaying)
        XCTAssertNil(player.selectedMount)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(ManagedAPIProtocol.requests.count, 3)
        XCTAssertTrue(ManagedAPIProtocol.requests.allSatisfy { $0.url?.host == "backend.test" && $0.url?.path == "/api/v1/nowplaying" && $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertEqual(AzuraCastAPI.managedBaseURL?.absoluteString, "https://radio-luzia.vercel.app")
    }

    @MainActor
    func testPodcastEpisodesUsePublishedFeedURLsAndRejectRemovedEpisodes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManagedAPIProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ManagedAPIProtocol.status = 200
        ManagedAPIProtocol.requests = []
        ManagedAPIProtocol.payload = Data(#"[{"id":"9-episode-hash","title":"Episódio do feed","links":{"download":"https://audio.example.com/episode.mp3"}}]"#.utf8)
        let api = AzuraCastAPI(baseURL: URL(string: "https://backend.test")!, session: session)
        let episode = try await api.publishedEpisode("9-episode-hash", podcastID: "9")
        XCTAssertEqual(episode.links.download?.absoluteString, "https://audio.example.com/episode.mp3")
        ManagedAPIProtocol.payload = Data("[]".utf8)
        do { _ = try await api.publishedEpisode("9-episode-hash", podcastID: "9"); XCTFail("Removed episodes must not resume") }
        catch { XCTAssertTrue(error is AzuraCastAPI.APIError) }
        XCTAssertEqual(ManagedAPIProtocol.requests.count, 2)
        XCTAssertTrue(ManagedAPIProtocol.requests.allSatisfy { $0.url?.path == "/api/v1/podcast/9/episodes" })
    }

    func testMissingBackendNeverUsesOldStation() async throws {
        let api = AzuraCastAPI(baseURL: nil)
        do { _ = try await api.nowPlaying(); XCTFail("Missing API URL must fail closed") }
        catch { XCTAssertTrue(error is AzuraCastAPI.APIError) }
    }
}

extension NowPlayingTests {
    func testPrimaryPodcastQueueRepeatsInOrderAndPreservesCurrentEpisode() throws {
        let first = PrimaryPlaybackItem(id: "one", title: "Primeiro", url: URL(string: "https://example.com/one.mp3")!)
        let second = PrimaryPlaybackItem(id: "two", title: "Segundo", url: URL(string: "https://example.com/two.mp3")!)
        let queue = PrimaryPlayback(contentId: "10", title: "Podcast", type: "podcast_feed", loop: true, items: [first, second])
        XCTAssertEqual(queue.item(currentID: nil)?.id, "one")
        XCTAssertEqual(queue.item(currentID: "two")?.id, "two")
        XCTAssertEqual(queue.item(currentID: "one", advancing: true)?.id, "two")
        XCTAssertEqual(queue.item(currentID: "two", advancing: true)?.id, "one")
        XCTAssertEqual(queue.item(currentID: "removed", advancing: true)?.id, "one")
        let single = PrimaryPlayback(contentId: "10", title: "Podcast", type: "podcast_feed", loop: true, items: [first])
        XCTAssertEqual(single.item(currentID: "one", advancing: true)?.id, "one")
        let audio = PrimaryPlayback(contentId: "10", title: "Áudio", type: "audio", loop: false, items: [first])
        XCTAssertNil(audio.item(currentID: "one", advancing: true))
    }
}
