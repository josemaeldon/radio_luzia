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
                            if episode.links.download != nil {
                                radioPlayer.pause()
                                player.play(episodeID: episode.id, podcastID: selected.id, art: episode.art ?? selected.art)
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
            .task {
                while !Task.isCancelled {
                    podcasts = (try? await AzuraCastAPI.shared.podcasts()) ?? []
                    if let selected {
                        episodes = (try? await AzuraCastAPI.shared.podcastEpisodes(selected.id)) ?? []
                    }
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
        }.preferredColorScheme(.dark)
    }
}

@Observable private final class PodcastAudioPlayer: @unchecked Sendable {
    private static let nowPlayingAlbum = "Rádio Santa Luzia • Podcasts"
    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var primaryObserver: NSObjectProtocol?
    private var episodeID: String?
    private var podcastID: String?
    private var publicationVersion = 0
    private var validationTask: Task<Void, Never>?
    private var publicationTask: Task<Void, Never>?
    var url: URL?
    var title = "Podcast"
    var artworkURL: URL?
    var isPlaying = false
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0

    init() {
        configureAudioSession()
        configureRemoteCommands()
        primaryObserver = NotificationCenter.default.addObserver(forName: .primaryPlaybackRequested, object: nil, queue: .main) { [weak self] _ in
            if self?.episodeID != nil { self?.stopUnpublished() }
        }
        publicationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled && self != nil {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                await self?.verifyPublication()
            }
        }
    }

    deinit {
        validationTask?.cancel()
        publicationTask?.cancel()
        if let primaryObserver { NotificationCenter.default.removeObserver(primaryObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver) }
        avPlayer?.pause()
    }

    func play(episodeID: String, podcastID: String, art: URL?) {
        if self.episodeID == episodeID && self.podcastID == podcastID && isPlaying { pause(); return }
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.artworkURL = art
        resumePublished()
    }

    private func resumePublished() {
        validationTask?.cancel()
        publicationVersion += 1
        let version = publicationVersion
        validationTask = Task { @MainActor [weak self] in
            guard let self, let id = episodeID, let podcast = podcastID else { return }
            defer { if version == publicationVersion { validationTask = nil } }
            do {
                let episode = try await AzuraCastAPI.shared.publishedEpisode(id, podcastID: podcast)
                guard !Task.isCancelled, id == episodeID, podcast == podcastID, version == publicationVersion else { return }
                guard let url = episode.links.download else { stopUnpublished(); return }
                startValidatedURL(url, title: episode.title, art: artworkURL)
            } catch { if !Task.isCancelled { stopUnpublished() } }
        }
    }

    private func verifyPublication() async {
        guard let id = episodeID, let podcast = podcastID, validationTask?.isCancelled != false else { return }
        let version = publicationVersion
        do {
            let episode = try await AzuraCastAPI.shared.publishedEpisode(id, podcastID: podcast)
            guard version == publicationVersion, id == episodeID, podcast == podcastID else { return }
            guard let publishedURL = episode.links.download else { stopUnpublished(); return }
            if publishedURL != url {
                if isPlaying { startValidatedURL(publishedURL, title: episode.title, art: artworkURL) }
                else { avPlayer?.replaceCurrentItem(with: nil); url = publishedURL }
            }
            title = episode.title
            updateNowPlaying()
        } catch { if !Task.isCancelled && version == publicationVersion { stopUnpublished() } }
    }

    private func stopUnpublished() {
        publicationVersion += 1
        validationTask?.cancel()
        validationTask = nil
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        isPlaying = false
        url = nil
        episodeID = nil
        podcastID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func startValidatedURL(_ url: URL, title: String, art: URL?) {
        if self.url == url && avPlayer?.currentItem != nil {
            self.title = title
            avPlayer?.play()
            isPlaying = true
            updateNowPlaying()
            return
        }
        self.url = url
        self.title = title
        self.artworkURL = art
        avPlayer?.pause()
        if let timeObserver { avPlayer?.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        avPlayer = AVPlayer(url: url)
        avPlayer?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        addProgressObserver()
        observeItem()
        #if !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        avPlayer?.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func pause() {
        publicationVersion += 1
        validationTask?.cancel()
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
        timeObserver = avPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: nil) { [weak self] time in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                elapsed = time.seconds.isFinite ? time.seconds : 0
                duration = self.avPlayer?.currentItem?.duration.seconds.isFinite == true ? self.avPlayer?.currentItem?.duration.seconds ?? 0 : 0
                updateNowPlaying()
            }
        }
    }

    private func observeItem() {
        itemStatusObservation = avPlayer?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in self?.updateNowPlaying() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer?.currentItem,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = false
                self?.updateNowPlaying()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.resumePublished()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if isPlaying { pause() } else { resumePublished() }
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                avPlayer?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                elapsed = position
                updateNowPlaying()
            }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.seek(by: 15) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.seek(by: -15) }
            return .success
        }
    }

    private func seek(by offset: TimeInterval) {
        guard let avPlayer else { return }
        let target = max(0, min((avPlayer.currentTime().seconds + offset), duration > 0 ? duration : .greatestFiniteMagnitude))
        avPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard url != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: Self.nowPlayingAlbum,
            MPMediaItemPropertyAlbumArtist: "Rádio Santa Luzia",
            MPMediaItemPropertyMediaType: NSNumber(value: MPMediaType.podcast.rawValue),
            MPNowPlayingInfoPropertyExternalContentIdentifier: url?.absoluteString ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = currentArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded()
    }

    private var currentArtwork: MPMediaItemArtwork? {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
    }

    private func loadArtworkIfNeeded() {
        guard let artworkURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data),
                  let self,
                  self.artworkURL == artworkURL else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }

}
