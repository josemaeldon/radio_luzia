import AVFoundation
import MediaPlayer
import Observation
import UIKit

extension Notification.Name {
    static let primaryPlaybackRequested = Notification.Name("RadioLuziaPrimaryPlaybackRequested")
}

@MainActor
@Observable
final class RadioPlayer {
    enum PlaybackState: Equatable {
        case idle, connecting, playing, paused, failed(String)

        var label: String {
            switch self {
            case .idle: "Pronto para ouvir"
            case .connecting: "Conectando ao áudio…"
            case .playing: "Reproduzindo áudio"
            case .paused: "Áudio pausado"
            case .failed: "Falha na conexão"
            }
        }
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var state: PlaybackState = .idle
    private(set) var lastMetadataUpdate = Date()
    private(set) var primaryEpisodeID: String?
    private(set) var selectedMountID: Int?
    var errorMessage: String?

    private let api: AzuraCastAPI
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var endedObservation: NSObjectProtocol?
    private var itemObservation: NSObjectProtocol?
    private var stalledObservation: NSObjectProtocol?
    private var interruptionObservation: NSObjectProtocol?
    private var activeStreamURL: URL?
    private var playbackVersion = 0
    private var playbackRequest: Task<Void, Never>?
    private var metadataRequestID = 0
    private var managedRefreshTask: Task<Void, Never>?
    private var started = false
    private var wantsPlayback = false
    private var shouldResumeAfterInterruption = false
    private var interruptionResumeTask: Task<Void, Never>?
    private var currentArtworkSongID: String?
    private var pausedAt: Date?
    private let stalePauseThreshold: TimeInterval = 15
    private var lastAppliedPlayedAt: Int?
    private var lastAppliedElapsed: Double?

    var primaryPlaybackItem: PrimaryPlaybackItem? { nowPlaying?.playback?.item(currentID: primaryEpisodeID) }
    var primaryPlaybackTitle: String { primaryPlaybackItem?.title ?? currentTrack?.song.displayTitle ?? "Conteúdo principal" }
    var primaryPlaybackURL: URL? { primaryPlaybackItem?.url ?? selectedMount?.url ?? nowPlaying?.station.listenURL }
    var currentTrack: PlayingTrack? { nowPlaying?.nowPlaying }
    var isPlaying: Bool { state == .playing || state == .connecting }
    var selectedMount: Mount? {
        guard let mounts = nowPlaying?.station.mounts else { return nil }
        return mounts.first(where: { $0.id == selectedMountID })
            ?? nowPlaying?.station.preferredMount
    }

    init(api: AzuraCastAPI = .shared) {
        self.api = api
        configureAudioSession()
        configurePlayerObservation()
        configureRemoteCommands()
        configureNotifications()
    }

