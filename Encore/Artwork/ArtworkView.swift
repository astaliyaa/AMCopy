import SwiftUI
import AVFoundation
import ImageIO

/// Square artwork with Apple Music's rounded corners, hairline border and placeholder.
struct ArtworkView: View {
    let artworkID: String?
    var pixelSize: Int = 500
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .task(id: artworkID) {
                guard let artworkID else { image = nil; return }
                if let hit = ArtworkCache.shared.cached(id: artworkID, maxPixel: pixelSize) {
                    image = hit
                } else {
                    image = await ArtworkCache.shared.image(id: artworkID, maxPixel: pixelSize)
                }
            }
    }
}

struct ArtworkPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [Color(white: 0.55), Color(white: 0.42)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            GeometryReader { geo in
                Image(systemName: "music.note")
                    .font(.system(size: geo.size.width * 0.38, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Shows the animated cover when there is one (and the setting is on), otherwise static artwork.
struct SongArtwork: View {
    let artworkID: String?
    let animatedURL: URL?
    var pixelSize: Int = 1000
    var cornerRadius: CGFloat = 10
    @AppStorage(SettingsKey.animatedCovers) private var animatedCovers = true

    var body: some View {
        if animatedCovers, let animatedURL {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ArtworkView(artworkID: artworkID, pixelSize: pixelSize, cornerRadius: 0)
                    AnimatedArtworkView(url: animatedURL)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            ArtworkView(artworkID: artworkID, pixelSize: pixelSize, cornerRadius: cornerRadius)
        }
    }
}

// MARK: - Animated covers

/// A muted, looping video or GIF that fills its frame.
struct AnimatedArtworkView: View {
    let url: URL

    var body: some View {
        if url.pathExtension.lowercased() == "gif" {
            GIFView(url: url)
        } else {
            LoopingVideoView(url: url)
        }
    }
}

struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingVideoUIView {
        let view = LoopingVideoUIView()
        view.load(url)
        return view
    }

    func updateUIView(_ view: LoopingVideoUIView, context: Context) {
        view.load(url)
    }

    static func dismantleUIView(_ view: LoopingVideoUIView, coordinator: ()) {
        view.stop()
    }
}

final class LoopingVideoUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(_ url: URL) {
        guard url != currentURL else { return }
        stop()
        currentURL = url
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        self.player = player
        player.play()
    }

    @objc private func resume() { player?.play() }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        playerLayer.player = nil
        currentURL = nil
    }
}

struct GIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> GIFImageView {
        let view = GIFImageView()
        view.load(url)
        return view
    }

    func updateUIView(_ view: GIFImageView, context: Context) {
        view.load(url)
    }

    static func dismantleUIView(_ view: GIFImageView, coordinator: ()) {
        view.stop()
    }
}

final class GIFImageView: UIImageView {
    private var token = UUID()
    private var currentURL: URL?

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func load(_ url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        contentMode = .scaleAspectFill
        clipsToBounds = true
        let token = UUID()
        self.token = token
        _ = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, cgImage, stop in
            guard let self, self.token == token else {
                stop.pointee = true
                return
            }
            self.image = UIImage(cgImage: cgImage)
        }
    }

    func stop() {
        token = UUID()
        currentURL = nil
    }
}
