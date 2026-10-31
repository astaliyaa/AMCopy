import Foundation

/// Reads and rewrites FLAC Vorbis comments + front-cover PICTURE blocks.
enum FLACTags {
    struct Block {
        var type: UInt8
        var data: Data
    }

    enum FLACError: LocalizedError {
        case notFLAC
        var errorDescription: String? { "This doesn't look like a valid FLAC file." }
    }

    private static let managedKeys: Set<String> = [
        "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "ALBUM ARTIST", "COMPOSER", "GENRE", "DATE", "YEAR",
        "TRACKNUMBER", "TRACKTOTAL", "TOTALTRACKS", "DISCNUMBER", "DISCTOTAL", "TOTALDISCS",
        "COMMENT", "DESCRIPTION", "LYRICS", "UNSYNCEDLYRICS",
    ]

    // MARK: Reading

    static func read(url: URL) -> TagSet? {
        guard let metadata = try? readMetadata(url) else { return nil }
        let blocks = metadata.0
        var t = TagSet()
        if let comments = blocks.first(where: { $0.type == 4 }).map({ parseComments($0.data).comments }) {
            func value(_ keys: String...) -> String? {
                for key in keys {
                    if let v = comments.first(where: { $0.0 == key })?.1, !v.isEmpty { return v }
                }
                return nil
            }
            t.title = value("TITLE")
            t.artist = value("ARTIST")
            t.album = value("ALBUM")
            t.albumArtist = value("ALBUMARTIST", "ALBUM ARTIST")
            t.composer = value("COMPOSER")
            t.genre = value("GENRE")
            t.year = TagSet.parseYear(value("DATE", "YEAR"))
            let track = TagSet.parsePair(value("TRACKNUMBER"))
            t.trackNumber = track.0
            t.trackCount = track.1 ?? value("TRACKTOTAL", "TOTALTRACKS").flatMap { Int($0) }
            let disc = TagSet.parsePair(value("DISCNUMBER"))
            t.discNumber = disc.0
            t.discCount = disc.1 ?? value("DISCTOTAL", "TOTALDISCS").flatMap { Int($0) }
            t.comment = value("COMMENT", "DESCRIPTION")
            t.lyrics = value("LYRICS", "UNSYNCEDLYRICS")
        }
        let pictures = blocks.filter { $0.type == 6 }.compactMap { parsePicture($0.data) }
        t.artwork = (pictures.first(where: { $0.type == 3 }) ?? pictures.first)?.data
        return t
    }

    /// Returns metadata blocks and the byte offset where audio frames start.
    static func readMetadata(_ url: URL) throws -> ([Block], Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var offset = 0
        var magic = try handle.read(upToCount: 4) ?? Data()
        // Skip a (non-standard) ID3v2 tag in front of the stream.
        if magic.starts(with: [0x49, 0x44, 0x33]) {
            let rest = try handle.read(upToCount: 6) ?? Data()
            let header = [UInt8](magic + rest)
            guard header.count == 10 else { throw FLACError.notFLAC }
            offset = 10 + ID3.syncsafe(header[6..<10])
            try handle.seek(toOffset: UInt64(offset))
            magic = try handle.read(upToCount: 4) ?? Data()
        }
        guard magic.elementsEqual([0x66, 0x4C, 0x61, 0x43]) else { throw FLACError.notFLAC }
        offset += 4

        var blocks: [Block] = []
        var isLast = false
        while !isLast {
            guard let header = try handle.read(upToCount: 4), header.count == 4 else { throw FLACError.notFLAC }
            let h = [UInt8](header)
            isLast = h[0] & 0x80 != 0
            let length = Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
            let data = try handle.read(upToCount: length) ?? Data()
            guard data.count == length else { throw FLACError.notFLAC }
            blocks.append(Block(type: h[0] & 0x7F, data: data))
            offset += 4 + length
        }
        return (blocks, offset)
    }

    // MARK: Writing

    static func write(_ tags: TagSet, to url: URL) throws {
        let (blocks, audioOffset) = try readMetadata(url)
        let handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: UInt64(audioOffset))
        let audio = try handle.readToEnd() ?? Data()
        try handle.close()

        let existing = blocks.first(where: { $0.type == 4 }).map { parseComments($0.data) }
        let vendor = existing?.vendor ?? "Encore"
        var comments = (existing?.comments ?? []).filter { !managedKeys.contains($0.0) }

