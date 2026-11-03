import SwiftUI
import MediaPlayer

struct PlayerView: View {
    @Environment(RadioPlayer.self) private var player
    @State private var showDetails = false
    @State private var showContents = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.055, green: 0.012, blue: 0.05), RadioTheme.plum, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        ArtworkView(url: player.currentTrack?.song.art, size: min(UIScreen.main.bounds.width - 48, 320))
                        VStack(spacing: 10) {
                            Text(player.nowPlaying == nil ? "Seu player de áudio" : player.primaryPlaybackTitle)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                            Text(player.nowPlaying == nil ? "Escolha um áudio ou episódio no catálogo." : "Conteúdo principal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let model = player.nowPlaying { playbackControls(model) }
                        else { unavailableContent }
                        Button { showContents = true } label: {
                            Label("Ver conteúdos", systemImage: "headphones")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .refreshable { await player.refreshMetadata() }
            }
            .navigationTitle("Luzia Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDetails = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Sobre o conteúdo")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showContents = true } label: { Image(systemName: "headphones") }
                        .accessibilityLabel("Abrir conteúdos")
                }
            }
            .sheet(isPresented: $showDetails) { StationDetailsView() }
            .sheet(isPresented: $showContents) { PodcastsView() }
            .alert("Luzia Player", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
                Button("OK", role: .cancel) { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
        }
        .tint(RadioTheme.gold)
    }

    private var unavailableContent: some View {
        VStack(spacing: 12) {
            if player.state == .idle || player.state == .connecting {
                ProgressView()
                Text("Carregando conteúdo…")
            } else {
                Label("Nenhum áudio principal disponível", systemImage: "play.slash")
                Text("Os áudios e podcasts publicados aparecem no catálogo de conteúdos.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Atualizar") { Task { await player.refreshMetadata() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .glassCard()
    }

    private func playbackControls(_ model: NowPlaying) -> some View {
        VStack(spacing: 22) {
            HStack(spacing: 28) {
                AirPlayButton().frame(width: 44, height: 44).roundGlassControl()
                    .accessibilityLabel("Escolher saída de áudio")
                Button(action: player.togglePlayback) {
                    ZStack {
                        Circle().fill(RadioTheme.gold)
                        if player.state == .connecting { ProgressView().tint(RadioTheme.plum) }
                        else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(RadioTheme.plum)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .frame(width: 78, height: 78)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pausar áudio" : "Reproduzir áudio")
                ShareLink(item: player.primaryPlaybackURL ?? model.station.listenURL, subject: Text(player.primaryPlaybackTitle), message: Text("Ouça este conteúdo no Luzia Player.")) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).roundGlassControl()
                }
                .accessibilityLabel("Compartilhar conteúdo")
            }
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                SystemVolumeSlider().frame(height: 26).accessibilityLabel("Volume")
                Image(systemName: "speaker.wave.3.fill")
            }
            .foregroundStyle(.secondary)
            Text(player.state.label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .glassCard()
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> SystemVolumeControl {
        SystemVolumeControl()
    }

    func updateUIView(_ control: SystemVolumeControl, context: Context) {}
}

private final class SystemVolumeControl: UIView {
    private let visibleSlider = UISlider(frame: .zero)
    private let systemVolumeView = MPVolumeView(frame: .zero)
    private var outputVolumeObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
        observeSystemVolume()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
        observeSystemVolume()
    }

    private func configureView() {
        visibleSlider.translatesAutoresizingMaskIntoConstraints = false
        visibleSlider.minimumValue = 0
        visibleSlider.maximumValue = 1
        visibleSlider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.78)
        visibleSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.13)
        visibleSlider.thumbTintColor = .white
        visibleSlider.accessibilityLabel = "Volume do sistema"
        visibleSlider.accessibilityHint = "Também acompanha os botões físicos de volume"
        visibleSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)

        systemVolumeView.translatesAutoresizingMaskIntoConstraints = false
        systemVolumeView.showsVolumeSlider = true
        systemVolumeView.alpha = 0.001
        systemVolumeView.isUserInteractionEnabled = false

        addSubview(visibleSlider)
        addSubview(systemVolumeView)
        NSLayoutConstraint.activate([
            visibleSlider.leadingAnchor.constraint(equalTo: leadingAnchor),
            visibleSlider.trailingAnchor.constraint(equalTo: trailingAnchor),
            visibleSlider.centerYAnchor.constraint(equalTo: centerYAnchor),
            systemVolumeView.widthAnchor.constraint(equalToConstant: 1),
            systemVolumeView.heightAnchor.constraint(equalToConstant: 1),
            systemVolumeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            systemVolumeView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        visibleSlider.value = AVAudioSession.sharedInstance().outputVolume
    }

    private func observeSystemVolume() {
        outputVolumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) {
            [weak self] session, _ in
            DispatchQueue.main.async {
                guard let self, !self.visibleSlider.isTracking else { return }
                self.visibleSlider.setValue(session.outputVolume, animated: true)
            }
        }
    }

    @objc private func volumeChanged() {
        systemVolumeView.layoutIfNeeded()
        guard let systemSlider = findSlider(in: systemVolumeView) else { return }
        systemSlider.setValue(visibleSlider.value, animated: false)
        systemSlider.sendActions(for: .valueChanged)
    }

    private func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        return view.subviews.lazy.compactMap(findSlider(in:)).first
    }
}
