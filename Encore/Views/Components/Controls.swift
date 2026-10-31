import SwiftUI
import AVKit

/// Apple Music-style slider: a thin capsule that thickens while dragged.
/// Dragging is relative (it doesn't jump to where you touch).
struct ElasticSlider: View {
    @Binding var value: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var startValue: Double = 0

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height: CGFloat = isDragging ? 12 : 7
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.22))
                Rectangle()
                    .fill(.white.opacity(isDragging ? 0.95 : 0.65))
                    .frame(width: width * min(max(value, 0), 1))
            }
            .frame(height: height)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity)
            .scaleEffect(x: isDragging ? 1.02 : 1, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            startValue = value
                            onEditingChanged(true)
                        }
                        value = min(max(startValue + gesture.translation.width / width, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.spring(duration: 0.3, bounce: 0.3), value: isDragging)
        }
        .frame(height: 28)
        .sensoryFeedback(.selection, trigger: isDragging)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.65)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Button style that dims and shrinks on press, like the Now Playing transport controls.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.12 : 0))
                    .padding(-10)
            }
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A round translucent icon button (favorite / "…" in Now Playing).
struct GlassCircleLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(.white.opacity(isActive ? 0.3 : 0.14), in: Circle())
    }
}

/// Genre / station card with a gradient and tilted artwork, as in Browse Categories.
struct GradientCard: View {
    let title: String
    var subtitle: String?
    var artworkID: String?
    var systemImage: String?
    var height: CGFloat = 110

    private var colors: [Color] {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.27, blue: 0.36), Color(red: 0.98, green: 0.55, blue: 0.20),
            Color(red: 0.35, green: 0.45, blue: 0.95), Color(red: 0.55, green: 0.30, blue: 0.85),
            Color(red: 0.15, green: 0.65, blue: 0.55), Color(red: 0.85, green: 0.25, blue: 0.60),
            Color(red: 0.20, green: 0.55, blue: 0.85), Color(red: 0.75, green: 0.55, blue: 0.20),
        ]
        let hash = StableHash.of(title)
        return [palette[hash % palette.count], palette[(hash / 7) % palette.count]]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artworkID {
                ArtworkView(artworkID: artworkID, pixelSize: 250, cornerRadius: 6)
                    .frame(width: height * 0.72, height: height * 0.72)
                    .rotationEffect(.degrees(22))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .offset(x: 18, y: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: height * 0.45, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .rotationEffect(.degrees(15))
                    .offset(x: 10, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.caption.weight(.medium)).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
