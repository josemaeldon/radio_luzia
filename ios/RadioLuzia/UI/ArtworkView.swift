import SwiftUI

struct ArtworkView: View {
    let url: URL?
    var size: CGFloat = 320

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.35))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill().transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .failure:
                placeholder
            case .empty:
                ZStack { placeholder; ProgressView().tint(.white.opacity(0.7)) }
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 30, y: 18)
        .accessibilityLabel("Capa da música")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [RadioTheme.wine, RadioTheme.plum], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("DefaultStationArtwork")
                .resizable()
                .scaledToFill()
                .shadow(color: RadioTheme.gold.opacity(0.2), radius: 16)
        }
    }
}
