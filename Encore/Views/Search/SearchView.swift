import SwiftUI

struct SearchView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @State private var query = ""
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    browse
                } else {
                    results
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, Songs, Lyrics, and More")
            .routeDestinations()
        }
    }

    private var browse: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if library.genres.isEmpty && library.songs.isEmpty {
                    EmptyLibraryView().padding(.top, 60)
                } else {
                    Text("Browse Categories")
                        .font(.title2.bold())
                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink(value: Route.favorites) {
                            GradientCard(title: "Favorites", systemImage: "star.fill")
                        }
                        .buttonStyle(.plain)
                        NavigationLink(value: Route.albums) {
                            GradientCard(title: "Albums", artworkID: library.recentlyAddedAlbums.first?.artworkID)
                        }
                        .buttonStyle(.plain)
                        ForEach(library.genres) { genre in
                            NavigationLink(value: Route.genre(genre.id)) {
                                GradientCard(title: genre.name, artworkID: genre.artworkID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var results: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let artists = library.artists.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(8)
        let albums = library.albums.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q)
        }.prefix(12)
        let songs = Array(library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
                || $0.composer.localizedCaseInsensitiveContains(q)
        }.prefix(40))
        let lyricMatches = Array(library.songs.filter {
            !songs.contains($0) && $0.lyrics.localizedCaseInsensitiveContains(q)
        }.prefix(10))
        let playlists = library.playlists.filter { $0.name.localizedCaseInsensitiveContains(q) }

        return List {
            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(Array(artists)) { artist in
                        NavigationLink(value: Route.artist(artist.id)) {
                            HStack(spacing: 12) {
                                ArtworkView(artworkID: artist.artworkID, pixelSize: 120, cornerRadius: 22)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading) {
                                    Text(artist.name)
                                    Text("Artist").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(Array(albums)) { album in
                        NavigationLink(value: Route.album(album.id)) {
                            HStack(spacing: 12) {
                                ArtworkView(artworkID: album.artworkID, pixelSize: 120, cornerRadius: 5)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading) {
                                    Text(album.title).lineLimit(1)
                                    Text("Album · \(album.artist)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            player.play(songs, startingAt: index, from: "Search")
                        } label: {
                            SongRow(song: song, subtitle: "Song · \(song.displayArtist)")
                        }
                    }
                }
            }
            if !lyricMatches.isEmpty {
                Section("Lyrics") {
                    ForEach(lyricMatches) { song in
                        Button {
                            player.play([song], from: "Search")
                        } label: {
                            SongRow(song: song, subtitle: lyricSnippet(song.lyrics, q))
                        }
                    }
                }
            }
            if !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: Route.playlist(playlist.id)) {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: playlist, pixelSize: 120, cornerRadius: 5)
                                    .frame(width: 44, height: 44)
                                Text(playlist.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if artists.isEmpty && albums.isEmpty && songs.isEmpty && lyricMatches.isEmpty && playlists.isEmpty {
                ContentUnavailableView.search(text: q)
            }
        }
    }

    /// The lyric line containing the match.
    private func lyricSnippet(_ lyrics: String, _ q: String) -> String {
        let line = lyrics.components(separatedBy: .newlines).first { $0.localizedCaseInsensitiveContains(q) } ?? ""
        let cleaned = line.replacingOccurrences(of: #"\[[0-9:.]+\]"#, with: "", options: .regularExpression)
        return "Lyrics · " + cleaned.trimmingCharacters(in: .whitespaces)
    }
}
