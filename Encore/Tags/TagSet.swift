import Foundation

/// A format-neutral set of tags, read from or written to an audio file.
struct TagSet: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var composer: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var trackCount: Int?
    var discNumber: Int?
    var discCount: Int?
    var comment: String?
    var lyrics: String?
    var artwork: Data?

    /// Fills any empty field from `other`.
    mutating func fillMissing(from other: TagSet) {
        func pick(_ a: String?, _ b: String?) -> String? {
            if let a, !a.isEmpty { return a }
            return b
        }
        title = pick(title, other.title)
        artist = pick(artist, other.artist)
        album = pick(album, other.album)
        albumArtist = pick(albumArtist, other.albumArtist)
        composer = pick(composer, other.composer)
        genre = pick(genre, other.genre)
        comment = pick(comment, other.comment)
        lyrics = pick(lyrics, other.lyrics)
        year = year ?? other.year
        trackNumber = trackNumber ?? other.trackNumber
        trackCount = trackCount ?? other.trackCount
        discNumber = discNumber ?? other.discNumber
        discCount = discCount ?? other.discCount
        artwork = artwork ?? other.artwork
    }

    /// Parses "3", "3/12", "03 of 12".
    static func parsePair(_ text: String?) -> (Int?, Int?) {
        guard let text else { return (nil, nil) }
        let parts = text.split(whereSeparator: { !$0.isNumber }).map { Int($0) }
        return (parts.first ?? nil, parts.count > 1 ? parts[1] : nil)
    }

    /// First run of 4 digits, e.g. "2019-05-03" → 2019.
    static func parseYear(_ text: String?) -> Int? {
        guard let text else { return nil }
        let runs = text.split(whereSeparator: { !$0.isASCII || !$0.isNumber })
        if let year = runs.first(where: { $0.count == 4 }) { return Int(year) }
        return runs.first.flatMap { Int($0) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
