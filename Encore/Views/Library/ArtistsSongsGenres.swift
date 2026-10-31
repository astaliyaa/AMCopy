import SwiftUI

// MARK: - Artists

struct ArtistsView: View {
    @Environment(Library.self) private var library

    var body: some View {
        List(library.artists) { artist in
            NavigationLink(value: Route.artist(artist.id)) {
                HStack(spacing: 14) {
                    ArtworkView(artworkID: artist.artworkID, pixelSize: 150, cornerRadius: 26)
                        .frame(width: 52, height: 52)
                    Text(artist.name)
                        .font(.body)
                        .lineLimit(1)
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
        }
        .listStyle(.plain)
        .overlay {
            if library.artists.isEmpty { EmptyLibraryView() }
        }
        .navigationTitle("Artists")
    }
}

struct ArtistDetailView: View {
    let artistID: String
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    var body: some View {
        if let artist = library.artist(artistID) {
            content(artist)
        } else {
            ContentUnavailableView("Artist Not Available", systemImage: "music.microphone")
        }
    }

    private func content(_ artist: Artist) -> some View {
        let songs = artist.songs
        let topSongs = songs.sorted { $0.playCount > $1.playCount }.prefix(5)
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(spacing: 14) {
                    ArtworkView(artworkID: artist.artworkID, pixelSize: 600, cornerRadius: 110)
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                    Text(artist.name)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    PlayShuffleButtons(songs: songs, title: artist.name)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Songs").font(.title2.bold()).padding(.horizontal, 20)
                    ForEach(Array(topSongs)) { song in
                        Button {
                            player.play(songs, startingAt: songs.firstIndex(of: song), from: artist.name)
                        } label: {
                            SongRow(song: song, subtitle: song.displayAlbum)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }

                Shelf("Albums", items: artist.albums) { album in
                    NavigationLink(value: Route.album(album.id)) {
                        AlbumTile(album: album, width: 160)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Songs

struct SongsView: View {
    enum Sort: String, CaseIterable {
        case title = "Title", artist = "Artist", album = "Album", recent = "Recently Added", plays = "Most Played"
    }

    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui
    @AppStorage("songSort") private var sort: Sort = .title
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive

    private var songs: [Song] {
        let all = library.songs
        switch sort {
        case .title: return all.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            return all.sorted {
                let order = $0.displayArtist.localizedStandardCompare($1.displayArtist)
                return order == .orderedSame ? Song.albumOrder($0, $1) : order == .orderedAscending
            }
        case .album:
            return all.sorted {
                $0.albumKey == $1.albumKey
                    ? Song.albumOrder($0, $1)
                    : $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending
            }
        case .recent: return all.sorted { $0.dateAdded > $1.dateAdded }
        case .plays: return all.sorted { $0.playCount > $1.playCount }
        }
    }

    var body: some View {
        let sorted = self.songs
        let editing = editMode.isEditing
        List(selection: $selection) {
            if !editing {
                PlayShuffleButtons(songs: sorted, title: "Songs")
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
            }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, song in
                Group {
                    if editing {
                        SongRow(song: song)
                    } else {
                        Button {
                            player.play(sorted, startingAt: index, from: "Songs")
                        } label: {
                            SongRow(song: song)
                        }
                    }
                }
                .tag(song.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
                .swipeActions(edge: .leading) {
                    Button { player.playNext([song]) } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(.purple)
                    Button { player.playLast([song]) } label: {
                        Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { ui.confirmDelete([song]) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .overlay {
            if library.songs.isEmpty { EmptyLibraryView() }
        }
        .navigationTitle("Songs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Select") {
                    withAnimation {
                        editMode = editing ? .inactive : .active
                        selection.removeAll()
                    }
                }
            }
            if !editing {
                ToolbarItem(placement: .topBarTrailing) {
                    SortMenu(selection: $sort)
                }
            }
            if editing {
                ToolbarItemGroup(placement: .bottomBar) {
                    let chosen = sorted.filter { selection.contains($0.id) }
                    Button("Edit Info") { ui.edit(chosen) }
                        .disabled(chosen.isEmpty)
                    Spacer()
                    Menu("More") {
                        Button { player.playNext(chosen) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { ui.addToPlaylist(chosen) } label: { Label("Add to a Playlist…", systemImage: "text.badge.plus") }
                        Button(role: .destructive) { ui.confirmDelete(chosen) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .disabled(chosen.isEmpty)
                    Spacer()
                    Button(selection.count == sorted.count ? "Deselect All" : "Select All") {
                        selection = selection.count == sorted.count ? [] : Set(sorted.map(\.id))
                    }
                }
            }
        }
    }
}

/// Simple song list used by Favorites and Genres.
struct SongListView: View {
    let title: String
    let songs: [Song]
    @Environment(Player.self) private var player

    var body: some View {
        List {
            PlayShuffleButtons(songs: songs, title: title)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    player.play(songs, startingAt: index, from: title)
                } label: {
                    SongRow(song: song)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
    }
}

struct FavoritesView: View {
    @Environment(Library.self) private var library

    var body: some View {
        SongListView(title: "Favorite Songs", songs: library.favorites)
            .overlay {
                if library.favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites Yet",
                        systemImage: "star",
                        description: Text("Tap the star in Now Playing or long-press a song and choose Favorite.")
                    )
                }
            }
    }
}

// MARK: - Genres

struct GenresView: View {
    @Environment(Library.self) private var library
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(library.genres) { genre in
                    NavigationLink(value: Route.genre(genre.id)) {
                        GradientCard(title: genre.name, subtitle: "\(genre.songs.count) songs", artworkID: genre.artworkID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .overlay {
            if library.genres.isEmpty {
                ContentUnavailableView("No Genres", systemImage: "guitars", description: Text("Add a genre to your songs with Edit Info."))
            }
        }
        .navigationTitle("Genres")
    }
}

struct GenreDetailView: View {
    let genreID: String
    @Environment(Library.self) private var library

    var body: some View {
        if let genre = library.genre(genreID) {
            SongListView(title: genre.name, songs: genre.songs)
        } else {
            ContentUnavailableView("Genre Not Available", systemImage: "guitars")
        }
    }
}
