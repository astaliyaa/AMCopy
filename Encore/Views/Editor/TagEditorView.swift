import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Field values shown in the editor. With several songs selected, fields that differ start empty
/// and show "Mixed"; only fields you actually change are written.
struct TagDraft: Equatable {
    var values: [TagField: String] = [:]
    var mixed: Set<TagField> = []
    var isExplicit = false

    subscript(field: TagField) -> String {
        get { values[field] ?? "" }
        set { values[field] = newValue }
    }

    init() {}

    init(songs: [Song]) {
        for field in TagField.allCases {
            let distinct = Set(songs.map { $0.value(for: field) })
            if distinct.count == 1, let only = distinct.first {
                values[field] = only
            } else {
                values[field] = ""
                mixed.insert(field)
            }
        }
        isExplicit = !songs.isEmpty && songs.allSatisfy(\.isExplicit)
    }
}

enum ArtworkChange {
    case unchanged, remove
    case set(Data)
}

enum AnimatedCoverChange {
    case unchanged, remove
    case set(URL)
}

private enum FileImportKind {
    case artwork, animatedCover, lyrics

    var types: [UTType] {
        switch self {
        case .artwork: [.image]
        case .animatedCover: [.movie, .gif]
        case .lyrics: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText, .text]
        }
    }
}

/// Video picked from Photos, copied to a temporary file.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

