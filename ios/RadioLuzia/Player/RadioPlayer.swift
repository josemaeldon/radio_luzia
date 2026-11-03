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
            case .idle: "Pronto para ouvir"
            case .connecting: "Conectando ao áudio…"
            case .playing: "Reproduzindo áudio"
            case .paused: "Áudio pausado"
            case .failed: "Conteúdo indisponível"
            }
        }
    }
    struct EpisodeSelection: Equatable, Sendable {
        let podcastID: String
        let episodeID: String
    }
    private(set) var nowPlaying: NowPlaying?
    private(set) var selectedEpisode: PodcastEpisode?
    private(set) var episodeSelection: EpisodeSelection?
    private(set) var primaryEpisodeID: String?
    private(set) var selectedMountID: Int?
    private(set) var state: PlaybackState = .idle
    var errorMessage: String?
    private let api: AzuraCastAPI
    private let player = AVPlayer()
    private var activeURL: URL?
    private var selectedArtwork: URL?
    private var loadedArtwork: URL?
    private var started = false
    private var wantsPlayback = false
    private var resumeAfterInterruption = false
    private var requestVersion = 0
    private var playbackVersion = 0
    private var playbackTask: Task<Bool, Never>?
    private var refreshTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var observers: [NSObjectProtocol] = []

    var currentTrack: PlayingTrack? { nowPlaying?.nowPlaying }
    var selectedMount: Mount? { nowPlaying?.station.preferredMount }
    var primaryPlaybackItem: PrimaryPlaybackItem? { nowPlaying?.playback?.item(currentID: primaryEpisodeID) }
    var primaryPlaybackTitle: String { selectedEpisode?.title ?? primaryPlaybackItem?.title ?? currentTrack?.song.displayTitle ?? "Conteúdo principal" }
    var primaryPlaybackURL: URL? {
        if episodeSelection != nil { return selectedEpisode?.links.download }
        return primaryPlaybackItem?.url ?? selectedMount?.url ?? nowPlaying?.station.listenURL
    }
    var artworkURL: URL? {
        episodeSelection != nil ? (selectedEpisode?.art ?? selectedArtwork) : currentTrack?.song.art
    }
    var hasPlayableContent: Bool { primaryPlaybackURL != nil }
    var isEpisodeSelected: Bool { episodeSelection != nil }
    var isPlaying: Bool { state == .playing || state == .connecting }
    var playbackDuration: TimeInterval {
        let duration = player.currentItem?.duration.seconds ?? 0
        return duration.isFinite && duration > 0 ? duration : 0
    }

    init(api: AzuraCastAPI = .shared) {
        self.api = api
        configureAudioSession()
        configureObservation()
        configureNotifications()
        configureRemoteCommands()
    }

    func start() async {
        guard !started else { return }
        started = true
        await refreshMetadata(showError: false)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled && self != nil {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if self?.playbackTask == nil { await self?.refreshMetadata(showError: false) }
            }
        }
    }

    // This object belongs to the app, not to the catalog sheet. Dismissing the
    // sheet or locking the device never releases its AVPlayer or selection.
    @discardableResult
    func selectEpisode(episodeID: String, podcastID: String, artworkURL: URL? = nil, autoplay: Bool = true) async -> Bool {
        let selection = EpisodeSelection(podcastID: podcastID, episodeID: episodeID)
        if episodeSelection == selection && selectedEpisode != nil {
            if autoplay && isPlaying { return true }
            return await beginPlayback(autoplay: autoplay).value
        }
        pause()
        requestVersion += 1
        resetMediaItem()
        nowPlaying = nil
        selectedEpisode = nil
        primaryEpisodeID = nil
        episodeSelection = selection
        selectedArtwork = artworkURL
        return await beginPlayback(autoplay: autoplay).value
    }

    func playPrimary() {
        pause()
        requestVersion += 1
        resetMediaItem()
        episodeSelection = nil
        selectedEpisode = nil
        selectedArtwork = nil
        nowPlaying = nil
        primaryEpisodeID = nil
        play()
    }
    func play() { _ = beginPlayback() }
    func togglePlayback() { isPlaying ? pause() : play() }
    func pause() {
        playbackVersion += 1
        playbackTask?.cancel()
        playbackTask = nil
        wantsPlayback = false
        resumeAfterInterruption = false
        player.pause()
        state = .paused
        updateNowPlayingCenter()
    }
    func retry() { resetMediaItem(); play() }
    func selectMount(_ mount: Mount) {
        guard mount.id == selectedMount?.id else { return }
        selectedMountID = mount.id
    }

    private func beginPlayback(autoplay: Bool = true, advancing: Bool = false) -> Task<Bool, Never> {
        playbackTask?.cancel()
        playbackVersion += 1
        let version = playbackVersion
        let previousContent = nowPlaying?.playback?.contentId
        let endedID = primaryEpisodeID
        wantsPlayback = autoplay
        state = .connecting
        let task = Task { [weak self] in
            guard let self else { return false }
            defer { if version == playbackVersion { playbackTask = nil } }
            guard await refreshMetadata(showError: true), !Task.isCancelled, version == playbackVersion else { return false }
            if advancing, episodeSelection == nil, let queue = nowPlaying?.playback,
               queue.contentId == previousContent, let next = queue.item(currentID: endedID, advancing: true) {
                primaryEpisodeID = next.id
                resetMediaItem()
            }
            if autoplay && wantsPlayback { return activateAndPlay() }
            state = .paused
            updateNowPlayingCenter()
            return true
        }
        playbackTask = task
        return task
    }

    @discardableResult
    func refreshMetadata(showError: Bool = true) async -> Bool {
        requestVersion += 1
        let version = requestVersion
        let source = episodeSelection
        let oldURL = activeURL
        do {
            if let source {
                let episode = try await api.publishedEpisode(source.episodeID, podcastID: source.podcastID)
                guard !Task.isCancelled, version == requestVersion, episodeSelection == source else { return false }
                selectedEpisode = episode
            } else {
                let model = try await api.nowPlaying()
                guard !Task.isCancelled, version == requestVersion, episodeSelection == nil else { return false }
                let previousContent = nowPlaying?.playback?.contentId
                let previousEpisode = primaryEpisodeID
                nowPlaying = model
                primaryEpisodeID = model.playback?.item(currentID: previousContent == model.playback?.contentId ? previousEpisode : nil)?.id
                selectedMountID = model.station.preferredMount?.id
            }
            if oldURL != nil && oldURL != primaryPlaybackURL {
                resetMediaItem()
                if wantsPlayback && playbackTask == nil { _ = activateAndPlay() }
            }
            errorMessage = nil
            updateNowPlayingCenter()
            return true
        } catch {
            guard !Task.isCancelled, version == requestVersion, episodeSelection == source else { return false }
            pause()
            resetMediaItem()
            nowPlaying = nil
            selectedEpisode = nil
            selectedMountID = nil
            primaryEpisodeID = nil
            state = .failed("O conteúdo publicado não está disponível.")
            if showError { errorMessage = "Não foi possível carregar este conteúdo publicado." }
            return false
        }
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }
    func progress(at date: Date = Date()) -> Double {
        playbackDuration > 0 ? min(1, elapsed() / playbackDuration) : 0
    }
    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, playbackDuration > 0 else { return }
        player.seek(to: CMTime(seconds: min(max(0, seconds), playbackDuration), preferredTimescale: 600))
        updateNowPlayingCenter()
    }

    private func resetMediaItem() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        activeURL = nil
        loadedArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    private func configureAudioSession() {
        do {
#if targetEnvironment(simulator)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
#else
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
#endif
        } catch { errorMessage = "Não foi possível preparar a saída de áudio." }
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }
    @discardableResult
    private func activateAndPlay() -> Bool {
        guard let url = primaryPlaybackURL else { return false }
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch { state = .failed("Não foi possível ativar o áudio."); errorMessage = state.label; return false }
        if activeURL != url || player.currentItem == nil || player.currentItem?.status == .failed {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4
            player.replaceCurrentItem(with: item)
            activeURL = url
        } else if playbackDuration > 0 && elapsed() >= playbackDuration - 0.05 {
            player.seek(to: .zero)
        }
        state = .connecting
        player.play()
        updateNowPlayingCenter()
        return true
    }

    private func configureObservation() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing: state = .playing
                case .waitingToPlayAtSpecifiedRate: state = .connecting
                case .paused:
                    if case .failed = state { break }
                    if state != .idle && playbackTask == nil { state = .paused }
                @unknown default: break
                }
                updateNowPlayingCenter()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateNowPlayingCenter() }
        }
    }
    private func configureNotifications() {
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, let current = player.currentItem, ObjectIdentifier(current) == id else { return }
                if episodeSelection == nil && nowPlaying?.playback?.loop == true && wantsPlayback { _ = beginPlayback(advancing: true) }
                else { wantsPlayback = false; state = .paused; updateNowPlayingCenter() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, let current = player.currentItem, ObjectIdentifier(current) == id else { return }
                pause()
                state = .failed("A reprodução foi interrompida.")
                errorMessage = "Não foi possível continuar o áudio. Tente reproduzir novamente."
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                if interruption == .began {
                    resumeAfterInterruption = wantsPlayback
                    player.pause(); state = .paused; updateNowPlayingCenter()
                } else if resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    resumeAfterInterruption = false
                    play()
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in guard let self else { return }; configureAudioSession(); if wantsPlayback { resetMediaItem(); play() } }
        })
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlayback() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in self?.seek(to: seconds) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in if let self { self.seek(to: self.elapsed() + 15) } }; return .success }
        center.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in if let self { self.seek(to: self.elapsed() - 15) } }; return .success }
    }
    private func updateNowPlayingCenter() {
        guard let url = primaryPlaybackURL else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: primaryPlaybackTitle,
            MPMediaItemPropertyArtist: "Luzia Player",
            MPNowPlayingInfoPropertyExternalContentIdentifier: url.absoluteString,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed(),
            MPNowPlayingInfoPropertyPlaybackRate: player.timeControlStatus == .playing ? 1.0 : 0.0,
        ]
        if playbackDuration > 0 { info[MPMediaItemPropertyPlaybackDuration] = playbackDuration }
        if episodeSelection != nil { info[MPMediaItemPropertyAlbumTitle] = "Luzia Player • Conteúdos"; info[MPMediaItemPropertyMediaType] = NSNumber(value: MPMediaType.podcast.rawValue) }
        if let artwork = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        let canSeek = playbackDuration > 0
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = canSeek
        MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled = canSeek
        MPRemoteCommandCenter.shared().skipBackwardCommand.isEnabled = canSeek
        guard let art = artworkURL, loadedArtwork != art else { return }
        loadedArtwork = art
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: art), let image = UIImage(data: data),
                  let self, primaryPlaybackURL == url, artworkURL == art else { return }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }
}
