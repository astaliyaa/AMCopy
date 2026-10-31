import Foundation

struct Song: Identifiable, Codable, Hashable {
    var id = UUID()
    /// File name inside `Paths.music`.
    var fileName: String
    /// Name of the file as it was imported (used by "Tag from File Name").
    var originalFileName: String
    var title: String
    var artist: String = ""
    var album: String = ""
    var albumArtist: String = ""
    var composer: String = ""
    var genre: String = ""
    var year: Int?
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var comment: String = ""
    var lyrics: String = ""
    var isExplicit = false
    var isLossless = false
    var duration: Double = 0
    var fileSize: Int64 = 0
    /// Static cover, stored in `Paths.artwork` (deduplicated by content hash).
    var artworkID: String?
    /// Looping video or GIF, stored in `Paths.animatedCovers`.
    var animatedCoverFile: String?
    var dateAdded = Date()
    var lastPlayed: Date?
    var playCount = 0
    var isFavorite = false

    var fileURL: URL { Paths.music.appendingPathComponent(fileName) }
    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }
    var animatedCoverURL: URL? { animatedCoverFile.map { Paths.animatedCovers.appendingPathComponent($0) } }

    var displayArtist: String { artist.isEmpty ? "Unknown Artist" : artist }
    var displayAlbum: String { album.isEmpty ? "Unknown Album" : album }
    var displayAlbumArtist: String {
        if !albumArtist.isEmpty { return albumArtist }
        return displayArtist
    }

    var albumKey: String { "\(displayAlbumArtist.lowercased())|\(displayAlbum.lowercased())" }
    var artistKey: String { displayAlbumArtist.lowercased() }

    /// Disc, then track, then title.
    static func albumOrder(_ a: Song, _ b: Song) -> Bool {
        let da = a.discNumber ?? 1, db = b.discNumber ?? 1
        if da != db { return da < db }
        let ta = a.trackNumber ?? Int.max, tb = b.trackNumber ?? Int.max
        if ta != tb { return ta < tb }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}

// MARK: - Tag fields (used by the tag editor and file writers)

enum TagField: String, CaseIterable, Hashable {
    case title, artist, album, albumArtist, composer, genre, year
    case track, trackCount, disc, discCount, comment, lyrics

    var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .albumArtist: "Album Artist"
        case .composer: "Composer"
        case .genre: "Genre"
        case .year: "Year"
        case .track: "Track"
        case .trackCount: "Track Count"
        case .disc: "Disc"
        case .discCount: "Disc Count"
        case .comment: "Comments"
        case .lyrics: "Lyrics"
        }
    }

    var isNumeric: Bool {
        switch self {
        case .year, .track, .trackCount, .disc, .discCount: true
        default: false
        }
    }
}

extension Song {
    func value(for field: TagField) -> String {
        switch field {
        case .title: title
        case .artist: artist
        case .album: album
        case .albumArtist: albumArtist
        case .composer: composer
        case .genre: genre
        case .year: year.map(String.init) ?? ""
        case .track: trackNumber.map(String.init) ?? ""
        case .trackCount: trackCount.map(String.init) ?? ""
        case .disc: discNumber.map(String.init) ?? ""
        case .discCount: discCount.map(String.init) ?? ""
        case .comment: comment
        case .lyrics: lyrics
        }
    }

    mutating func setValue(_ raw: String, for field: TagField) {
        let value = field == .lyrics ? raw : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = Int(value.filter(\.isNumber).prefix(9))
        switch field {
        case .title: title = value.isEmpty ? (originalFileName as NSString).deletingPathExtension : value
        case .artist: artist = value
        case .album: album = value
        case .albumArtist: albumArtist = value
        case .composer: composer = value
        case .genre: genre = value
        case .year: year = number
        case .track: trackNumber = number
        case .trackCount: trackCount = number
        case .disc: discNumber = number
        case .discCount: discCount = number
        case .comment: comment = value
        case .lyrics: lyrics = value
        }
    }

    /// The full set of tags this song should have in its file.
    func tagSet() -> TagSet {
        TagSet(
            title: title, artist: artist, album: album, albumArtist: albumArtist,
            composer: composer, genre: genre, year: year,
            trackNumber: trackNumber, trackCount: trackCount,
            discNumber: discNumber, discCount: discCount,
            comment: comment, lyrics: lyrics,
            artwork: artworkID.flatMap { ArtworkStore.data(for: $0) }
        )
    }
}
