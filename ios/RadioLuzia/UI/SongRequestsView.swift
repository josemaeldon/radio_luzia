import SwiftUI

struct PodcastsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RadioPlayer.self) private var radioPlayer
    @State private var podcasts: [Podcast] = []
    @State private var selected: Podcast?
    @State private var episodes: [PodcastEpisode] = []
    @State private var selecting = false
    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    List(episodes) { episode in
                        Button {
                            if episode.links.download != nil {
                                selecting = true
                                Task {
                                    defer { selecting = false }
                                    if await radioPlayer.selectEpisode(episodeID: episode.id, podcastID: selected.id, artworkURL: episode.art ?? selected.art) { dismiss() }
                                }
                            }
                        } label: {
                            Label(episode.title, systemImage: radioPlayer.episodeSelection?.podcastID == selected.id && radioPlayer.episodeSelection?.episodeID == episode.id && radioPlayer.isPlaying ? "waveform" : "play.circle")
                        }
                        .disabled(selecting)
                    }
                } else if podcasts.isEmpty { ContentUnavailableView("Nenhum conteúdo publicado", systemImage: "mic.slash", description: Text("Os áudios e episódios publicados aparecerão aqui.")) }
                else { List(podcasts) { podcast in Button { selected = podcast; Task { episodes = (try? await AzuraCastAPI.shared.podcastEpisodes(podcast.id)) ?? [] } } label: { Label(podcast.title, systemImage: "mic.fill") } } }
            }
            .navigationTitle(selected?.title ?? "Conteúdos")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }; if selected != nil { ToolbarItem(placement: .topBarLeading) { Button("Conteúdos") { selected = nil } } } }
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
