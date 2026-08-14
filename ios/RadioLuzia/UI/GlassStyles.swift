import SwiftUI

extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func roundGlassControl() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.14), lineWidth: 1) }
        }
    }
}

enum RadioTheme {
    static let wine = Color(red: 0.35, green: 0.025, blue: 0.10)
    static let plum = Color(red: 0.10, green: 0.02, blue: 0.08)
    static let gold = Color(red: 1.0, green: 0.70, blue: 0.25)
    static let cream = Color(red: 1.0, green: 0.93, blue: 0.80)
}

