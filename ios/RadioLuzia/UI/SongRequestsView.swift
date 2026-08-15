import SwiftUI
import AVFoundation
import Observation
import MediaPlayer

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
    @Environment(RadioPlayer.self) private var radioPlayer
    @State private var podcasts: [Podcast] = []
    @State private var selected: Podcast?
    @State private var episodes: [PodcastEpisode] = []
    @State private var player = PodcastAudioPlayer()
    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    List(episodes) { episode in
                        Button {
                            if let url = episode.links.download {
                                radioPlayer.pause()
                                player.play(url, title: episode.title)
                            }
                        } label: {
                            Label(episode.title, systemImage: player.url == episode.links.download && player.isPlaying ? "pause.circle.fill" : "play.circle")
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
    private static let nowPlayingAlbum = "Rádio Santa Luzia • Podcasts"
    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    var url: URL?
    var title = "Podcast"
    var isPlaying = false
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    func play(_ url: URL, title: String) {
        if self.url == url {
            if isPlaying { pause() } else { avPlayer?.play(); isPlaying = true; updateNowPlaying() }
            return
        }
        self.url = url
        self.title = title
        avPlayer?.pause()
        avPlayer = AVPlayer(url: url)
        avPlayer?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        addProgressObserver()
        try? AVAudioSession.sharedInstance().setActive(true)
        avPlayer?.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func pause() {
        avPlayer?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    private func configureAudioSession() {
        #if targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #else
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
        #endif
    }

    private func addProgressObserver() {
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
        timeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            elapsed = time.seconds.isFinite ? time.seconds : 0
            duration = self.avPlayer?.currentItem?.duration.seconds.isFinite == true ? self.avPlayer?.currentItem?.duration.seconds ?? 0 : 0
            updateNowPlaying()
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.avPlayer?.play(); self?.isPlaying = true; self?.updateNowPlaying(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if isPlaying { pause() } else { avPlayer?.play(); isPlaying = true; updateNowPlaying() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            avPlayer?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
            elapsed = event.positionTime
            updateNowPlaying()
            return .success
        }
    }

    private func updateNowPlaying() {
        guard url != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: Self.nowPlayingAlbum,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    deinit {
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
    }
}
