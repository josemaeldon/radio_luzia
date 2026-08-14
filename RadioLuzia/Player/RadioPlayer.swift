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
    private var interruptionObservation: NSObjectProtocol?
    private var activeStreamURL: URL?
    private var started = false
    private var shouldResumeAfterInterruption = false
    private var currentArtworkSongID: String?

    var currentTrack: PlayingTrack? { nowPlaying?.nowPlaying }
    var isPlaying: Bool { state == .playing || state == .connecting }
    var selectedMount: Mount? {
        guard let mounts = nowPlaying?.station.mounts else { return nil }
        return mounts.first(where: { $0.id == selectedMountID })
            ?? mounts.first(where: \.isDefault)
            ?? mounts.first
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
        guard nowPlaying?.isOnline != false else {
            errorMessage = "A rádio está fora do ar neste momento."
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Não foi possível ativar o áudio."
        }

        let url = selectedMount?.url ?? nowPlaying?.station.listenURL
            ?? URL(string: "https://webradio.cloudbr.app/listen/santaluziapgm/192")!
        if activeStreamURL != url || player.currentItem == nil {
            activeStreamURL = url
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4
            player.replaceCurrentItem(with: item)
        }
        state = .connecting
        player.play()
        updateNowPlayingCenter()
    }

    func pause() {
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
        let songChanged = currentTrack?.song.id != model.nowPlaying.song.id
        nowPlaying = model
        lastMetadataUpdate = Date()
        if selectedMountID == nil {
            let saved = UserDefaults.standard.integer(forKey: "selectedMountID")
            selectedMountID = model.station.mounts.contains(where: { $0.id == saved })
                ? saved
                : model.station.mounts.first(where: \.isDefault)?.id
        }
        if songChanged { currentArtworkSongID = nil }
        updateNowPlayingCenter()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
        } catch {
            state = .failed("Não foi possível preparar o áudio.")
        }
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
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
            Task { @MainActor [weak self] in self?.state = .failed(message) }
        }

        interruptionObservation = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let rawType else { return }
                self?.handleInterruption(type: rawType, options: rawOptions)
            }
        }
    }

    private func handleInterruption(type rawType: UInt, options rawOptions: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            pause()
        case .ended:
            if shouldResumeAfterInterruption,
               AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) { play() }
        @unknown default: break
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
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1 : 0,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed()
        ]
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