        func add(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            comments.append((key, value))
        }
        add("TITLE", tags.title)
        add("ARTIST", tags.artist)
        add("ALBUM", tags.album)
        add("ALBUMARTIST", tags.albumArtist)
        add("COMPOSER", tags.composer)
        add("GENRE", tags.genre)
        add("DATE", tags.year.map(String.init))
        add("TRACKNUMBER", tags.trackNumber.map(String.init))
        add("TRACKTOTAL", tags.trackCount.map(String.init))
        add("DISCNUMBER", tags.discNumber.map(String.init))
        add("DISCTOTAL", tags.discCount.map(String.init))
        add("COMMENT", tags.comment)
        add("LYRICS", tags.lyrics)

        // STREAMINFO first, then everything we don't manage (seek table, cue sheet, app blocks…).
        var newBlocks = blocks.filter { $0.type != 1 && $0.type != 4 && $0.type != 6 }
        newBlocks.append(Block(type: 4, data: buildComments(vendor: vendor, comments: comments)))
        if let artwork = tags.artwork, artwork.count < 0xFF_FF00 {
            newBlocks.append(Block(type: 6, data: buildPicture(artwork)))
        }
        newBlocks.append(Block(type: 1, data: Data(count: 4096)))

        var output = Data([0x66, 0x4C, 0x61, 0x43])
        for (i, block) in newBlocks.enumerated() {
            let isLast = i == newBlocks.count - 1
            let length = block.data.count
            output.append(contentsOf: [
                (isLast ? 0x80 : 0) | block.type,
                UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
            ])
            output.append(block.data)
        }
        output.append(audio)
        try output.write(to: url, options: .atomic)
    }

    // MARK: Block coding

    static func parseComments(_ data: Data) -> (vendor: String, comments: [(String, String)]) {
        var r = ByteReader(data)
        guard let vendorLength = r.u32le(), let vendorBytes = r.take(Int(vendorLength)),
              let count = r.u32le() else { return ("", []) }
        var comments: [(String, String)] = []
        for _ in 0..<min(Int(count), 10_000) {
            guard let length = r.u32le(), let bytes = r.take(Int(length)) else { break }
            let entry = String(decoding: bytes, as: UTF8.self)
            guard let eq = entry.firstIndex(of: "=") else { continue }
            comments.append((entry[..<eq].uppercased(), String(entry[entry.index(after: eq)...])))
        }
        return (String(decoding: vendorBytes, as: UTF8.self), comments)
    }

    static func buildComments(vendor: String, comments: [(String, String)]) -> Data {
        var d = Data()
        func appendLE(_ v: Int) {
            d.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
        }
        let vendorBytes = Array(vendor.utf8)
        appendLE(vendorBytes.count)
        d.append(contentsOf: vendorBytes)
        appendLE(comments.count)
        for (key, value) in comments {
            let bytes = Array("\(key)=\(value)".utf8)
            appendLE(bytes.count)
            d.append(contentsOf: bytes)
        }
        return d
    }

    static func parsePicture(_ data: Data) -> (type: UInt32, data: Data)? {
        var r = ByteReader(data)
        guard let type = r.u32be(),
              let mimeLength = r.u32be(), r.take(Int(mimeLength)) != nil,
              let descriptionLength = r.u32be(), r.take(Int(descriptionLength)) != nil,
              r.take(16) != nil, // width, height, depth, colors
              let length = r.u32be(), let bytes = r.take(Int(length)) else { return nil }
        return (type, Data(bytes))
    }

    static func buildPicture(_ image: Data) -> Data {
        let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
        let mime = Array((isPNG ? "image/png" : "image/jpeg").utf8)
        var d = Data()
        d.append(contentsOf: ID3.be32Bytes(3))
        d.append(contentsOf: ID3.be32Bytes(mime.count))
        d.append(contentsOf: mime)
        d.append(contentsOf: ID3.be32Bytes(0)) // description
        d.append(contentsOf: [UInt8](repeating: 0, count: 16))
        d.append(contentsOf: ID3.be32Bytes(image.count))
        d.append(image)
        return d
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private var pos = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func take(_ n: Int) -> ArraySlice<UInt8>? {
        guard n >= 0, pos + n <= bytes.count else { return nil }
        defer { pos += n }
        return bytes[pos..<(pos + n)]
    }

    mutating func u32le() -> UInt32? {
        guard let b = take(4) else { return nil }
        return b.reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u32be() -> UInt32? {
        guard let b = take(4) else { return nil }
        return b.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
