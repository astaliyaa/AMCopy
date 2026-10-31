import AVFoundation

struct ImportedInfo {
    var tags: TagSet
    var duration: Double
    var isLossless: Bool
}

/// Reads tags with our own MP3/FLAC parsers first, then fills gaps from AVFoundation.
enum MetadataReader {
    static func read(url: URL) async -> ImportedInfo {
        let ext = url.pathExtension.lowercased()
        var tags = TagSet()
        switch ext {
        case "mp3": tags = ID3.readTagSet(url: url) ?? TagSet()
        case "flac": tags = FLACTags.read(url: url) ?? TagSet()
        default: break
        }

        let asset = AVURLAsset(url: url)
        tags.fillMissing(from: await readAVFoundation(asset))

        var duration = 0.0
        if let time = try? await asset.load(.duration), time.seconds.isFinite {
            duration = time.seconds
        }

        var lossless = ["flac", "wav", "aif", "aiff", "aifc"].contains(ext)
        if !lossless, ["m4a", "caf", "mp4", "alac"].contains(ext),
           let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let formats = try? await track.load(.formatDescriptions),
           let format = formats.first {
            lossless = CMFormatDescriptionGetMediaSubType(format) == kAudioFormatAppleLossless
        }

        return ImportedInfo(tags: tags, duration: duration, isLossless: lossless)
    }

    static func readAVFoundation(_ asset: AVURLAsset) async -> TagSet {
        var tags = TagSet()
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return tags }
        var items: [AVMetadataItem] = []
        for format in formats {
            if let found = try? await asset.loadMetadata(for: format) { items += found }
        }

        for item in items {
            guard let id = item.identifier else { continue }
            switch id {
            case .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription, .quickTimeMetadataTitle:
                if tags.title == nil { tags.title = await string(item) }
            case .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataLeadPerformer, .quickTimeMetadataArtist:
                if tags.artist == nil { tags.artist = await string(item) }
            case .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle, .quickTimeMetadataAlbum:
                if tags.album == nil { tags.album = await string(item) }
            case .iTunesMetadataAlbumArtist, .id3MetadataBand:
                if tags.albumArtist == nil { tags.albumArtist = await string(item) }
            case .iTunesMetadataComposer, .id3MetadataComposer, .quickTimeMetadataComposer:
                if tags.composer == nil { tags.composer = await string(item) }
            case .iTunesMetadataUserGenre, .id3MetadataContentType, .quickTimeMetadataGenre:
                if tags.genre == nil { tags.genre = await string(item).map(ID3.normalizeGenre) }
            case .iTunesMetadataPredefinedGenre:
                if tags.genre == nil, let n = try? await item.load(.numberValue)?.intValue {
                    tags.genre = ID3.genreName(n - 1)
                }
            case .iTunesMetadataReleaseDate, .commonIdentifierCreationDate, .id3MetadataYear,
                 .id3MetadataRecordingTime, .quickTimeMetadataYear:
                if tags.year == nil { tags.year = TagSet.parseYear(await string(item)) }
            case .iTunesMetadataTrackNumber:
                if tags.trackNumber == nil, let pair = await mp4Pair(item) {
                    (tags.trackNumber, tags.trackCount) = pair
                }
            case .iTunesMetadataDiscNumber:
                if tags.discNumber == nil, let pair = await mp4Pair(item) {
                    (tags.discNumber, tags.discCount) = pair
                }
            case .id3MetadataTrackNumber:
                if tags.trackNumber == nil { (tags.trackNumber, tags.trackCount) = TagSet.parsePair(await string(item)) }
            case .id3MetadataPartOfASet:
                if tags.discNumber == nil { (tags.discNumber, tags.discCount) = TagSet.parsePair(await string(item)) }
            case .iTunesMetadataLyrics, .id3MetadataUnsynchronizedLyric:
                if tags.lyrics == nil { tags.lyrics = await string(item) }
            case .iTunesMetadataUserComment, .id3MetadataComments:
                if tags.comment == nil { tags.comment = await string(item) }
            case .commonIdentifierArtwork, .iTunesMetadataCoverArt, .id3MetadataAttachedPicture, .quickTimeMetadataArtwork:
                if tags.artwork == nil { tags.artwork = try? await item.load(.dataValue) }
            default:
                break
            }
        }
        return tags
    }

    private static func string(_ item: AVMetadataItem) async -> String? {
        if let s = try? await item.load(.stringValue) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = try? await item.load(.numberValue) { return n.stringValue }
        return nil
    }

    /// iTunes "trkn"/"disk" atoms: [0, 0, number(2 bytes), total(2 bytes), …]
    private static func mp4Pair(_ item: AVMetadataItem) async -> (Int?, Int?)? {
        if let data = try? await item.load(.dataValue), data.count >= 6 {
            let b = [UInt8](data)
            let n = Int(b[2]) << 8 | Int(b[3])
            let total = Int(b[4]) << 8 | Int(b[5])
            return (n > 0 ? n : nil, total > 0 ? total : nil)
        }
        if let n = try? await item.load(.numberValue)?.intValue { return (n, nil) }
        return nil
    }
}
