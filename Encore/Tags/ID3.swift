import Foundation

/// Minimal ID3v2.2/2.3/2.4 reader and v2.3/2.4 writer.
/// Unknown frames are preserved when rewriting a v2.3 or v2.4 tag.
enum ID3 {
    struct Frame {
        var id: String
        var flags: UInt16
        var data: Data
    }

    struct Tag {
        var majorVersion: UInt8
        var frames: [Frame]
        /// Bytes the tag occupies at the start of the file (header + body + footer).
        var totalSize: Int
    }

    enum WriteError: LocalizedError {
        case unreadable
        var errorDescription: String? { "The MP3 file couldn't be read." }
    }

    // MARK: - Reading

    static func readTagSet(url: URL) -> TagSet? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), header.count == 10,
              header.starts(with: [0x49, 0x44, 0x33]) else { return nil }
        let size = syncsafe([UInt8](header)[6..<10])
        guard let body = try? handle.read(upToCount: size) else { return nil }
        guard let tag = parse(header + body) else { return nil }
        return tagSet(from: tag)
    }

    /// Parses a tag at the start of `data` (which must begin at index 0).
    static func parse(_ data: Data) -> Tag? {
        guard data.count >= 10, data.starts(with: [0x49, 0x44, 0x33]) else { return nil }
        let header = [UInt8](data.prefix(10))
        let major = header[3]
        let flags = header[5]
        guard (2...4).contains(major) else { return nil }
        let size = syncsafe(header[6..<10])
        let hasFooter = major == 4 && flags & 0x10 != 0
        let total = 10 + size + (hasFooter ? 10 : 0)
        guard data.count >= 10 + size else { return nil }

        var body = [UInt8](data[10..<(10 + size)])
        let wholeTagUnsync = flags & 0x80 != 0
        if wholeTagUnsync && major <= 3 { body = removeUnsync(body) }

        var pos = 0
        if flags & 0x40 != 0, body.count >= 4 {
            if major == 3 { pos = 4 + Int(be32(body, 0)) }
            if major == 4 { pos = syncsafe(body[0..<4]) }
        }

        let idLength = major == 2 ? 3 : 4
        let headerLength = major == 2 ? 6 : 10
        var frames: [Frame] = []

        while pos + headerLength <= body.count {
            let idBytes = body[pos..<(pos + idLength)]
            guard idBytes.allSatisfy({ (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) }),
                  let id = String(bytes: idBytes, encoding: .ascii) else { break }

            var frameSize: Int
            var frameFlags: UInt16 = 0
            switch major {
            case 2:
                frameSize = Int(body[pos + 3]) << 16 | Int(body[pos + 4]) << 8 | Int(body[pos + 5])
            case 3:
                frameSize = Int(be32(body, pos + 4))
                frameFlags = UInt16(body[pos + 8]) << 8 | UInt16(body[pos + 9])
            default:
                frameSize = syncsafe(body[(pos + 4)..<(pos + 8)])
                frameFlags = UInt16(body[pos + 8]) << 8 | UInt16(body[pos + 9])
                // Some writers (old iTunes) wrote plain sizes in v2.4.
                let plain = Int(be32(body, pos + 4))
                if plain != frameSize, !isFrameStart(body, at: pos + headerLength + frameSize),
                   isFrameStart(body, at: pos + headerLength + plain) {
                    frameSize = plain
                }
            }

            let start = pos + headerLength
            guard frameSize >= 0, start + frameSize <= body.count else { break }
            var frameData = Array(body[start..<(start + frameSize)])

            if major == 4 {
                let format = UInt8(frameFlags & 0xFF)
                if format & 0x01 != 0, frameData.count >= 4 { frameData.removeFirst(4) }
                if format & 0x02 != 0 || wholeTagUnsync { frameData = removeUnsync(frameData) }
                frameFlags &= 0xFFFC
            }

            frames.append(Frame(id: id, flags: frameFlags, data: Data(frameData)))
            pos = start + frameSize
        }

        return Tag(majorVersion: major, frames: frames, totalSize: total)
    }

    static func tagSet(from tag: Tag) -> TagSet {
        let v2 = tag.majorVersion == 2
        func frames(_ v3: String, _ v2id: String) -> [Frame] {
            tag.frames.filter { $0.id == (v2 ? v2id : v3) }
        }
        func text(_ v3: String, _ v2id: String) -> String? {
            frames(v3, v2id).first.flatMap { decodeTextFrame($0.data) }
        }

        var t = TagSet()
        t.title = text("TIT2", "TT2")
        t.artist = text("TPE1", "TP1")
        t.album = text("TALB", "TAL")
        t.albumArtist = text("TPE2", "TP2")
        t.composer = text("TCOM", "TCM")
        t.genre = text("TCON", "TCO").map(normalizeGenre)
        t.year = TagSet.parseYear(text("TDRC", "TYE") ?? text("TYER", "TYE"))
        (t.trackNumber, t.trackCount) = TagSet.parsePair(text("TRCK", "TRK"))
        (t.discNumber, t.discCount) = TagSet.parsePair(text("TPOS", "TPA"))

        for frame in frames("COMM", "COM") {
            if let comment = decodeLanguageFrame(frame.data),
               !comment.0.hasPrefix("iTun"), !comment.1.isEmpty {
                t.comment = comment.1
                break
            }
        }
        for frame in frames("USLT", "ULT") {
            if let lyrics = decodeLanguageFrame(frame.data), !lyrics.1.isEmpty {
                t.lyrics = lyrics.1
                break
            }
        }

        let pictures = frames("APIC", "PIC").compactMap { decodePicture($0.data, v2: v2) }
        t.artwork = (pictures.first(where: { $0.type == 3 }) ?? pictures.first)?.data
        return t
    }

    // MARK: - Writing

    /// Text frames we own. Everything else in the tag is kept.
    private static let managedFrames: Set<String> = [
        "TIT2", "TPE1", "TALB", "TPE2", "TCOM", "TCON", "TYER", "TDRC", "TRCK", "TPOS", "USLT", "APIC",
    ]

    static func write(_ tags: TagSet, to url: URL) throws {
        guard let original = try? Data(contentsOf: url) else { throw WriteError.unreadable }
        let existing = parse(original)
        let version: UInt8 = existing?.majorVersion == 4 ? 4 : 3

        var frames: [Frame] = (existing?.majorVersion ?? 3) >= 3 ? existing?.frames ?? [] : []
        frames.removeAll { frame in
            if managedFrames.contains(frame.id) { return true }
            if frame.id == "COMM" {
                let description = decodeLanguageFrame(frame.data)?.0 ?? ""
                return !description.hasPrefix("iTun")
            }
            // Compressed / encrypted / grouped frames can't be carried over safely.
            let format = UInt8(frame.flags & 0xFF)
            let unsafeMask: UInt8 = version == 4 ? 0x4C : 0xE0
            return format & unsafeMask != 0
        }

        func addText(_ id: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            frames.append(textFrame(id, value, version: version))
        }
        func pair(_ a: Int?, _ b: Int?) -> String? {
            guard let a else { return nil }
            return b.map { "\(a)/\($0)" } ?? "\(a)"
        }

        addText("TIT2", tags.title)
        addText("TPE1", tags.artist)
        addText("TALB", tags.album)
        addText("TPE2", tags.albumArtist)
        addText("TCOM", tags.composer)
        addText("TCON", tags.genre)
        addText(version == 4 ? "TDRC" : "TYER", tags.year.map(String.init))
        addText("TRCK", pair(tags.trackNumber, tags.trackCount))
        addText("TPOS", pair(tags.discNumber, tags.discCount))
        if let comment = tags.comment, !comment.isEmpty {
            frames.append(languageFrame("COMM", comment, version: version))
        }
        if let lyrics = tags.lyrics, !lyrics.isEmpty {
            frames.append(languageFrame("USLT", lyrics, version: version))
        }
        if let artwork = tags.artwork {
            frames.append(pictureFrame(artwork))
        }

        // Audio sits between the old tag and an optional 128-byte ID3v1 tag at the end.
        let audioStart = min(existing?.totalSize ?? 0, original.count)
        var audioEnd = original.count
        if original.count - audioStart >= 128,
           original[(original.count - 128)..<(original.count - 125)].elementsEqual([0x54, 0x41, 0x47]) {
            audioEnd -= 128
        }

        var output = serialize(frames, version: version, padding: 2048)
        output.append(original[audioStart..<audioEnd])
        try output.write(to: url, options: .atomic)
    }

    static func serialize(_ frames: [Frame], version: UInt8, padding: Int) -> Data {
        var body = Data()
        for frame in frames where frame.id.utf8.count == 4 {
            body.append(contentsOf: Array(frame.id.utf8))
            body.append(contentsOf: version == 4 ? syncsafeBytes(frame.data.count) : be32Bytes(frame.data.count))
            body.append(contentsOf: [UInt8(frame.flags >> 8) & (version == 4 ? 0x70 : 0xE0), 0])
            body.append(frame.data)
        }
        body.append(Data(count: padding))
        var tag = Data([0x49, 0x44, 0x33, version, 0, 0])
        tag.append(contentsOf: syncsafeBytes(body.count))
        tag.append(body)
        return tag
    }

    // MARK: - Frame builders

    private static func encoding(for strings: [String], version: UInt8) -> UInt8 {
        if strings.allSatisfy({ $0.canBeConverted(to: .isoLatin1) }) { return 0 }
        return version == 4 ? 3 : 1
    }

    private static func encode(_ string: String, encoding: UInt8, terminated: Bool) -> [UInt8] {
        var out: [UInt8]
        switch encoding {
        case 0: out = Array(string.data(using: .isoLatin1, allowLossyConversion: true) ?? Data())
        case 3: out = Array(string.utf8)
        default: out = [0xFF, 0xFE] + string.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        }
        if terminated { out += (encoding == 1 || encoding == 2) ? [0, 0] : [0] }
        return out
    }

    static func textFrame(_ id: String, _ value: String, version: UInt8) -> Frame {
        let enc = encoding(for: [value], version: version)
        return Frame(id: id, flags: 0, data: Data([enc] + encode(value, encoding: enc, terminated: false)))
    }

    static func languageFrame(_ id: String, _ value: String, version: UInt8) -> Frame {
        let enc = encoding(for: [value], version: version)
        var bytes: [UInt8] = [enc] + Array("eng".utf8)
        bytes += encode("", encoding: enc, terminated: true)
        bytes += encode(value, encoding: enc, terminated: false)
        return Frame(id: id, flags: 0, data: Data(bytes))
    }

    static func pictureFrame(_ image: Data) -> Frame {
        let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
        var bytes: [UInt8] = [0]
        bytes += Array((isPNG ? "image/png" : "image/jpeg").utf8) + [0]
        bytes += [3, 0] // front cover, empty description
        return Frame(id: "APIC", flags: 0, data: Data(bytes) + image)
    }

    // MARK: - Frame decoding

    static func decodeTextFrame(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let enc = bytes.first else { return nil }
        let value = decodeString(Array(bytes.dropFirst()), encoding: enc)
            .components(separatedBy: "\u{0}")
            .map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        return value.isEmpty ? nil : value
    }

    /// COMM / USLT: encoding, 3-byte language, description\0, text.
    static func decodeLanguageFrame(_ data: Data) -> (String, String)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let enc = bytes[0]
        let (description, next) = readTerminated(bytes, from: 4, encoding: enc)
        let text = decodeString(Array(bytes[min(next, bytes.count)...]), encoding: enc)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"))
        return (description, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// APIC (v2.3/2.4) or PIC (v2.2).
    static func decodePicture(_ data: Data, v2: Bool) -> (type: UInt8, data: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        let enc = bytes[0]
        var pos: Int
        if v2 {
            pos = 4 // encoding + 3-char format
        } else {
            guard let end = bytes[1...].firstIndex(of: 0) else { return nil }
            pos = end + 1
        }
        guard pos < bytes.count else { return nil }
        let type = bytes[pos]
        let (_, imageStart) = readTerminated(bytes, from: pos + 1, encoding: enc)
        guard imageStart < bytes.count else { return nil }
        return (type, Data(bytes[imageStart...]))
    }

    private static func readTerminated(_ bytes: [UInt8], from start: Int, encoding: UInt8) -> (String, Int) {
        guard start < bytes.count else { return ("", bytes.count) }
        let wide = encoding == 1 || encoding == 2
        var i = start
        if wide {
            while i + 1 < bytes.count, !(bytes[i] == 0 && bytes[i + 1] == 0) { i += 2 }
            let value = decodeString(Array(bytes[start..<min(i, bytes.count)]), encoding: encoding)
            return (value, min(i + 2, bytes.count))
        }
        while i < bytes.count, bytes[i] != 0 { i += 1 }
        return (decodeString(Array(bytes[start..<i]), encoding: encoding), min(i + 1, bytes.count))
    }

    private static func decodeString(_ raw: [UInt8], encoding: UInt8) -> String {
        var bytes = raw
        switch encoding {
        case 1, 2:
            if bytes.count % 2 == 1 { bytes.removeLast() }
            while bytes.count >= 2, bytes[bytes.count - 1] == 0, bytes[bytes.count - 2] == 0 { bytes.removeLast(2) }
            if encoding == 2 { return String(bytes: bytes, encoding: .utf16BigEndian) ?? "" }
            if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
                return String(bytes: bytes, encoding: .utf16) ?? ""
            }
            return String(bytes: bytes, encoding: .utf16LittleEndian) ?? ""
        case 3:
            while bytes.last == 0 { bytes.removeLast() }
            return String(decoding: bytes, as: UTF8.self)
        default:
            while bytes.last == 0 { bytes.removeLast() }
            return String(bytes: bytes, encoding: .isoLatin1) ?? ""
        }
    }

    // MARK: - Genres

    /// "(17)", "17", "(17)Rock" → "Rock".
    static func normalizeGenre(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("("), let close = s.firstIndex(of: ")") {
            let number = s[s.index(after: s.startIndex)..<close]
            let rest = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            if let n = Int(number), let name = genreName(n) { return name }
        }
        if let n = Int(s), let name = genreName(n) { return name }
        return s
    }

    static func genreName(_ index: Int) -> String? {
        genres.indices.contains(index) ? genres[index] : nil
    }

    static let genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
        "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
        "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop",
        "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game",
        "Sound Clip", "Gospel", "Noise", "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative",
        "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial",
        "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
        "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka",
        "Retro", "Musical", "Rock & Roll", "Hard Rock",
    ]

    // MARK: - Byte helpers

    static func syncsafe<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
    }

    static func syncsafeBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }

    static func be32Bytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func isFrameStart(_ body: [UInt8], at pos: Int) -> Bool {
        if pos == body.count { return true }
        guard pos + 4 <= body.count else { return false }
        if body[pos] == 0 { return true } // padding
        return body[pos..<(pos + 4)].allSatisfy { (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) }
    }

    static func removeUnsync(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            out.append(bytes[i])
            if bytes[i] == 0xFF, i + 1 < bytes.count, bytes[i + 1] == 0 { i += 2 } else { i += 1 }
        }
        return out
    }
}
