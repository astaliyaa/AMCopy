import Foundation

/// Copies audio files into the library and reads their tags.
enum Importer {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "aifc", "flac", "caf", "alac",
    ]

    @MainActor private static var isScanningInbox = false

    /// Imports files and/or folders (folders are searched recursively).
    /// `move` is used for files already inside the app's own Documents folder.
    @MainActor
    static func importItems(at urls: [URL], library: Library, move: Bool = false) async {
        guard !urls.isEmpty else { return }
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

        let files = await Task.detached(priority: .userInitiated) { collectAudioFiles(in: urls) }.value
        guard !files.isEmpty else { return }

        library.importStatus = ImportStatus(done: 0, total: files.count)
        var batch: [Song] = []
        for (i, file) in files.enumerated() {
            let song = await Task.detached(priority: .userInitiated) {
                await makeSong(from: file, move: move)
            }.value
            if let song { batch.append(song) }
            library.importStatus = ImportStatus(done: i + 1, total: files.count)
            if batch.count >= 20 {
                library.add(batch)
                batch.removeAll()
            }
        }
        library.add(batch)
        library.importStatus = nil
    }

    /// Imports anything dropped into Documents (Files app / Finder / Apple Devices file sharing).
    @MainActor
    static func scanInbox(library: Library) async {
        guard !isScanningInbox else { return }
        isScanningInbox = true
        defer { isScanningInbox = false }
        await importItems(at: [Paths.inbox], library: library, move: true)
    }

    /// Handles a file opened in the app from another app ("Open in Encore").
    @MainActor
    static func importOpenedFile(_ url: URL, library: Library) async {
        let insideSandbox = url.standardizedFileURL.path.hasPrefix(Paths.inbox.standardizedFileURL.path)
        await importItems(at: [url], library: library, move: insideSandbox)
    }

    static func collectAudioFiles(in urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in enumerator where audioExtensions.contains(file.pathExtension.lowercased()) {
                    result.append(file)
                }
            } else if audioExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func makeSong(from source: URL, move: Bool) async -> Song? {
        let fm = FileManager.default
        let folder = source.deletingLastPathComponent()
        let originalName = source.lastPathComponent
        let sidecarLyrics = try? String(contentsOf: source.deletingPathExtension().appendingPathExtension("lrc"), encoding: .utf8)
        let folderArtwork = folderCover(in: folder)

        let destination = Paths.uniqueURL(in: Paths.music, fileName: originalName)
        do {
            if move {
                try fm.moveItem(at: source, to: destination)
            } else {
                try fm.copyItem(at: source, to: destination)
            }
        } catch {
            return nil
        }

        let info = await MetadataReader.read(url: destination)
        var tags = info.tags
        if (tags.lyrics ?? "").isEmpty { tags.lyrics = sidecarLyrics }
        if tags.artwork == nil { tags.artwork = folderArtwork }

        let baseName = (originalName as NSString).deletingPathExtension
        var song = Song(fileName: destination.lastPathComponent, originalFileName: originalName, title: baseName)
        song.title = tags.title?.nilIfEmpty ?? baseName
        song.artist = tags.artist ?? ""
        song.album = tags.album ?? ""
        song.albumArtist = tags.albumArtist ?? ""
        song.composer = tags.composer ?? ""
        song.genre = tags.genre ?? ""
        song.year = tags.year
        song.trackNumber = tags.trackNumber
        song.trackCount = tags.trackCount
        song.discNumber = tags.discNumber
        song.discCount = tags.discCount
        song.comment = tags.comment ?? ""
        song.lyrics = tags.lyrics ?? ""
        song.duration = info.duration
        song.isLossless = info.isLossless
        song.artworkID = tags.artwork.flatMap { ArtworkStore.save($0) }
        let attributes = try? fm.attributesOfItem(atPath: destination.path)
        song.fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        // Untagged file: try "Artist - Title" / "01 - Title" from the file name.
        if tags.title == nil && tags.artist == nil {
            let guess = FilenamePattern.guess(baseName)
            song.title = guess.title
            if let artist = guess.artist { song.artist = artist }
            if let track = guess.track { song.trackNumber = track }
        }
        return song
    }

    private static func folderCover(in folder: URL) -> Data? {
        let names = ["cover", "folder", "front", "album", "artwork"]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for name in names {
            if let match = files.first(where: {
                let ext = $0.pathExtension.lowercased()
                return $0.deletingPathExtension().lastPathComponent.lowercased() == name && ["jpg", "jpeg", "png"].contains(ext)
            }) {
                return try? Data(contentsOf: match)
            }
        }
        return nil
    }
}

/// mp3tag-style "%artist% - %title%" parsing.
enum FilenamePattern {
    static let defaultPattern = "%artist% - %title%"

    static let tokens: [String: TagField?] = [
        "title": .title, "artist": .artist, "album": .album, "albumartist": .albumArtist,
        "composer": .composer, "genre": .genre, "year": .year, "track": .track, "disc": .disc,
        "dummy": nil,
    ]

    /// Returns the fields captured from `fileName` (without extension), or nil if it doesn't match.
    static func parse(_ fileName: String, pattern: String) -> [TagField: String]? {
        var regex = "^"
        var fields: [TagField?] = []
        var rest = Substring(pattern)
        while let start = rest.firstIndex(of: "%") {
            regex += NSRegularExpression.escapedPattern(for: String(rest[..<start]))
            let afterStart = rest.index(after: start)
            guard let end = rest[afterStart...].firstIndex(of: "%") else {
                rest = rest[start...]
                break
            }
            let name = rest[afterStart..<end].lowercased()
            if let field = tokens[name] {
                let numeric = field?.isNumeric ?? false
                regex += numeric ? "\\s*(\\d+)\\s*" : "(.+?)"
                fields.append(field)
            } else {
                regex += NSRegularExpression.escapedPattern(for: "%\(name)%")
            }
            rest = rest[rest.index(after: end)...]
        }
        regex += NSRegularExpression.escapedPattern(for: String(rest)) + "$"

        guard !fields.isEmpty,
              let expression = try? NSRegularExpression(pattern: regex),
              let match = expression.firstMatch(in: fileName, range: NSRange(fileName.startIndex..., in: fileName))
        else { return nil }

        var result: [TagField: String] = [:]
        for (i, field) in fields.enumerated() {
            guard let field, let range = Range(match.range(at: i + 1), in: fileName) else { continue }
            result[field] = fileName[range].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Best guess for untagged files.
    static func guess(_ baseName: String) -> (title: String, artist: String?, track: Int?) {
        let cleaned = baseName.replacingOccurrences(of: "_", with: " ")
        let parts = cleaned.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else {
            // "01 Song Name" / "01. Song Name"
            let scanner = cleaned.prefix(while: \.isNumber)
            if !scanner.isEmpty, scanner.count <= 3, let n = Int(scanner) {
                let title = cleaned.dropFirst(scanner.count).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
                if !title.isEmpty { return (title, nil, n) }
            }
            return (cleaned, nil, nil)
        }
        if let n = Int(parts[0]), parts[0].count <= 3 {
            if parts.count >= 3 { return (parts[2...].joined(separator: " - "), parts[1], n) }
            return (parts[1], nil, n)
        }
        return (parts[1...].joined(separator: " - "), parts[0], nil)
    }
}
