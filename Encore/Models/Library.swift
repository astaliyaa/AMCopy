import Foundation
import Observation

struct ImportStatus: Equatable {
    var done: Int
    var total: Int
}

/// The music library: songs + playlists, persisted as JSON.
/// Albums, artists and genres are rebuilt from songs after every change.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    private(set) var songs: [Song] = []
    private(set) var playlists: [Playlist] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var genres: [Genre] = []
    var importStatus: ImportStatus?

    @ObservationIgnored private var songIndex: [UUID: Int] = [:]
    @ObservationIgnored private var albumIndex: [String: Int] = [:]
    @ObservationIgnored private var artistIndex: [String: Int] = [:]
    @ObservationIgnored private var genreIndex: [String: Int] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private struct Snapshot: Codable {
        var songs: [Song]
        var playlists: [Playlist]
    }

    private init() {
        Paths.createDirectories()
        if let data = try? Data(contentsOf: Paths.libraryFile),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            songs = snapshot.songs
            playlists = snapshot.playlists
        }
        rebuild()
    }

    // MARK: Lookup

    func song(_ id: UUID) -> Song? {
        guard let i = songIndex[id], songs.indices.contains(i) else { return nil }
        return songs[i]
    }

    func songs(_ ids: [UUID]) -> [Song] { ids.compactMap(song) }

    func album(_ id: String) -> Album? {
        guard let i = albumIndex[id], albums.indices.contains(i) else { return nil }
        return albums[i]
    }

    func artist(_ id: String) -> Artist? {
        guard let i = artistIndex[id], artists.indices.contains(i) else { return nil }
        return artists[i]
    }

    func genre(_ id: String) -> Genre? {
        guard let i = genreIndex[id], genres.indices.contains(i) else { return nil }
        return genres[i]
    }

    func playlist(_ id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    var favorites: [Song] {
        songs.filter(\.isFavorite).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var recentlyAddedAlbums: [Album] { albums.sorted { $0.dateAdded > $1.dateAdded } }

    var recentlyPlayedAlbums: [Album] {
        albums.filter { $0.lastPlayed != nil }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    var storageUsed: Int64 { songs.reduce(0) { $0 + $1.fileSize } }

    // MARK: Songs

    func add(_ newSongs: [Song]) {
        guard !newSongs.isEmpty else { return }
        songs.append(contentsOf: newSongs)
        didChange()
    }

    func update(_ updated: [Song]) {
        guard !updated.isEmpty else { return }
        for song in updated {
            if let i = songIndex[song.id] { songs[i] = song }
        }
        didChange()
        if let current = Player.shared.currentSong, updated.contains(where: { $0.id == current.id }) {
            Player.shared.refreshNowPlayingInfo()
        }
    }

    func update(_ song: Song) { update([song]) }

    func modify(_ id: UUID, _ change: (inout Song) -> Void) {
        guard let i = songIndex[id] else { return }
        change(&songs[i])
        didChange()
    }

    func toggleFavorite(_ id: UUID) { modify(id) { $0.isFavorite.toggle() } }

    func markPlayed(_ id: UUID) { modify(id) { $0.lastPlayed = Date() } }

    func incrementPlayCount(_ id: UUID) { modify(id) { $0.playCount += 1 } }

    /// Removes songs and their audio files. Artwork that nothing else uses is deleted too.
    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        Player.shared.removeSongs(ids)
        let removed = songs.filter { ids.contains($0.id) }
        songs.removeAll { ids.contains($0.id) }
        for i in playlists.indices {
            playlists[i].songIDs.removeAll { ids.contains($0) }
        }
        let fm = FileManager.default
        for song in removed {
            try? fm.removeItem(at: song.fileURL)
        }
        collectGarbage()
        didChange()
    }

    func deleteEverything() {
        delete(Set(songs.map(\.id)))
        playlists.removeAll()
        didChange()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String, details: String = "", songIDs: [UUID] = [], artworkID: String? = nil) -> Playlist {
        let playlist = Playlist(
            name: name.isEmpty ? "New Playlist" : name,
            details: details,
            songIDs: songIDs,
            artworkID: artworkID
        )
        playlists.insert(playlist, at: 0)
        didChange()
        return playlist
    }

    func modifyPlaylist(_ id: UUID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[i])
        playlists[i].dateModified = Date()
        didChange()
    }

    func addSongs(_ ids: [UUID], to playlistID: UUID) {
        modifyPlaylist(playlistID) { $0.songIDs.append(contentsOf: ids) }
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        collectGarbage()
        didChange()
    }

    // MARK: Internals

    private func didChange() {
        rebuild()
        scheduleSave()
    }

    private func rebuild() {
        songIndex = Dictionary(songs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        let byAlbum = Dictionary(grouping: songs, by: \.albumKey)
        var newAlbums: [Album] = byAlbum.map { key, members in
            let sorted = members.sorted(by: Song.albumOrder)
            let first = sorted[0]
            return Album(
                id: key,
                title: first.displayAlbum,
                artist: first.displayAlbumArtist,
                year: sorted.compactMap(\.year).max(),
                genre: sorted.first(where: { !$0.genre.isEmpty })?.genre ?? "",
                songs: sorted
            )
        }
        newAlbums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        albums = newAlbums
        albumIndex = Dictionary(newAlbums.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })

        let byArtist = Dictionary(grouping: newAlbums, by: \.artistID)
        let newArtists: [Artist] = byArtist.map { key, albums in
            Artist(id: key, name: albums[0].artist, albums: albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) })
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        artists = newArtists
        artistIndex = Dictionary(newArtists.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })

        let byGenre = Dictionary(grouping: songs.filter { !$0.genre.isEmpty }, by: { $0.genre.lowercased() })
        let newGenres: [Genre] = byGenre.map { key, members in
            Genre(id: key, name: members[0].genre, songs: members.sorted(by: Song.albumOrder))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        genres = newGenres
        genreIndex = Dictionary(newGenres.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Deletes artwork and animated covers no song or playlist references.
    func collectGarbage() {
        let usedArtwork = Set(songs.compactMap(\.artworkID) + playlists.compactMap(\.artworkID))
        let usedAnimated = Set(songs.compactMap(\.animatedCoverFile))
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: Paths.artwork, includingPropertiesForKeys: nil) {
            for file in files where !usedArtwork.contains(file.deletingPathExtension().lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
        if let files = try? fm.contentsOfDirectory(at: Paths.animatedCovers, includingPropertiesForKeys: nil) {
            for file in files where !usedAnimated.contains(file.lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let snapshot = Snapshot(songs: songs, playlists: playlists)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Paths.libraryFile, options: .atomic)
    }
}
