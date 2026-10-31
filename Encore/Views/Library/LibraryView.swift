import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(UIState.self) private var ui

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        @Bindable var ui = ui
        NavigationStack(path: $ui.libraryPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        CategoryRow(title: "Playlists", systemImage: "music.note.list", route: .playlists)
                        CategoryRow(title: "Artists", systemImage: "music.microphone", route: .artists)
                        CategoryRow(title: "Albums", systemImage: "square.stack", route: .albums)
                        CategoryRow(title: "Songs", systemImage: "music.note", route: .songs)
                        CategoryRow(title: "Favorite Songs", systemImage: "star", route: .favorites)
                        CategoryRow(title: "Genres", systemImage: "guitars", route: .genres, showsDivider: false)
                    }
                    .padding(.leading, 20)

                    if library.songs.isEmpty {
                        EmptyLibraryView().padding(.top, 40)
                    } else {
                        Text("Recently Added")
                            .font(.title2.bold())
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                            .padding(.bottom, 12)
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(library.recentlyAddedAlbums.prefix(40)) { album in
                                NavigationLink(value: Route.album(album.id)) {
                                    AlbumTile(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { ui.importFiles() } label: { Label("Import Songs…", systemImage: "music.note") }
                        Button { ui.importFolder() } label: { Label("Import Folder…", systemImage: "folder") }
                        Divider()
                        Button { ui.playlistEditor = PlaylistEditRequest(playlistID: nil) } label: {
                            Label("New Playlist…", systemImage: "music.note.list")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ui.showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .routeDestinations()
        }
    }
}

private struct CategoryRow: View {
    let title: String
    let systemImage: String
    let route: Route
    var showsDivider = true

    var body: some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 30)
                    Text(title)
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 20)
                }
                .padding(.vertical, 11)
                if showsDivider {
                    Divider().padding(.leading, 44)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Routing

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteView(route: route)
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .playlists: PlaylistsView()
        case .artists: ArtistsView()
        case .albums: AlbumsView()
        case .songs: SongsView()
        case .favorites: FavoritesView()
        case .genres: GenresView()
        case .album(let id): AlbumDetailView(albumID: id)
        case .artist(let id): ArtistDetailView(artistID: id)
        case .genre(let id): GenreDetailView(genreID: id)
        case .playlist(let id): PlaylistDetailView(playlistID: id)
        }
    }
}

// MARK: - Albums

struct AlbumsView: View {
    enum Sort: String, CaseIterable {
        case title = "Title", artist = "Artist", recent = "Recently Added", year = "Release Date"
    }

    @Environment(Library.self) private var library
    @AppStorage("albumSort") private var sort: Sort = .title
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    private var albums: [Album] {
        switch sort {
        case .title: library.albums
        case .artist:
            library.albums.sorted {
                $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
            }
        case .recent: library.recentlyAddedAlbums
        case .year: library.albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(value: Route.album(album.id)) {
                        AlbumTile(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .overlay {
            if library.albums.isEmpty { EmptyLibraryView() }
        }
        .navigationTitle("Albums")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(selection: $sort)
            }
        }
    }
}

struct SortMenu<Option: RawRepresentable & CaseIterable & Hashable>: View where Option.RawValue == String, Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option

    var body: some View {
        Menu {
            Picker("Sort By", selection: $selection) {
                ForEach(Option.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Album detail

struct AlbumDetailView: View {
    let albumID: String
    @Environment(Library.self) private var library
    @AppStorage(SettingsKey.animatedCovers) private var animatedCovers = true

    var body: some View {
        if let album = library.album(albumID) {
            content(album)
        } else {
            ContentUnavailableView("Album Not Available", systemImage: "square.stack")
        }
    }

    private func content(_ album: Album) -> some View {
        let motion = animatedCovers ? album.animatedCoverURL : nil
        return ScrollView {
            VStack(spacing: 0) {
                if let motion {
                    // Full-bleed motion artwork header.
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            ArtworkView(artworkID: album.artworkID, pixelSize: 1200, cornerRadius: 0)
                            AnimatedArtworkView(url: motion)
                        }
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 90)
                        }
                } else {
                    ArtworkView(artworkID: album.artworkID, pixelSize: 900, cornerRadius: 10)
                        .frame(width: 264, height: 264)
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                        .padding(.top, 8)
                }

                AlbumHeader(album: album)
                    .padding(.horizontal, 20)
                    .padding(.top, motion == nil ? 18 : -30)

                TrackList(album: album)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 4) {
                    if let year = album.year { Text(String(year)) }
                    Text("\(album.songs.count) \(album.songs.count == 1 ? "song" : "songs"), \(album.duration.longDurationString)")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .ignoresSafeArea(edges: motion == nil ? [] : .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(motion == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    AlbumActions(album: album)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

private struct AlbumHeader: View {
    let album: Album

    var body: some View {
        VStack(spacing: 4) {
            Text(album.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            NavigationLink(value: Route.artist(album.artistID)) {
                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                if !album.subtitle.isEmpty {
                    Text(album.subtitle.uppercased())
                }
                if album.isLossless { LosslessBadge() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            PlayShuffleButtons(songs: album.songs, title: album.title)
                .padding(.top, 14)
        }
    }
}

private struct TrackList: View {
    let album: Album
    @Environment(Player.self) private var player

    var body: some View {
        let multiDisc = album.discCount > 1
        let discs = Dictionary(grouping: album.songs, by: { $0.discNumber ?? 1 }).sorted { $0.key < $1.key }
        LazyVStack(alignment: .leading, spacing: 0) {
            Divider().padding(.leading, 20)
            ForEach(discs, id: \.key) { entry in
                let songs = entry.value
                if multiDisc {
                    Text("Disc \(entry.key)")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                }
                ForEach(songs) { song in
                    Button {
                        let index = album.songs.firstIndex(of: song) ?? 0
                        player.play(album.songs, startingAt: index, from: album.title)
                    } label: {
                        SongRow(
                            song: song,
                            trackNumber: song.trackNumber ?? ((album.songs.firstIndex(of: song) ?? 0) + 1),
                            subtitle: song.artist != album.artist && !song.artist.isEmpty ? song.artist : nil
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(RowButtonStyle())
                    Divider().padding(.leading, 56)
                }
            }
        }
    }
}

/// Plain row with a gray highlight while pressed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color(.systemGray5).opacity(configuration.isPressed ? 1 : 0))
    }
}
