import SwiftUI

struct PlayerView: View {
    @Environment(RadioPlayer.self) private var player
    @State private var showDetails = false
    @State private var showRequests = false
    @State private var showQuality = false

    var body: some View {
        @Bindable var player = player
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(spacing: 26) {
                        stationHeader
                        nowPlayingSection
                        if let model = player.nowPlaying {
                            playbackControls(model)
                            if let next = model.playingNext { upNext(next) }
                            history(model.songHistory)
                        } else {
                            loadingCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .refreshable { await player.refreshMetadata() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDetails = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Detalhes da rádio")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if player.nowPlaying?.station.requestsEnabled == true {
                        Button { showRequests = true } label: { Image(systemName: "music.note.list") }
                            .accessibilityLabel("Pedir música")
                    }
                    Button { showQuality = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Qualidade da transmissão")
                }
            }
            .sheet(isPresented: $showDetails) { StationDetailsView() }
            .sheet(isPresented: $showRequests) { SongRequestsView() }
            .sheet(isPresented: $showQuality) { QualityPickerView() }
            .alert("Rádio Santa Luzia", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
        .tint(RadioTheme.gold)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.012, blue: 0.05), RadioTheme.plum, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(RadioTheme.wine.opacity(0.65))
                .frame(width: 330, height: 330)
                .blur(radius: 75)
                .offset(x: 140, y: -270)
            Circle()
                .fill(RadioTheme.gold.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -170, y: 260)
        }
        .ignoresSafeArea()
    }

    private var stationHeader: some View {
        VStack(spacing: 8) {
            Text(player.nowPlaying?.station.name.uppercased() ?? "PARÓQUIA SANTA LUZIA")
                .font(.caption.weight(.bold))
                .tracking(2.1)
                .foregroundStyle(RadioTheme.cream.opacity(0.84))
            HStack(spacing: 7) {
                Circle()
                    .fill(player.nowPlaying?.isOnline == true ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: player.nowPlaying?.isOnline == true ? .green : .orange, radius: 5)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
    }

    private var statusText: String {
        if let live = player.nowPlaying?.live, live.isLive {
            return live.streamerName.isEmpty ? "Programa ao vivo" : "Ao vivo com \(live.streamerName)"
        }
        return player.nowPlaying?.isOnline == true ? "No ar agora" : "Verificando sinal…"
    }

    private var nowPlayingSection: some View {
        VStack(spacing: 23) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, 340)
                HStack {
                    Spacer()
                    ArtworkView(url: player.currentTrack?.song.art, size: side)
                        .id(player.currentTrack?.song.id)
                    Spacer()
                }
            }
            .frame(height: min(UIScreen.main.bounds.width - 40, 340))

            VStack(spacing: 7) {
                Text(player.currentTrack?.song.displayTitle ?? "Rádio Santa Luzia")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(.numericText())
                Text(player.currentTrack?.song.displayArtist ?? "A luz que toca você")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let album = player.currentTrack?.song.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(RadioTheme.gold.opacity(0.78))
                        .lineLimit(1)
                }
            }
            .animation(.easeInOut, value: player.currentTrack?.song.id)
        }
    }

    private func playbackControls(_ model: NowPlaying) -> some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    ProgressView(value: player.progress(at: context.date))
                        .tint(RadioTheme.gold)
                        .animation(.linear(duration: 1), value: player.progress(at: context.date))
                    HStack {
                        Text(formatTime(player.elapsed(at: context.date)))
                        Spacer()
                        Text("-\(formatTime(max((player.currentTrack?.duration ?? 0) - player.elapsed(at: context.date), 0)))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
                }
            }

            HStack(spacing: 26) {
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .padding(4)
                    .roundGlassControl()
                    .accessibilityLabel("Escolher saída de áudio")

                Button(action: player.togglePlayback) {
                    ZStack {
                        Circle().fill(RadioTheme.gold)
                        if player.state == .connecting {
                            ProgressView().tint(RadioTheme.plum)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(RadioTheme.plum)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .frame(width: 78, height: 78)
                    .shadow(color: RadioTheme.gold.opacity(0.28), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pausar rádio" : "Ouvir rádio")

                ShareLink(
                    item: model.station.publicPlayerURL ?? model.station.listenURL,
                    subject: Text(model.station.name),
                    message: Text("Ouça \(model.station.name) comigo.")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .padding(4)
                        .roundGlassControl()
                }
                .accessibilityLabel("Compartilhar rádio")
            }

            HStack(spacing: 11) {
                Image(systemName: "speaker.fill")
                    .font(.caption2.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { player.volume },
                        set: { player.volume = $0 }
                    ),
                    in: 0...1
                )
                    .tint(.white.opacity(0.76))
                    .controlSize(.small)
                    .accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 3)

            HStack(spacing: 6) {
                Image(systemName: stateIcon)
                Text(player.state.label)
                if let mount = player.selectedMount {
                    Text("• \(mount.bitrate) kbps")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(22)
        .glassCard()
    }

    private var stateIcon: String {
        switch player.state {
        case .playing: "waveform"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        default: "pause.circle"
        }
    }

    private func upNext(_ track: PlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("A SEGUIR", systemImage: "forward.fill")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(RadioTheme.gold)
            TrackRow(track: track, showsTime: false)
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private func history(_ tracks: [PlayingTrack]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TOCOU RECENTEMENT", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.7))
            ForEach(Array(tracks.prefix(5).enumerated()), id: \.element.id) { index, track in
                TrackRow(track: track, showsTime: true)
                if index < min(tracks.count, 5) - 1 { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(RadioTheme.gold)
            Text("Sintonizando a programação…").foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard()
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let seconds = max(Int(interval), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TrackRow: View {
    let track: PlayingTrack
    let showsTime: Bool

    var body: some View {
        HStack(spacing: 13) {
            AsyncImage(url: track.song.art) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    RadioTheme.wine
                    Image(systemName: "music.note").foregroundStyle(RadioTheme.gold)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.song.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(track.song.displayArtist).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsTime, let playedAt = track.playedAt {
                Text(Date(timeIntervalSince1970: TimeInterval(playedAt)), style: .time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            } else if track.isRequest {
                Image(systemName: "person.wave.2.fill").foregroundStyle(RadioTheme.gold)
            }
        }
    }
}
