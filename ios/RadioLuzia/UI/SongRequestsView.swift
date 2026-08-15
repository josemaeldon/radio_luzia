import SwiftUI
import AVFoundation
import Observation

struct SongRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [RequestableSong] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var sendingID: String?
    @State private var alertMessage: String?
    @State private var visibleCount = 30

    private var filteredSongs: [RequestableSong] {
        guard !searchText.isEmpty else { return songs }
        return songs.filter {
            $0.song.displayTitle.localizedStandardContains(searchText)
                || $0.song.displayArtist.localizedStandardContains(searchText)
                || $0.song.album.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Carregando repertório…")
                } else if songs.isEmpty {
                    ContentUnavailableView("Pedidos indisponíveis", systemImage: "music.note.slash", description: Text("Tente novamente mais tarde."))
                } else {
                    List(Array(filteredSongs.prefix(visibleCount))) { item in
                        Button { Task { await request(item) } } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: item.song.art) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "music.note").frame(maxWidth: .infinity, maxHeight: .infinity).background(RadioTheme.wine)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.song.displayTitle).foregroundStyle(.primary).lineLimit(1)
                                    Text(item.song.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if sendingID == item.id { ProgressView() }
                                else { Image(systemName: "plus.circle").foregroundStyle(RadioTheme.gold) }
                            }
                        }
                        .disabled(sendingID != nil)
                        .onAppear { if item.id == filteredSongs.dropFirst(max(visibleCount - 5, 0)).first?.id { visibleCount += 30 } }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Peça sua música")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Música, artista ou álbum")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .task { await loadSongs() }
            .alert("Pedido musical", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: { Text(alertMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private func loadSongs() async {
        defer { isLoading = false }
        songs = (try? await AzuraCastAPI.shared.requestableSongs()) ?? []
    }

    private func request(_ item: RequestableSong) async {
        sendingID = item.id
        defer { sendingID = nil }
        do {
            alertMessage = try await AzuraCastAPI.shared.requestSong(item.requestID)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct PodcastsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var podcasts: [Podcast] = []
    @State private var selected: Podcast?
    @State private var episodes: [PodcastEpisode] = []
    @State private var player = PodcastAudioPlayer()
    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    List(episodes) { episode in
                        Button { if let url = episode.links.download { player.play(url) } } label: {
                            Label(episode.title, systemImage: player.url == episode.links.download ? "pause.circle.fill" : "play.circle")
                        }
                    }
                } else if podcasts.isEmpty { ContentUnavailableView("Podcasts indisponíveis", systemImage: "mic.slash", description: Text("Nenhum podcast publicado no momento.")) }
                else { List(podcasts) { podcast in Button { selected = podcast; Task { episodes = (try? await AzuraCastAPI.shared.podcastEpisodes(podcast.id)) ?? [] } } label: { Label(podcast.title, systemImage: "mic.fill") } } }
            }
            .navigationTitle(selected?.title ?? "Podcasts")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }; if selected != nil { ToolbarItem(placement: .topBarLeading) { Button("Podcasts") { selected = nil } } } }
            .task { podcasts = (try? await AzuraCastAPI.shared.podcasts()) ?? [] }
        }.preferredColorScheme(.dark)
    }
}

@Observable private final class PodcastAudioPlayer {
    private var avPlayer: AVPlayer?
    var url: URL?
    func play(_ url: URL) { if self.url == url { avPlayer?.pause(); self.url = nil } else { self.url = url; avPlayer = AVPlayer(url: url); avPlayer?.play() } }
}
