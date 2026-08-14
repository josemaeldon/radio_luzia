import SwiftUI

struct StationDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        NavigationStack {
            List {
                if let model = player.nowPlaying {
                    Section("Estação") {
                        LabeledContent("Nome", value: model.station.name)
                        LabeledContent("Descrição", value: model.station.description)
                        LabeledContent("Fuso horário", value: model.station.timezone)
                        LabeledContent("Ouvintes agora", value: "\(model.listeners.current)")
                        LabeledContent("Status", value: model.isOnline ? "No ar" : "Fora do ar")
                    }
                    if model.live.isLive {
                        Section("Transmissão ao vivo") {
                            LabeledContent("Apresentador", value: model.live.streamerName.isEmpty ? "Ao vivo" : model.live.streamerName)
                        }
                    }
                    metadataSection(model.nowPlaying.song, playlist: model.nowPlaying.playlist)
                    if !model.nowPlaying.song.lyrics.isEmpty {
                        Section("Letra") { Text(model.nowPlaying.song.lyrics).textSelection(.enabled) }
                    }
                    Section("Tecnologia") {
                        Label("Metadados instantâneos via WebSocket", systemImage: "bolt.horizontal.circle")
                        Label("Áudio Icecast em segundo plano", systemImage: "waveform.circle")
                        Label("Controles na tela bloqueada", systemImage: "lock.iphone")
                    }
                }
            }
            .navigationTitle("Sobre a transmissão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func metadataSection(_ song: Song, playlist: String?) -> some View {
        Section("Metadados da faixa") {
            LabeledContent("Título", value: song.displayTitle)
            LabeledContent("Artista", value: song.displayArtist)
            if !song.album.isEmpty { LabeledContent("Álbum", value: song.album) }
            if !song.genre.isEmpty { LabeledContent("Gênero", value: song.genre) }
            if !song.isrc.isEmpty { LabeledContent("ISRC", value: song.isrc) }
            if let playlist, !playlist.isEmpty { LabeledContent("Playlist", value: playlist) }
        }
    }
}

