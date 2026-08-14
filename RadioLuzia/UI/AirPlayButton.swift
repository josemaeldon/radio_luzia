import AVKit
import SwiftUI

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.activeTintColor = UIColor(RadioTheme.gold)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
