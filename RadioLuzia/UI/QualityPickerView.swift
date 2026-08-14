import SwiftUI

struct QualityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(player.nowPlaying?.station.mounts ?? []) { mount in
                        Button {
                            player.selectMount(mount)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mount.name).foregroundStyle(.primary)
                                    Text("\(mount.format.uppercased()) • \(mount.bitrate) kbps")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if player.selectedMount?.id == mount.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RadioTheme.gold)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Uma qualidade menor economiza dados móveis. A troca mantém a programação ao vivo.")
                }
            }
            .navigationTitle("Qualidade do áudio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