    func start() async {
        guard !started else { return }
        started = true
        await refreshMetadata(showError: false)
        managedRefreshTask = Task { [weak self] in
            while !Task.isCancelled && self != nil {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if self?.playbackRequest == nil { await self?.refreshMetadata(showError: false) }
            }
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        NotificationCenter.default.post(name: .primaryPlaybackRequested, object: nil)
        playbackRequest?.cancel()
        playbackVersion += 1
        let version = playbackVersion
        wantsPlayback = true
        state = .connecting
        playbackRequest = Task { [weak self] in
            guard let self else { return }
            defer { if version == playbackVersion { playbackRequest = nil } }
            guard await refreshMetadata(showError: true) else { return }
            guard !Task.isCancelled, wantsPlayback, nowPlaying != nil else { return }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            interruptionResumeTask?.cancel()
            let recreateItem = pausedAt.map { Date().timeIntervalSince($0) >= stalePauseThreshold } ?? false
            pausedAt = nil
            if activateAndPlay(recreateItemIfNeeded: recreateItem) { schedulePlaybackRecovery() }
        }
    }

    func pause() {
        playbackVersion += 1
        playbackRequest?.cancel()
        playbackRequest = nil
        wantsPlayback = false
        shouldResumeAfterInterruption = false
        interruptionResumeTask?.cancel()
        pausedAt = Date()
        player.pause()
        state = .paused
        updateNowPlayingCenter()
    }

    func retry() {
        player.replaceCurrentItem(with: nil)
        activeStreamURL = nil
        play()
    }

    func selectMount(_ mount: Mount) {
        guard selectedMountID != mount.id else { return }
        let resume = isPlaying
        selectedMountID = mount.id
        UserDefaults.standard.set(mount.id, forKey: "selectedMountID")
        activeStreamURL = nil
        player.replaceCurrentItem(with: nil)
        if resume { play() }
    }

    @discardableResult
    func refreshMetadata(showError: Bool = true) async -> Bool {
        metadataRequestID += 1
        let requestID = metadataRequestID
        do {
            let model = try await api.nowPlaying()
            guard !Task.isCancelled, requestID == metadataRequestID else { return false }
            apply(model)
            return true
        } catch {
            guard !Task.isCancelled, requestID == metadataRequestID else { return false }
            pause()
            player.replaceCurrentItem(with: nil)
            activeStreamURL = nil
            nowPlaying = nil
            selectedMountID = nil
            primaryEpisodeID = nil
            if !Self.isPodcastNowPlaying { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
            state = .failed("Nenhum áudio publicado disponível.")
            if showError { errorMessage = "Não foi possível carregar o áudio publicado na API." }
            return false
        }
    }

    func progress(at date: Date = Date()) -> Double {
        guard let track = currentTrack, track.duration > 0 else { return 0 }
        let syncedElapsed = track.elapsed ?? 0
        let advancing = max(0, date.timeIntervalSince(lastMetadataUpdate))
        return min(max((syncedElapsed + advancing) / track.duration, 0), 1)
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let track = currentTrack else { return 0 }
        return min((track.elapsed ?? 0) + max(0, date.timeIntervalSince(lastMetadataUpdate)), track.duration)
    }

    private func apply(_ model: NowPlaying) {
        // The websocket can replay publications after reconnecting. Do not let
        // an older publication move the title backwards while the stream is
        // already playing a newer song.
        if let incomingPlayedAt = model.nowPlaying.playedAt,
           let currentPlayedAt = lastAppliedPlayedAt,
           incomingPlayedAt < currentPlayedAt {
            return
        }
        if let incomingPlayedAt = model.nowPlaying.playedAt,
           let currentPlayedAt = lastAppliedPlayedAt,
           incomingPlayedAt == currentPlayedAt,
           let incomingElapsed = model.nowPlaying.elapsed,
           let currentElapsed = lastAppliedElapsed,
           incomingElapsed < currentElapsed {
            return
        }

        let previousURL = activeStreamURL
        let songChanged = currentTrack?.song.id != model.nowPlaying.song.id
        let previousContentID = nowPlaying?.playback?.contentId
        let previousEpisodeID = primaryEpisodeID
        nowPlaying = model
        primaryEpisodeID = model.playback?.item(currentID: previousContentID == model.playback?.contentId ? previousEpisodeID : nil)?.id
        lastAppliedPlayedAt = model.nowPlaying.playedAt
        lastAppliedElapsed = model.nowPlaying.elapsed
        if let playedAt = model.nowPlaying.playedAt,
           let elapsed = model.nowPlaying.elapsed {
            // Anchor the progress to the server timeline instead of the
            // moment a websocket packet happened to arrive on this device.
            lastMetadataUpdate = Date(timeIntervalSince1970: Double(playedAt) + elapsed)
        } else {
            lastMetadataUpdate = Date()
        }
        selectedMountID = model.station.preferredMount?.id
        if previousURL != nil && previousURL != primaryPlaybackURL {
            player.replaceCurrentItem(with: nil)
            activeStreamURL = nil
            if wantsPlayback && activateAndPlay() { schedulePlaybackRecovery() }
        }
        if songChanged { currentArtworkSongID = nil }
        errorMessage = nil
        updateNowPlayingCenter()
    }

    private func configureAudioSession() {
        do {
#if targetEnvironment(simulator)
            // The simulator does not expose a real AirPlay route and may log
            // SessionCore badParam (-50) when this option is requested.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
#else
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
#endif
        } catch {
            // A sessão de áudio pode não aceitar a configuração durante a
            // inicialização (especialmente no simulador). Isso não significa
            // que o áudio falhou: a sessão só precisa estar ativa quando o
            // usuário tocar em reproduzir.
        }
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    /// Activates the session and starts the existing item when possible. Keeping
    /// this in one place is important: CarPlay and the remote controls call the
    /// same path as the button in the app.
    @discardableResult
    private func activateAndPlay(recreateItemIfNeeded: Bool = false) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            state = .failed("Não foi possível ativar o áudio.")
            errorMessage = "Não foi possível ativar o áudio."
            updateNowPlayingCenter()
            return false
        }

        guard let url = primaryPlaybackURL else {
            state = .failed("O áudio ainda não está disponível.")
            errorMessage = "Aguarde o conteúdo carregar para iniciar a reprodução."
            updateNowPlayingCenter()
            return false
        }
        let itemNeedsRecreation = player.currentItem?.status == .failed
        if recreateItemIfNeeded || activeStreamURL != url || player.currentItem == nil || itemNeedsRecreation {
            activeStreamURL = url
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4
            player.replaceCurrentItem(with: item)
        }

        state = .connecting
        player.play()
        updateNowPlayingCenter()
        return true
    }

    private func configurePlayerObservation() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing: self.state = .playing
                case .waitingToPlayAtSpecifiedRate: self.state = .connecting
                case .paused where self.state != .idle: self.state = .paused
                default: break
                }
                self.updateNowPlayingCenter()
            }
        }
    }

    private func advancePrimaryEpisode() {
        guard wantsPlayback, let playback = nowPlaying?.playback, playback.loop else { return }
        let contentID = playback.contentId
        let endedID = primaryEpisodeID
        playbackRequest?.cancel()
        playbackVersion += 1
        let version = playbackVersion
        playbackRequest = Task { [weak self] in
            guard let self else { return }
            defer { if version == playbackVersion { playbackRequest = nil } }
            guard await refreshMetadata(showError: true), !Task.isCancelled, wantsPlayback,
                  let refreshed = nowPlaying?.playback, refreshed.contentId == contentID,
                  let next = refreshed.item(currentID: endedID, advancing: true) else { return }
            primaryEpisodeID = next.id
            activeStreamURL = nil
            player.replaceCurrentItem(with: nil)
            if activateAndPlay(recreateItemIfNeeded: true) { schedulePlaybackRecovery() }
        }
    }

    private func configureNotifications() {
        endedObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let endedID = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.player.currentItem, ObjectIdentifier(currentItem) == endedID else { return }
                self.advancePrimaryEpisode()
            }
        }

        itemObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                ?? "A reprodução foi interrompida."
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                self.state = .failed(message)
                if wasPlaying { self.scheduleReconnect() }
            }
        }

        stalledObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.scheduleReconnect()
            }
        }

        interruptionObservation = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let rawType else { return }
                self?.handleInterruption(type: rawType)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsPlayback else { return }
                self.configureAudioSession()
                self.scheduleSystemResume(recreateItem: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsPlayback else { return }
                self.scheduleSystemResume()
            }
        }
    }

    private func handleInterruption(type rawType: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            // AVPlayer can change to `.paused` before this notification is
            // delivered. Keep the user's playback intent separately so a
            // temporary interruption does not look like a manual pause.
            shouldResumeAfterInterruption = wantsPlayback
            player.pause()
            state = .paused
            updateNowPlayingCenter()
        case .ended:
            guard shouldResumeAfterInterruption else { return }
            shouldResumeAfterInterruption = false
            scheduleSystemResume()
        @unknown default: break
        }
    }

    private func scheduleSystemResume(recreateItem: Bool = false) {
        interruptionResumeTask?.cancel()
        interruptionResumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<8 {
                guard !Task.isCancelled, self.wantsPlayback else { return }
                await self.refreshMetadata(showError: false)
                guard !Task.isCancelled, self.wantsPlayback else { return }
                if self.activateAndPlay(recreateItemIfNeeded: recreateItem) {
                    self.schedulePlaybackRecovery()
                    return
                }
                if attempt < 7 { try? await Task.sleep(for: .milliseconds(400)) }
            }
            guard self.wantsPlayback else { return }
            self.state = .failed("Não foi possível retomar o áudio.")
            self.updateNowPlayingCenter()
        }
    }

    /// `AVPlayer.play()` can succeed while the item remains stuck in a
    /// waiting state after a long pause. Reopening the live stream gives the
    /// player a fresh connection instead of leaving the UI spinning forever.
    private func schedulePlaybackRecovery() {
        interruptionResumeTask?.cancel()
        interruptionResumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for attempt in 0..<3 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, self.wantsPlayback else { return }
                guard self.player.timeControlStatus != .playing else { return }
                _ = self.activateAndPlay(recreateItemIfNeeded: true)
                if attempt == 2 {
                    self.state = .failed("Não foi possível iniciar o áudio.")
                    self.updateNowPlayingCenter()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard wantsPlayback, state != .paused, state != .idle else { return }
        interruptionResumeTask?.cancel()
        interruptionResumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.state != .paused, self.state != .idle else { return }
            await self.refreshMetadata(showError: false)
            guard !Task.isCancelled, self.wantsPlayback else { return }
            self.state = .connecting
            self.activeStreamURL = nil
            self.player.replaceCurrentItem(with: nil)
            if self.activateAndPlay() {
                self.schedulePlaybackRecovery()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.playCommand.addTarget { [weak self] _ in
            guard !Self.isPodcastNowPlaying else { return .commandFailed }
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard !Self.isPodcastNowPlaying else { return .commandFailed }
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard !Self.isPodcastNowPlaying else { return .commandFailed }
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
    }

    private func updateNowPlayingCenter() {
        guard !Self.isPodcastNowPlaying else { return }
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: primaryPlaybackTitle,
            MPMediaItemPropertyArtist: "Luzia Player",
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1 : 0,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed()
        ]
        if nowPlaying?.live.isLive == true {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        if !track.song.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = track.song.album }
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let artURL = track.song.art, currentArtworkSongID != track.song.id else { return }
        currentArtworkSongID = track.song.id
        let expectedID = track.song.id
        Task {
            guard
                let (data, _) = try? await URLSession.shared.data(from: artURL),
                let image = UIImage(data: data),
                currentTrack?.song.id == expectedID
            else { return }
            let requestHandler: @Sendable (CGSize) -> UIImage = { _ in image }
            let artwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: requestHandler)
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    private static var isPodcastNowPlaying: Bool {
        (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyAlbumTitle] as? String)
            == "Luzia Player • Conteúdos"
    }
}
