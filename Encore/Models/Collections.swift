import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var details: String = ""
    var songIDs: [UUID] = []
    var artworkID: String?
    var dateCreated = Date()
    var dateModified = Date()
}

/// Albums, artists and genres are derived from songs every time the library changes.
struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let year: Int?
    let genre: String
    let songs: [Song]

    var artistID: String { artist.lowercased() }
    var artworkID: String? { songs.first(where: { $0.artworkID != nil })?.artworkID }
    var animatedCoverURL: URL? { songs.first(where: { $0.animatedCoverFile != nil })?.animatedCoverURL }
    var dateAdded: Date { songs.map(\.dateAdded).max() ?? .distantPast }
    var lastPlayed: Date? { songs.compactMap(\.lastPlayed).max() }
    var playCount: Int { songs.reduce(0) { $0 + $1.playCount } }
    var duration: Double { songs.reduce(0) { $0 + $1.duration } }
    var isExplicit: Bool { songs.contains(where: \.isExplicit) }
    var isLossless: Bool { !songs.isEmpty && songs.allSatisfy(\.isLossless) }
    var discCount: Int { Set(songs.map { $0.discNumber ?? 1 }).count }

    var subtitle: String {
        [genre.isEmpty ? nil : genre, year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }
}

struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    let albums: [Album]

    var songs: [Song] { albums.flatMap(\.songs) }
    var artworkID: String? { albums.lazy.compactMap(\.artworkID).first }
}

struct Genre: Identifiable, Hashable {
    let id: String
    let name: String
    let songs: [Song]

    var artworkID: String? { songs.lazy.compactMap(\.artworkID).first }
}

enum StableHash {
    /// djb2 — unlike `hashValue`, stays the same between launches.
    static func of(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &<< 5) &+ hash &+ UInt64(byte) }
        return Int(hash % UInt64(Int.max))
    }
}

extension Double {
    /// 3:07 / 1:02:03
    var timeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 hour, 4 minutes"
    var longDurationString: String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = self >= 3600 ? [.hour, .minute] : [.minute]
        return f.string(from: self) ?? ""
    }
}
