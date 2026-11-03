import SwiftUI

struct StationDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RadioPlayer.self) private var player
    @State private var links: [AzuraCastAPI.ManagedContent] = []

    var body: some View {
        NavigationStack {
            List {
                if player.hasPlayableContent {
                    Section(player.isEpisodeSelected ? "Episódio selecionado" : "Conteúdo principal") {
                        LabeledContent("Título", value: player.primaryPlaybackTitle)
                        if let description = player.nowPlaying?.station.description, !description.isEmpty { Text(description) }
                    }
                }
                if !links.isEmpty {
                    Section("Links publicados") {
                        ForEach(links) { content in Link(content.title, destination: content.url) }
                    }
                }
                Section("Reprodução") {
                    Label("Áudio em segundo plano", systemImage: "waveform")
                    Label("Controles na tela bloqueada", systemImage: "lock.iphone")
                    Label("Saída de áudio por AirPlay", systemImage: "airplay.audio")
                }
            }
            .navigationTitle("Sobre o conteúdo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .task { links = ((try? await AzuraCastAPI.shared.managedContents()) ?? []).filter { $0.type == "public_page" || $0.type == "podcast_feed" } }
        .preferredColorScheme(.dark)
    }
}
