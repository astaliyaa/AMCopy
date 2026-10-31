import SwiftUI

/// Time-synced (LRC) lyrics scroll and highlight; plain lyrics just scroll.
struct LyricsPanel: View {
    let song: Song
    @Environment(UIState.self) private var ui
    @State private var parsed = ParsedLyrics.empty

    var body: some View {
        Group {
            if parsed.lines.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("No Lyrics")
                        .font(.title3.bold())
                    Text("Paste lyrics or import an .lrc file to get time-synced lyrics.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Button("Add Lyrics") { ui.edit([song], tab: .lyrics) }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parsed.isSynced {
                SyncedLyrics(lines: parsed.lines, parsed: parsed)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(parsed.lines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
                }
                .fadingEdges()
            }
        }
        .task(id: song.lyrics) {
            parsed = LyricsParser.parse(song.lyrics)
        }
    }
}

private struct SyncedLyrics: View {
    let lines: [LyricLine]
    let parsed: ParsedLyrics
    @Environment(Player.self) private var player

    var body: some View {
        let active = parsed.activeIndex(at: player.currentTime) ?? -1
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(lines) { line in
                        let distance = abs(line.id - active)
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white.opacity(line.id == active ? 1 : 0.32))
                            .blur(radius: line.id == active ? 0 : min(Double(distance) * 0.6, 2.5))
                            .scaleEffect(line.id == active ? 1 : 0.96, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .id(line.id)
                            .onTapGesture {
                                if let time = line.time { player.seek(to: time) }
                            }
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 320)
                .animation(.easeInOut(duration: 0.35), value: active)
            }
            .onChange(of: active) { _, index in
                guard index >= 0 else { return }
                withAnimation(.spring(duration: 0.7)) {
                    proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.25))
                }
            }
            .onAppear {
                if active >= 0 { proxy.scrollTo(active, anchor: UnitPoint(x: 0, y: 0.25)) }
            }
        }
        .fadingEdges()
    }
}

struct QueuePanel: View {
    @Environment(Player.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Playing Next").font(.headline)
                    if !player.queueTitle.isEmpty {
                        Text("From \(player.queueTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer()
                QueueToggle(systemImage: "shuffle", isOn: player.isShuffled) { player.toggleShuffle() }
                QueueToggle(systemImage: player.repeatMode.symbol, isOn: player.repeatMode != .off) { player.cycleRepeat() }
            }

            if player.upNext.isEmpty {
                Text("Nothing up next")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, song in
                        HStack(spacing: 12) {
                            ArtworkView(artworkID: song.artworkID, pixelSize: 120, cornerRadius: 5)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.title).lineLimit(1)
                                Text(song.displayArtist)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { player.jump(toUpNext: offset) }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.white.opacity(0.15))
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    }
                    .onMove { player.moveUpNext(from: $0, to: $1) }
                    .onDelete { player.removeFromUpNext(at: $0) }

                    Button("Clear Up Next", role: .destructive) { player.clearUpNext() }
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .fadingEdges()
            }
        }
        .padding(.top, 6)
    }
}

private struct QueueToggle: View {
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 44, height: 30)
                .background(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }
}

extension View {
    /// Fades content out at the top and bottom edges.
    func fadingEdges(_ length: CGFloat = 28) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: length)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: length)
            }
        }
    }
}
