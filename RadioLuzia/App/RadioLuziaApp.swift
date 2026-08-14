import SwiftUI

@main
struct RadioLuziaApp: App {
    @State private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .environment(player)
                .preferredColorScheme(.dark)
                .task { await player.start() }
        }
    }
}

