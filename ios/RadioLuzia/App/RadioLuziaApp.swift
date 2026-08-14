import SwiftUI

@main
struct RadioLuziaApp: App {
    @State private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            storePreviewRoot
                .environment(player)
                .preferredColorScheme(.dark)
                .task { await player.start() }
        }
    }

    @ViewBuilder
    private var storePreviewRoot: some View {
#if DEBUG
        switch ProcessInfo.processInfo.environment["STORE_PREVIEW"] {
        case "details": StationDetailsView()
        case "requests": SongRequestsView()
        default: PlayerView()
        }
#else
        PlayerView()
#endif
    }
}
