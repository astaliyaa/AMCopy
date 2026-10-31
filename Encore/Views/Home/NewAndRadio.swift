import SwiftUI

/// "New": everything you've added recently.
struct NewView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    private var latestSongs: [Song] {
        Array(library.songs.sorted { $0.dateAdded > $1.dateAdded }.prefix(24))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.songs.isEmpty {
                    EmptyLibraryView().padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        heroCarousel
                        latestSongsGrid
                        Shelf("New Albums", route: .albums, items: Array(library.recentlyAddedAlbums.prefix(20))) { album in
                            NavigationLink(value: Route.album(album.id)) {
                                AlbumTile(album: album, width: 160)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New")
            .routeDestinations()
        }
    }

    private var heroCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(library.recentlyAddedAlbums.prefix(6)) { album in
                    NavigationLink(value: Route.album(album.id)) {
                        HeroCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private var latestSongsGrid: some View {
        let songs = latestSongs
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Latest Songs", route: .songs)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4), spacing: 16) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            player.play(songs, startingAt: index, from: "Latest Songs")
                        } label: {
                            SongRow(song: song)
                                .frame(width: 300)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct HeroCard: View {
    let album: Album
    @AppStorage(SettingsKey.animatedCovers) private var animatedCovers = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECENTLY ADDED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(album.title)
                    .font(.title3)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            SongArtwork(
                artworkID: album.artworkID,
                animatedURL: animatedCovers ? album.animatedCoverURL : nil,
                pixelSize: 900,
                cornerRadius: 12
            )
            .frame(width: 330, height: 330)
        }
        .frame(width: 330)
        .contextMenu { AlbumActions(album: album) }
    }
}

/// "Radio": shuffled stations generated from your own library.
struct RadioView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.songs.isEmpty {
                    EmptyLibraryView().padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 30) {
                        Button {
                            player.play(library.songs, shuffle: true, from: "My Station")
                        } label: {
                            StationHero()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)

                        if !library.genres.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Genre Stations")
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(library.genres) { genre in
                                        Button {
                                            player.play(genre.songs, shuffle: true, from: "\(genre.name) Station")
                                        } label: {
                                            GradientCard(title: genre.name, subtitle: "Station", artworkID: genre.artworkID)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        Shelf("Artist Stations", items: Array(library.artists.prefix(30))) { artist in
                            Button {
                                player.play(artist.songs, shuffle: true, from: "\(artist.name) Station")
                            } label: {
                                VStack(spacing: 8) {
                                    ArtworkView(artworkID: artist.artworkID, pixelSize: 300, cornerRadius: 60)
                                        .frame(width: 120, height: 120)
                                        .overlay(alignment: .bottomTrailing) {
                                            Image(systemName: "dot.radiowaves.left.and.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(7)
                                                .background(Color.appAccent, in: Circle())
                                        }
                                    Text(artist.name)
                                        .font(.footnote)
                                        .lineLimit(1)
                                }
                                .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Radio")
            .routeDestinations()
        }
    }
}

private struct StationHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.4], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    .appAccent, .pink, .orange,
                    .purple, .appAccent, .pink,
                    .indigo, .purple, .appAccent,
                ]
            )
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            VStack(alignment: .leading, spacing: 4) {
                Text("MY STATION")
                    .font(.caption.weight(.bold))
                    .opacity(0.8)
                Text("Your whole library, shuffled")
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.25), in: Capsule())
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
