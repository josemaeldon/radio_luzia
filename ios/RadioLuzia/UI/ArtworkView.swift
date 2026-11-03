import SwiftUI

struct ArtworkView: View {
    var size: CGFloat = 320

    var body: some View {
        ZStack {
            LinearGradient(colors: [RadioTheme.wine, RadioTheme.plum], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("SantaLuziaLogo")
                .resizable()
                .scaledToFit()
                .padding(size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.34), radius: 30, y: 18)
        .accessibilityLabel("Brasão da Paróquia Santa Luzia")
    }
}
