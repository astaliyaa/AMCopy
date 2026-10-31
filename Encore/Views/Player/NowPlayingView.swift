import SwiftUI

enum NowPlayingMode {
    case artwork, lyrics, queue
}

struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var mode: NowPlayingMode = .artwork
    @Namespace private var artworkNamespace

    var body: some View {
        let song = player.currentSong
        ZStack {
            NowPlayingBackground(artworkID: song?.artworkID)

            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 38, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                if let song {
                    switch mode {
                    case .artwork:
                        LargeArtwork(song: song, isPlaying: player.isPlaying, namespace: artworkNamespace)
                            .frame(maxHeight: .infinity)
                        TitleRow(song: song)
                            .padding(.bottom, 10)
                    case .lyrics:
                        CompactHeader(song: song, namespace: artworkNamespace)
                        LyricsPanel(song: song)
                            .frame(maxHeight: .infinity)
                    case .queue:
                        CompactHeader(song: song, namespace: artworkNamespace)
                        QueuePanel()
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    Spacer()
                    Text("Not Playing").font(.title2.bold())
                    Spacer()
                }

                ScrubberView()
                TransportControls()
                    .padding(.vertical, 18)
                VolumeSlider()
                BottomBar(mode: $mode)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 28)
            .animation(.spring(duration: 0.45, bounce: 0.15), value: mode)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background { HiddenVolumeView() }
        .modifier(GlobalSheets(isActive: true))
        .onChange(of: player.currentSongID) { _, id in
            if id == nil { dismiss() }
        }
    }
}

// MARK: - Background

/// Slowly moving mesh gradient built from the artwork's colors.
struct NowPlayingBackground: View {
    let artworkID: String?
    @State private var colors = ColorExtractor.fallbackMesh

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(at: t), colors: colors)
        }
        .overlay(Color.black.opacity(0.18))
        .ignoresSafeArea()
        .task(id: artworkID) {
            let next = await ColorExtractor.meshColors(artworkID: artworkID)
            withAnimation(.easeInOut(duration: 1.0)) { colors = next }
        }
    }

    private func points(at t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.33)) * 0.14
        let b = Float(cos(t * 0.27)) * 0.14
        let c = Float(sin(t * 0.21 + 1.3)) * 0.12
        return [
            SIMD2(0, 0), SIMD2(0.5 + a, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + b), SIMD2(0.5 + c, 0.5 - a), SIMD2(1, 0.5 + c),
            SIMD2(0, 1), SIMD2(0.5 - b, 1), SIMD2(1, 1),
        ]
    }
}

// MARK: - Artwork

private struct LargeArtwork: View {
    let song: Song
    let isPlaying: Bool
    let namespace: Namespace.ID

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            SongArtwork(artworkID: song.artworkID, animatedURL: song.animatedCoverURL, pixelSize: 1400, cornerRadius: 12)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(isPlaying ? 0.4 : 0.2), radius: isPlaying ? 28 : 12, y: isPlaying ? 16 : 6)
                .scaleEffect(isPlaying ? 1 : 0.8)
                .animation(.spring(duration: 0.5, bounce: 0.25), value: isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, 12)
    }
}

private struct TitleRow: View {
    let song: Song
    @Environment(Library.self) private var library
    @Environment(UIState.self) private var ui

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(song.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if song.isExplicit { ExplicitBadge() }
                }
                Button {
                    ui.navigate(to: .artist(song.artistKey))
                } label: {
                    Text(song.displayArtist)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                library.toggleFavorite(song.id)
            } label: {
                GlassCircleLabel(systemImage: song.isFavorite ? "star.fill" : "star", isActive: song.isFavorite)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: song.isFavorite)

            Menu {
                SongActions(song: song)
            } label: {
                GlassCircleLabel(systemImage: "ellipsis")
            }
        }
    }
}

private struct CompactHeader: View {
    let song: Song
    let namespace: Namespace.ID
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            SongArtwork(artworkID: song.artworkID, animatedURL: song.animatedCoverURL, pixelSize: 300, cornerRadius: 6)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.headline).lineLimit(1)
                Text(song.displayArtist).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                library.toggleFavorite(song.id)
            } label: {
                GlassCircleLabel(systemImage: song.isFavorite ? "star.fill" : "star", isActive: song.isFavorite)
            }
            .buttonStyle(.plain)
            Menu {
                SongActions(song: song)
            } label: {
                GlassCircleLabel(systemImage: "ellipsis")
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Scrubber & transport

private struct ScrubberView: View {
    @Environment(Player.self) private var player
    @State private var dragProgress: Double?

    var body: some View {
        let duration = max(player.duration, 0.01)
        let progress = dragProgress ?? min(player.currentTime / duration, 1)
        let elapsed = progress * duration
        let song = player.currentSong

        VStack(spacing: 2) {
            ElasticSlider(
                value: Binding(get: { progress }, set: { dragProgress = $0 }),
                onEditingChanged: { editing in
                    if !editing, let value = dragProgress {
                        player.seek(to: value * duration)
                        dragProgress = nil
                    }
                }
            )
            HStack {
                Text(elapsed.timeString)
                Spacer()
                if let song, song.isLossless {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                        Text("Lossless")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                } else if let song {
                    Text(song.fileExtension.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Text("-" + max(duration - elapsed, 0).timeString)
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct TransportControls: View {
    @Environment(Player.self) private var player
    @State private var backTaps = 0
    @State private var forwardTaps = 0

    var body: some View {
        HStack {
            Spacer()
            Button {
                backTaps += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .symbolEffect(.bounce.down, value: backTaps)
            }
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 52))
                    .frame(width: 72, height: 72)
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            Spacer()
            Button {
                forwardTaps += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .symbolEffect(.bounce.down, value: forwardTaps)
            }
            Spacer()
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
        .disabled(player.currentSong == nil)
        .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
    }
}

private struct VolumeSlider: View {
    @State private var volume = SystemVolume.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
            ElasticSlider(value: Binding(get: { volume.level }, set: { volume.set($0) }))
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

private struct BottomBar: View {
    @Binding var mode: NowPlayingMode

    var body: some View {
        HStack {
            toggle(.lyrics, on: "quote.bubble.fill", off: "quote.bubble")
            Spacer()
            AirPlayButton()
                .frame(width: 44, height: 44)
            Spacer()
            toggle(.queue, on: "list.bullet", off: "list.bullet")
        }
        .padding(.horizontal, 24)
    }

    private func toggle(_ target: NowPlayingMode, on: String, off: String) -> some View {
        let active = mode == target
        return Button {
            mode = active ? .artwork : target
        } label: {
            Image(systemName: active ? on : off)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.65))
                .frame(width: 40, height: 40)
                .background(active ? Color.white.opacity(0.9) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
