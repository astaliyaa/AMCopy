import SwiftUI

struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}

struct LosslessBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "waveform")
            Text("Lossless")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// Animated bars shown on the song that is playing.
struct NowPlayingIndicator: View {
    @Environment(Player.self) private var player

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.appAccent)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating, isActive: player.isPlaying)
    }
}

struct SongRow: View {
    let song: Song
    var trackNumber: Int?
    var showArtwork = true
    var subtitle: String?

    @Environment(Player.self) private var player

    var body: some View {
        let isCurrent = player.currentSongID == song.id
        HStack(spacing: 12) {
            if let trackNumber {
                ZStack {
                    if isCurrent {
                        NowPlayingIndicator()
                    } else {
                        Text("\(trackNumber)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 24)
            } else if showArtwork {
                ArtworkView(artworkID: song.artworkID, pixelSize: 150, cornerRadius: 5)
                    .frame(width: 48, height: 48)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.black.opacity(0.35))
                            NowPlayingIndicator().foregroundStyle(.white)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(song.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if song.isExplicit { ExplicitBadge() }
                }
                if let line = subtitle ?? (trackNumber == nil ? song.displayArtist : nil), !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if song.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.appAccent)
            }

            Menu {
                SongActions(song: song)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            SongActions(song: song)
        } preview: {
            SongPreview(song: song)
        }
    }
}

private struct SongPreview: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SongArtwork(artworkID: song.artworkID, animatedURL: song.animatedCoverURL, pixelSize: 600)
                .frame(width: 260, height: 260)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.headline).lineLimit(1)
                Text("\(song.displayArtist) — \(song.displayAlbum)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 288)
    }
}

/// Actions shared by every song menu (long-press, "…" button, Now Playing).
struct SongActions: View {
    let song: Song
    var playlistID: UUID?
    var playlistIndex: Int?

    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @Environment(UIState.self) private var ui

    var body: some View {
        Section {
            Button { player.playNext([song]) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { player.playLast([song]) } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
        Section {
            Button { ui.addToPlaylist([song]) } label: {
                Label("Add to a Playlist…", systemImage: "text.badge.plus")
            }
            Button { library.toggleFavorite(song.id) } label: {
                Label(song.isFavorite ? "Undo Favorite" : "Favorite", systemImage: song.isFavorite ? "star.slash" : "star")
            }
        }
        Section {
            Button { ui.edit([song]) } label: {
                Label("Edit Info", systemImage: "pencil")
            }
            Button { ui.edit([song], tab: .artwork) } label: {
                Label("Set Animated Cover", systemImage: "sparkles.rectangle.stack")
            }
            Button { ui.edit([song], tab: .lyrics) } label: {
                Label("Edit Lyrics", systemImage: "quote.bubble")
            }
        }
        Section {
            Button { ui.navigate(to: .album(song.albumKey)) } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
            Button { ui.navigate(to: .artist(song.artistKey)) } label: {
                Label("Go to Artist", systemImage: "music.microphone")
            }
            ShareLink(item: song.fileURL) {
                Label("Share Song File…", systemImage: "square.and.arrow.up")
            }
        }
        Section {
            if let playlistID, let playlistIndex {
                Button(role: .destructive) {
                    library.modifyPlaylist(playlistID) { playlist in
                        if playlist.songIDs.indices.contains(playlistIndex) {
                            playlist.songIDs.remove(at: playlistIndex)
                        }
                    }
                } label: {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            }
            Button(role: .destructive) { ui.confirmDelete([song]) } label: {
                Label("Delete from Library", systemImage: "trash")
            }
        }
    }
}

/// Actions for a whole album.
struct AlbumActions: View {
    let album: Album

    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui

    var body: some View {
        Section {
            Button { player.play(album.songs, shuffle: false, from: album.title) } label: {
                Label("Play", systemImage: "play")
            }
            Button { player.play(album.songs, shuffle: true, from: album.title) } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            Button { player.playNext(album.songs) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button { player.playLast(album.songs) } label: {
                Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
        Section {
            Button { ui.addToPlaylist(album.songs) } label: {
                Label("Add to a Playlist…", systemImage: "text.badge.plus")
            }
            Button { ui.edit(album.songs) } label: {
                Label("Edit Album Info", systemImage: "pencil")
            }
            Button { ui.edit(album.songs, tab: .artwork) } label: {
                Label("Set Animated Cover", systemImage: "sparkles.rectangle.stack")
            }
        }
        Section {
            Button(role: .destructive) { ui.confirmDelete(album.songs) } label: {
                Label("Delete from Library", systemImage: "trash")
            }
        }
    }
}

struct AlbumTile: View {
    let album: Album
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(artworkID: album.artworkID, pixelSize: 500)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(album.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if album.isExplicit { ExplicitBadge() }
                }
                Text(album.artist)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.footnote)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .contextMenu {
            AlbumActions(album: album)
        }
    }
}

struct PlayShuffleButtons: View {
    let songs: [Song]
    let title: String
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 14) {
            Button {
                player.play(songs, shuffle: false, from: title)
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            Button {
                player.play(songs, shuffle: true, from: title)
            } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(SoftCapsuleButtonStyle())
        .disabled(songs.isEmpty)
    }
}

struct SoftCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.appAccent)
            .padding(.vertical, 13)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// "Recently Added ›" style section header.
struct SectionHeader: View {
    let title: String
    var route: Route?

    var body: some View {
        if let route {
            NavigationLink(value: route) {
                HStack(spacing: 4) {
                    Text(title).font(.title2.bold())
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(title).font(.title2.bold())
        }
    }
}

/// Horizontally scrolling shelf, as on Home / New / Radio.
struct Shelf<Item: Identifiable, Cell: View>: View {
    let title: String
    var route: Route?
    let items: [Item]
    let cell: (Item) -> Cell

    init(_ title: String, route: Route? = nil, items: [Item], @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.title = title
        self.route = route
        self.items = items
        self.cell = cell
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, route: route)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in cell(item) }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

struct EmptyLibraryView: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        ContentUnavailableView {
            Label("Add Your Music", systemImage: "music.note.house")
        } description: {
            Text("Import MP3, M4A, FLAC, WAV or AIFF files from the Files app, or copy them into Encore's folder from your computer.")
        } actions: {
            Button("Import Songs…") { ui.importFiles() }
                .buttonStyle(.borderedProminent)
            Button("Import a Folder…") { ui.importFolder() }
        }
    }
}
