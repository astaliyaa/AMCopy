import SwiftUI

struct HomeView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui

    /// Most played first, then a per-launch shuffle so Home feels fresh.
    private var topPicks: [Album] {
        let played = library.albums.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }
        let rest = library.albums.filter { $0.playCount == 0 }.sorted { $0.id.hashValue < $1.id.hashValue }
        return Array((played.prefix(4) + rest).prefix(8))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.songs.isEmpty {
                    EmptyLibraryView().padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        Shelf("Top Picks for You", items: topPicks) { album in
                            NavigationLink(value: Route.album(album.id)) {
                                TopPickCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }

                        if !library.recentlyPlayedAlbums.isEmpty {
                            Shelf("Recently Played", items: Array(library.recentlyPlayedAlbums.prefix(15))) { album in
                                NavigationLink(value: Route.album(album.id)) {
                                    AlbumTile(album: album, width: 160)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !library.genres.isEmpty {
                            Shelf("Made for You", items: Array(library.genres.prefix(10))) { genre in
                                Button {
                                    player.play(genre.songs, shuffle: true, from: "\(genre.name) Mix")
                                } label: {
                                    MixCard(title: "\(genre.name) Mix", genre: genre)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !library.favorites.isEmpty {
                            Shelf("Favorite Songs", route: .favorites, items: Array(library.favorites.prefix(12))) { song in
                                Button {
                                    player.play(library.favorites, startingAt: library.favorites.firstIndex(of: song), from: "Favorite Songs")
                                } label: {
                                    SongCard(song: song)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Shelf("Recently Added", route: .albums, items: Array(library.recentlyAddedAlbums.prefix(15))) { album in
                            NavigationLink(value: Route.album(album.id)) {
                                AlbumTile(album: album, width: 160)
                            }
                            .buttonStyle(.plain)
                        }

                        if !library.playlists.isEmpty {
                            Shelf("Your Playlists", route: .playlists, items: library.playlists) { playlist in
                                NavigationLink(value: Route.playlist(playlist.id)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        PlaylistArtwork(playlist: playlist, pixelSize: 400)
                                            .frame(width: 160, height: 160)
                                        Text(playlist.name).font(.footnote).lineLimit(1)
                                    }
                                    .frame(width: 160)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { ui.showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                }
            }
            .routeDestinations()
        }
    }
}

/// Large artwork card with a caption tinted by the artwork's color.
struct TopPickCard: View {
    let album: Album
    @State private var tint = Color(white: 0.3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(artworkID: album.artworkID, pixelSize: 700, cornerRadius: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.subheadline)
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
        }
        .frame(width: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .contextMenu { AlbumActions(album: album) }
        .task(id: album.artworkID) {
            tint = await ColorExtractor.averageColor(artworkID: album.artworkID)
        }
    }
}

/// "Rock Mix" style card.
struct MixCard: View {
    let title: String
    let genre: Genre

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GradientCard(title: title, subtitle: "\(genre.songs.count) songs", artworkID: genre.artworkID, height: 160)
                .frame(width: 160)
            Text("Shuffled from your library")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 160)
    }
}

struct SongCard: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(artworkID: song.artworkID, pixelSize: 400)
                .frame(width: 140, height: 140)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title).foregroundStyle(.primary).lineLimit(1)
                Text(song.displayArtist).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.footnote)
        }
        .frame(width: 140)
        .contextMenu { SongActions(song: song) }
    }
}
