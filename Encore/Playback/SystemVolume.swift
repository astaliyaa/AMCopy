import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

/// Bridges the hardware volume to a SwiftUI slider (via a hidden MPVolumeView).
@MainActor
@Observable
final class SystemVolume {
    static let shared = SystemVolume()

    private(set) var level: Double = Double(AVAudioSession.sharedInstance().outputVolume)

    @ObservationIgnored let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let value = Double(session.outputVolume)
            Task { @MainActor in self?.level = value }
        }
    }

    func set(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        level = clamped
        if let slider = volumeView.subviews.lazy.compactMap({ $0 as? UISlider }).first {
            slider.setValue(Float(clamped), animated: false)
            slider.sendActions(for: .valueChanged)
        }
    }
}

/// Must be in the view hierarchy for `SystemVolume.set` to work. Also hides the system volume HUD.
struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.alpha = 0.011
        container.isUserInteractionEnabled = false
        let view = SystemVolume.shared.volumeView
        view.removeFromSuperview()
        container.addSubview(view)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
