import AVFoundation

/// Rewrites iTunes-style tags in .m4a files via a passthrough export (no re-encoding).
enum MP4Tagger {
    enum MP4Error: LocalizedError {
        case exportUnavailable
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .exportUnavailable: "This file can't be re-tagged."
            case .exportFailed(let reason): "Writing tags failed: \(reason)"
            }
        }
    }

    private static let managed: Set<AVMetadataIdentifier> = [
        .iTunesMetadataSongName, .iTunesMetadataArtist, .iTunesMetadataAlbum, .iTunesMetadataAlbumArtist,
        .iTunesMetadataComposer, .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre,
        .iTunesMetadataReleaseDate, .iTunesMetadataTrackNumber, .iTunesMetadataDiscNumber,
        .iTunesMetadataUserComment, .iTunesMetadataLyrics, .iTunesMetadataCoverArt,
    ]

    static func write(_ tags: TagSet, to url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let existing = (try? await asset.loadMetadata(for: .iTunesMetadata)) ?? []
        var items: [AVMetadataItem] = existing.filter { item in
            guard let id = item.identifier else { return true }
            return !managed.contains(id)
        }

        func text(_ id: AVMetadataIdentifier, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let item = AVMutableMetadataItem()
            item.identifier = id
            item.value = value as NSString
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            items.append(item)
        }
        func pair(_ id: AVMetadataIdentifier, _ number: Int?, _ total: Int?, length: Int) {
            guard let number else { return }
            let n = UInt16(clamping: number), t = UInt16(clamping: total ?? 0)
            var bytes: [UInt8] = [0, 0, UInt8(n >> 8), UInt8(n & 0xFF), UInt8(t >> 8), UInt8(t & 0xFF), 0, 0]
            bytes = Array(bytes.prefix(length))
            let item = AVMutableMetadataItem()
            item.identifier = id
            item.value = Data(bytes) as NSData
            item.dataType = kCMMetadataBaseDataType_RawData as String
            items.append(item)
        }

        text(.iTunesMetadataSongName, tags.title)
        text(.iTunesMetadataArtist, tags.artist)
        text(.iTunesMetadataAlbum, tags.album)
        text(.iTunesMetadataAlbumArtist, tags.albumArtist)
        text(.iTunesMetadataComposer, tags.composer)
        text(.iTunesMetadataUserGenre, tags.genre)
        text(.iTunesMetadataReleaseDate, tags.year.map(String.init))
        text(.iTunesMetadataUserComment, tags.comment)
        text(.iTunesMetadataLyrics, tags.lyrics)
        pair(.iTunesMetadataTrackNumber, tags.trackNumber, tags.trackCount, length: 8)
        pair(.iTunesMetadataDiscNumber, tags.discNumber, tags.discCount, length: 6)

        if let artwork = tags.artwork {
            let isPNG = artwork.starts(with: [0x89, 0x50, 0x4E, 0x47])
            let item = AVMutableMetadataItem()
            item.identifier = .iTunesMetadataCoverArt
            item.value = artwork as NSData
            item.dataType = (isPNG ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String
            items.append(item)
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MP4Error.exportUnavailable
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        session.outputURL = temp
        session.outputFileType = .m4a
        session.metadata = items

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    continuation.resume()
                } else {
                    let reason = session.error?.localizedDescription ?? "unknown error"
                    continuation.resume(throwing: MP4Error.exportFailed(reason))
                }
            }
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }
}

/// Picks the right writer for a file's format.
enum TagWriter {
    static func canWrite(_ song: Song) -> Bool {
        ["mp3", "flac", "m4a", "m4b"].contains(song.fileExtension)
    }

    static func write(_ song: Song) async throws {
        let tags = song.tagSet()
        let url = song.fileURL
        switch song.fileExtension {
        case "mp3":
            try await Task.detached(priority: .userInitiated) { try ID3.write(tags, to: url) }.value
        case "flac":
            try await Task.detached(priority: .userInitiated) { try FLACTags.write(tags, to: url) }.value
        case "m4a", "m4b":
            try await MP4Tagger.write(tags, to: url)
        default:
            break
        }
    }

    static func formatSupportNote(for song: Song) -> String {
        canWrite(song)
            ? "Edits are saved into the \(song.fileExtension.uppercased()) file, so they travel with it when you share or export."
            : "\(song.fileExtension.uppercased()) files don't support embedded tags here. Edits are kept in your library only."
    }
}
