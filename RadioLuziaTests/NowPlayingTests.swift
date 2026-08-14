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