struct TagEditorView: View {
    let request: EditRequest

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.writeTags) private var writeTags = true

    @State private var songs: [Song] = []
    @State private var draft = TagDraft()
    @State private var initial = TagDraft()
    @State private var tab: EditorTab = .details
    @State private var artworkChange = ArtworkChange.unchanged
    @State private var animatedChange = AnimatedCoverChange.unchanged
    @State private var overrides: [UUID: [TagField: String]] = [:]
    @State private var overrideSummary: String?
    @State private var pattern = FilenamePattern.defaultPattern
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loaded = false

    @State private var artworkPhoto: PhotosPickerItem?
    @State private var animatedPhoto: PhotosPickerItem?
    @State private var importKind = FileImportKind.artwork
    @State private var showFileImporter = false

    private var isBatch: Bool { songs.count > 1 }
    private var tabs: [EditorTab] { isBatch ? [.details, .artwork, .file] : EditorTab.allCases }

    private var hasChanges: Bool {
        if draft != initial || !overrides.isEmpty { return true }
        if case .unchanged = artworkChange, case .unchanged = animatedChange { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                if !songs.isEmpty {
                    Section {
                        header
                        Picker("Section", selection: $tab) {
                            ForEach(tabs) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)
                    }
                    .listRowBackground(Color.clear)

                    switch tab {
                    case .details: detailsSections
                    case .artwork: artworkSections
                    case .lyrics: lyricsSections
                    case .file: fileSections
                    }
                }
            }
            .navigationTitle(isBatch ? "\(songs.count) Songs" : "Edit Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!hasChanges)
                    }
                }
            }
            .interactiveDismissDisabled(hasChanges || isSaving)
            .alert("Couldn't Save Everything", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: {
                Text(errorMessage ?? "")
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: importKind.types) { result in
                if case .success(let url) = result { handleImportedFile(url) }
            }
            .onChange(of: artworkPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        artworkChange = .set(data)
                    }
                    artworkPhoto = nil
                }
            }
            .onChange(of: animatedPhoto) { _, item in
                guard let item else { return }
                Task {
                    await loadAnimatedCover(from: item)
                    animatedPhoto = nil
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        songs = library.songs(request.songIDs)
        draft = TagDraft(songs: songs)
        initial = draft
        tab = songs.count > 1 && request.tab == .lyrics ? .details : request.tab
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            currentArtworkPreview
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                if isBatch {
                    Text("\(songs.count) Songs").font(.headline)
                    Text(draft[.album].isEmpty ? "Multiple Albums" : draft[.album])
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                } else if let song = songs.first {
                    Text(draft[.title].isEmpty ? song.title : draft[.title]).font(.headline).lineLimit(2)
                    Text(draft[.artist].isEmpty ? song.displayArtist : draft[.artist])
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text(draft[.album].isEmpty ? song.displayAlbum : draft[.album])
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var currentArtworkPreview: some View {
        switch artworkChange {
        case .set(let data):
            if let image = UIImage(data: data) {
                Color.clear.aspectRatio(1, contentMode: .fit)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ArtworkView(artworkID: nil)
            }
        case .remove:
            ArtworkView(artworkID: nil)
        case .unchanged:
            let ids = Set(songs.map(\.artworkID))
            ArtworkView(artworkID: ids.count == 1 ? songs.first?.artworkID : nil, pixelSize: 300)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSections: some View {
        Section {
            if !isBatch { field(.title) }
            field(.artist)
            field(.album)
            field(.albumArtist)
            field(.composer)
            HStack {
                fieldLabel(.genre)
                TextField(TagField.genre.label, text: $draft[.genre], prompt: prompt(.genre))
                if !library.genres.isEmpty {
                    Menu {
                        ForEach(library.genres) { genre in
                            Button(genre.name) { draft[.genre] = genre.name }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down").font(.footnote)
                    }
                }
            }
            field(.year, keyboard: .numberPad)
        }
        Section {
            HStack {
                Text("Track").foregroundStyle(.secondary).frame(width: 104, alignment: .leading)
                if !isBatch {
                    TextField("#", text: $draft[.track], prompt: prompt(.track))
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 60)
                    Text("of").foregroundStyle(.secondary)
                }
                TextField("Total", text: $draft[.trackCount], prompt: prompt(.trackCount))
                    .keyboardType(.numberPad)
            }
            HStack {
                Text("Disc").foregroundStyle(.secondary).frame(width: 104, alignment: .leading)
                TextField("#", text: $draft[.disc], prompt: prompt(.disc))
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 60)
                Text("of").foregroundStyle(.secondary)
                TextField("Total", text: $draft[.discCount], prompt: prompt(.discCount))
                    .keyboardType(.numberPad)
            }
            Toggle("Explicit", isOn: $draft.isExplicit)
        }
        Section("Comments") {
            TextField("Comments", text: $draft[.comment], prompt: prompt(.comment), axis: .vertical)
                .lineLimit(2...6)
        }
        Section {
            Toggle("Write Tags to Files", isOn: $writeTags)
        } footer: {
            if let song = songs.first {
                Text(isBatch ? "MP3, FLAC and M4A files get updated tags. Other formats keep edits in your library only." : TagWriter.formatSupportNote(for: song))
            }
        }
    }

    private func fieldLabel(_ f: TagField) -> some View {
        Text(f.label).foregroundStyle(.secondary).frame(width: 104, alignment: .leading)
    }

    private func prompt(_ f: TagField) -> Text {
        Text(draft.mixed.contains(f) && draft[f].isEmpty ? "Mixed" : f.label)
    }

    private func field(_ f: TagField, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            fieldLabel(f)
            TextField(f.label, text: $draft[f], prompt: prompt(f))
                .keyboardType(keyboard)
                .textInputAutocapitalization(f.isNumeric ? .never : .words)
        }
    }

    // MARK: - Artwork & animated cover

    @ViewBuilder
    private var artworkSections: some View {
        Section {
            HStack {
                Spacer()
                currentArtworkPreview.frame(width: 200, height: 200)
                Spacer()
            }
            .listRowBackground(Color.clear)
            PhotosPicker(selection: $artworkPhoto, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                importKind = .artwork
                showFileImporter = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
            Button {
                if let image = UIPasteboard.general.image, let data = image.pngData() {
                    artworkChange = .set(data)
                }
            } label: {
                Label("Paste Image", systemImage: "doc.on.clipboard")
            }
            .disabled(!UIPasteboard.general.hasImages)
            Button(role: .destructive) {
                artworkChange = .remove
            } label: {
                Label("Remove Artwork", systemImage: "trash")
            }
        } header: {
            Text("Artwork")
        } footer: {
            Text(isBatch ? "Applies to all \(songs.count) songs." : "Square images look best. Saved into the file's tags.")
        }

        Section {
            animatedPreview
            PhotosPicker(selection: $animatedPhoto, matching: .any(of: [.videos, .images])) {
                Label("Choose Video or GIF from Photos", systemImage: "video.badge.plus")
            }
            Button {
                importKind = .animatedCover
                showFileImporter = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }
            Button(role: .destructive) {
                animatedChange = .remove
            } label: {
                Label("Remove Animated Cover", systemImage: "trash")
            }
        } header: {
            Text("Animated Cover")
        } footer: {
            Text("Loops silently on the album page and in Now Playing. A short (3–15 s) square video works best. If a song has no artwork, the first frame is used as its cover.")
        }
    }

    @ViewBuilder
    private var animatedPreview: some View {
        let url: URL? = {
            switch animatedChange {
            case .set(let url): return url
            case .remove: return nil
            case .unchanged: return songs.first?.animatedCoverURL
            }
        }()
        if let url {
            HStack {
                Spacer()
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { AnimatedArtworkView(url: url) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(width: 200, height: 200)
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else {
            Text("No animated cover")
                .foregroundStyle(.secondary)
        }
    }

    private func loadAnimatedCover(from item: PhotosPickerItem) async {
        let types = item.supportedContentTypes
        if types.contains(where: { $0.conforms(to: .movie) }),
           let movie = try? await item.loadTransferable(type: PickedMovie.self) {
            animatedChange = .set(movie.url)
        } else if types.contains(where: { $0.conforms(to: .gif) }),
                  let data = try? await item.loadTransferable(type: Data.self) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
            if (try? data.write(to: url)) != nil { animatedChange = .set(url) }
        } else {
            errorMessageForPicker()
        }
    }

    private func errorMessageForPicker() {
        // Shown inline instead of the save alert so the editor stays open.
        overrideSummary = "Animated covers must be a video or a GIF."
    }

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsSections: some View {
        let parsed = LyricsParser.parse(draft[.lyrics])
        Section {
            TextEditor(text: $draft[.lyrics])
                .frame(minHeight: 300)
                .font(.callout)
        } header: {
            Text("Lyrics")
        } footer: {
            if parsed.isSynced {
                Label("Time-synced lyrics detected (\(parsed.lines.count) lines). They'll scroll along with the song.", systemImage: "checkmark.circle")
            } else {
                Text("For lyrics that scroll in time with the song, use LRC format: one line per lyric, each starting with a timestamp like [01:23.45].")
            }
        }
        Section {
            Button {
                importKind = .lyrics
                showFileImporter = true
            } label: {
                Label("Import .lrc or .txt File", systemImage: "doc.text")
            }
            Button {
                if let text = UIPasteboard.general.string { draft[.lyrics] = text }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Button(role: .destructive) {
                draft[.lyrics] = ""
            } label: {
                Label("Clear Lyrics", systemImage: "trash")
            }
        }
    }

    // MARK: - File

    @ViewBuilder
    private var fileSections: some View {
        if !isBatch, let song = songs.first {
            Section("File") {
                LabeledContent("Name", value: song.originalFileName)
                LabeledContent("Format", value: song.fileExtension.uppercased() + (song.isLossless ? " (Lossless)" : ""))
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: song.fileSize, countStyle: .file))
                LabeledContent("Duration", value: song.duration.timeString)
                LabeledContent("Date Added", value: song.dateAdded.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Plays", value: "\(song.playCount)")
                if let last = song.lastPlayed {
                    LabeledContent("Last Played", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                ShareLink(item: song.fileURL) {
                    Label("Share / Export File…", systemImage: "square.and.arrow.up")
                }
            }
        }

        Section {
            TextField("Pattern", text: $pattern)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            Button {
                applyFilenamePattern()
            } label: {
                Label("Tag from File Name", systemImage: "text.badge.checkmark")
            }
            if let overrideSummary {
                Text(overrideSummary).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("File Name → Tag")
        } footer: {
            Text("Placeholders: %artist% %title% %album% %albumartist% %track% %disc% %year% %genre% %composer% %dummy%. Example: \"%track% - %artist% - %title%\" matches \"03 - Artist - Song.mp3\".")
        }

        if isBatch {
            Section {
                Button {
                    autoNumber()
                } label: {
                    Label("Auto-Number Tracks", systemImage: "list.number")
                }
            } footer: {
                Text("Numbers the \(songs.count) songs 1–\(songs.count) in their current order and sets the track count.")
            }
        }
    }

    private func applyFilenamePattern() {
        var matched = 0
        if isBatch {
            for song in songs {
                let name = (song.originalFileName as NSString).deletingPathExtension
                if let fields = FilenamePattern.parse(name, pattern: pattern) {
                    overrides[song.id, default: [:]].merge(fields) { _, new in new }
                    matched += 1
                }
            }
            overrideSummary = "Matched \(matched) of \(songs.count) file names. Changes apply when you tap Save."
        } else if let song = songs.first {
            let name = (song.originalFileName as NSString).deletingPathExtension
            if let fields = FilenamePattern.parse(name, pattern: pattern) {
                for (field, value) in fields { draft[field] = value }
                overrideSummary = "Filled \(fields.count) fields from \"\(name)\"."
            } else {
                overrideSummary = "\"\(name)\" doesn't match this pattern."
            }
        }
    }

    private func autoNumber() {
        for (i, song) in songs.enumerated() {
            overrides[song.id, default: [:]][.track] = String(i + 1)
            overrides[song.id, default: [:]][.trackCount] = String(songs.count)
        }
        overrideSummary = "Tracks will be numbered 1–\(songs.count) when you tap Save."
    }

    // MARK: - Files picked from the Files app

    private func handleImportedFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        switch importKind {
        case .artwork:
            if let data = try? Data(contentsOf: url) { artworkChange = .set(data) }
        case .animatedCover:
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            if (try? FileManager.default.copyItem(at: url, to: temp)) != nil { animatedChange = .set(temp) }
        case .lyrics:
            if let data = try? Data(contentsOf: url) {
                draft[.lyrics] = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            }
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = songs.compactMap { library.song($0.id) }

        var newArtworkID: String?? = nil
        switch artworkChange {
        case .unchanged: break
        case .remove: newArtworkID = .some(nil)
        case .set(let data):
            newArtworkID = .some(await Task.detached { ArtworkStore.save(data) }.value)
        }

        var newAnimated: String?? = nil
        var firstFrameArtwork: String?
        switch animatedChange {
        case .unchanged: break
        case .remove: newAnimated = .some(nil)
        case .set(let url):
            let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())
            do {
                try FileManager.default.copyItem(at: url, to: Paths.animatedCovers.appendingPathComponent(name))
                newAnimated = .some(name)
            } catch {
                errorMessage = "The animated cover couldn't be saved: \(error.localizedDescription)"
                return
            }
            if case .unchanged = artworkChange, updated.contains(where: { $0.artworkID == nil }),
               let frame = await ArtworkStore.firstFrame(of: url) {
                firstFrameArtwork = ArtworkStore.save(frame)
            }
        }

        for i in updated.indices {
            for field in TagField.allCases where draft[field] != initial[field] {
                updated[i].setValue(draft[field], for: field)
            }
            for (field, value) in overrides[updated[i].id] ?? [:] {
                updated[i].setValue(value, for: field)
            }
            if draft.isExplicit != initial.isExplicit { updated[i].isExplicit = draft.isExplicit }
            if let newArtworkID {
                updated[i].artworkID = newArtworkID
            } else if updated[i].artworkID == nil, let firstFrameArtwork {
                updated[i].artworkID = firstFrameArtwork
            }
            if let newAnimated { updated[i].animatedCoverFile = newAnimated }
        }

        library.update(updated)
        library.collectGarbage()

        if writeTags {
            var failures: [String] = []
            for song in updated where TagWriter.canWrite(song) {
                do {
                    try await TagWriter.write(song)
                } catch {
                    failures.append("\(song.title): \(error.localizedDescription)")
                }
            }
            if !failures.isEmpty {
                errorMessage = "Your library was updated, but some files couldn't be re-tagged:\n\n" + failures.prefix(5).joined(separator: "\n")
                return
            }
        }
        dismiss()
    }
}
