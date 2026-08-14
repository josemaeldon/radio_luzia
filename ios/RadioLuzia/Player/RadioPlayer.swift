import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class RadioPlayer {
    enum PlaybackState: Equatable {
        case idle, connecting, playing, paused, failed(String)

        var label: String {
            switch self {
            case .idle: "Pronta para ouvir"
            case .connecting: "Conectando ao vivo…"
            case .playing: "Transmitindo ao vivo"
            case .paused: "Transmissão pausada"
            case .failed: "Falha na conexão"
            }
        }
    }

    private(set) var nowPlaying: NowPlaying?
    private(set) var state: PlaybackState = .idle
    private(set) var lastMetadataUpdate = Date()
    private(set) var selectedMountID: Int?
    var errorMessage: String?

    private let api = AzuraCastAPI.shared
    private let socket = NowPlayingSocket()
    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?
    private var itemObservation: NSObjectProtocol?
    private var stalledObservation: NSObjectProtocol?
    private var interruptionObservation: NSObjectProtocol?
    private var activeStreamURL: URL?
    private var started = false
    private var wantsPlayback = false
    private var shouldResumeAfterInterruption = false
    private var interruptionResumeTask: Task<Void, Never>?
    private var currentArtworkSongID: String?
    private var pausedAt: Date?
    private let stalePauseThreshold: TimeInterval = 15
    private var lastAppliedPlayedAt: Int?
    private var lastAppliedElapsed: Double?

    var currentTrack: PlayingTrack? { nowPlaying?.nowPlaying }
    var isPlaying: Bool { state == .playing || state == .connecting }
    var selectedMount: Mount? {
        guard let mounts = nowPlaying?.station.mounts else { return nil }
        return mounts.first(where: { $0.id == selectedMountID })
            ?? nowPlaying?.station.preferredMount
    }

    init() {
        configureAudioSession()
        configurePlayerObservation()
        configureRemoteCommands()
        configureNotifications()
    }

    func start() async {
        guard !started else { return }
        started = true
        await refreshMetadata(showError: false)
        await socket.connect { [weak self] model in
            self?.apply(model)
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        wantsPlayback = true
        guard nowPlaying?.isOnline != false else {
            wantsPlayback = false
            errorMessage = "A rádio está fora do ar neste momento."
            return
        }
        interruptionResumeTask?.cancel()
        let recreateItem = pausedAt.map { Date().timeIntervalSince($0) >= stalePauseThreshold } ?? false
        pausedAt = nil
        if activateAndPlay(recreateItemIfNeeded: recreateItem) {
            schedulePlaybackRecovery()
        }
    }

    func pause() {
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
        Task { await refreshMetadata(showError: true) }
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

    func refreshMetadata(showError: Bool = true) async {
        do {
            apply(try await api.nowPlaying())
        } catch {
            if showError { errorMessage = "Não foi possível atualizar os dados da rádio." }
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

        let songChanged = currentTrack?.song.id != model.nowPlaying.song.id
        nowPlaying = model
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
        if selectedMountID == nil || !model.station.mounts.contains(where: { $0.id == selectedMountID }) {
            let saved = UserDefaults.standard.integer(forKey: "selectedMountID")
            selectedMountID = model.station.mounts.contains(where: { $0.id == saved })
                ? saved
                : model.station.preferredMount?.id
        }
        if songChanged { currentArtworkSongID = nil }
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
            state = .failed("Não foi possível preparar o áudio.")
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

        guard let url = selectedMount?.url ?? nowPlaying?.station.listenURL else {
            state = .failed("A qualidade do áudio ainda não está disponível.")
            errorMessage = "Aguarde a rádio carregar para iniciar a reprodução."
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

    private func configureNotifications() {
        itemObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                ?? "A transmissão foi interrompida."
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
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
    }

    private func updateNowPlayingCenter() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.song.displayTitle,
            MPMediaItemPropertyArtist: track.song.displayArtist,
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
}
