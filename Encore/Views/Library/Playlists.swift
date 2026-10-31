import SwiftUI
import PhotosUI

/// Custom cover, or a 2×2 mosaic of the first album covers.
struct PlaylistArtwork: View {
    let playlist: Playlist
    var pixelSize: Int = 400
    var cornerRadius: CGFloat = 8
    @Environment(Library.self) private var library

    var body: some View {
        if let artworkID = playlist.artworkID {
            ArtworkView(artworkID: artworkID, pixelSize: pixelSize, cornerRadius: cornerRadius)
        } else {
            let covers = Array(NSOrderedSet(array: library.songs(playlist.songIDs).compactMap(\.artworkID)).array.compactMap { $0 as? String }.prefix(4))
            if covers.count >= 4 {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                ArtworkView(artworkID: covers[0], pixelSize: pixelSize / 2, cornerRadius: 0)
                                ArtworkView(artworkID: covers[1], pixelSize: pixelSize / 2, cornerRadius: 0)
                            }
                            GridRow {
                                ArtworkView(artworkID: covers[2], pixelSize: pixelSize / 2, cornerRadius: 0)
                                ArtworkView(artworkID: covers[3], pixelSize: pixelSize / 2, cornerRadius: 0)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if let first = covers.first {
                ArtworkView(artworkID: first, pixelSize: pixelSize, cornerRadius: cornerRadius)
            } else {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        LinearGradient(colors: [Color(white: 0.6), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

struct PlaylistsView: View {
    @Environment(Library.self) private var library
    @Environment(UIState.self) private var ui

    var body: some View {
        List {
            Button {
                ui.playlistEditor = PlaylistEditRequest(playlistID: nil)
            } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundStyle(Color.appAccent)
                        }
                    Text("New Playlist…")
                        .foregroundStyle(Color.appAccent)
                }
            }
            NavigationLink(value: Route.favorites) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color.appAccent, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "star.fill").font(.title2).foregroundStyle(.white)
                        }
                    Text("Favorite Songs")
                }
            }
            ForEach(library.playlists) { playlist in
                NavigationLink(value: Route.playlist(playlist.id)) {
                    HStack(spacing: 14) {
                        PlaylistArtwork(playlist: playlist, pixelSize: 160, cornerRadius: 8)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name).lineLimit(1)
                            Text("\(playlist.songIDs.count) songs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) { library.deletePlaylist(playlist.id) } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { library.deletePlaylist(library.playlists[i].id) }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlists")
    }
}

struct PlaylistDetailView: View {
    let playlistID: UUID
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var showSongPicker = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        if let playlist = library.playlist(playlistID) {
            content(playlist)
        } else {
            ContentUnavailableView("Playlist Not Available", systemImage: "music.note.list")
        }
    }

    private func content(_ playlist: Playlist) -> some View {
        let entries: [(offset: Int, song: Song)] = playlist.songIDs.enumerated().compactMap { pair in
            guard let song = library.song(pair.element) else { return nil }
            return (offset: pair.offset, song: song)
        }
        let songs = entries.map(\.song)
        return List {
            VStack(spacing: 10) {
                PlaylistArtwork(playlist: playlist, pixelSize: 800, cornerRadius: 10)
                    .frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                Text(playlist.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if !playlist.details.isEmpty {
                    Text(playlist.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                PlayShuffleButtons(songs: songs, title: playlist.name)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 14, trailing: 20))

            ForEach(entries, id: \.offset) { entry in
                Button {
                    player.play(songs, startingAt: entries.firstIndex { $0.offset == entry.offset }, from: playlist.name)
                } label: {
                    SongRow(song: entry.song)
                }
                .contextMenu {
                    SongActions(song: entry.song, playlistID: playlist.id, playlistIndex: entry.offset)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
            }
            .onDelete { offsets in
                let removed = Set(offsets.map { entries[$0].offset })
                library.modifyPlaylist(playlist.id) { p in
                    p.songIDs = p.songIDs.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
                }
            }
            .onMove { source, destination in
                library.modifyPlaylist(playlist.id) { p in
                    var ids = entries.map(\.song.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    p.songIDs = ids
                }
            }

            Button {
                showSongPicker = true
            } label: {
                Label("Add Songs", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.appAccent)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))

            if !songs.isEmpty {
                Text("\(songs.count) songs, \(songs.reduce(0) { $0 + $1.duration }.longDurationString)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 20, trailing: 20))
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { ui.playlistEditor = PlaylistEditRequest(playlistID: playlist.id) } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    Button { showSongPicker = true } label: {
                        Label("Add Songs", systemImage: "plus")
                    }
                    Button { player.playNext(songs) } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button { ui.edit(songs) } label: {
                        Label("Edit Info of All Songs", systemImage: "tag")
                    }
                    .disabled(songs.isEmpty)
                    Divider()
                    Button(role: .destructive) {
                        library.deletePlaylist(playlist.id)
                        dismiss()
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerSheet { ids in library.addSongs(ids, to: playlist.id) }
        }
    }
}

/// Create or edit a playlist's name, description and cover.
struct PlaylistEditorForm: View {
    let request: PlaylistEditRequest
    var onFinish: (() -> Void)?

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var artworkID: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false

    private var isNew: Bool { request.playlistID == nil }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack {
                            if let artworkID {
                                ArtworkView(artworkID: artworkID, pixelSize: 500, cornerRadius: 10)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.largeTitle)
                                            .foregroundStyle(Color.appAccent)
                                    }
                            }
                        }
                        .frame(width: 180, height: 180)
                    }
                    .buttonStyle(.plain)
                    if artworkID != nil {
                        Button("Remove Cover", role: .destructive) { artworkID = nil }
                            .font(.footnote)
                    }
                    TextField("Playlist Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section("Description") {
                TextField("Description", text: $details, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle(isNew ? "New Playlist" : "Edit Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { finish() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Done") { save() }
                    .fontWeight(.semibold)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    artworkID = await Task.detached { ArtworkStore.save(data) }.value
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let id = request.playlistID, let playlist = library.playlist(id) {
                name = playlist.name
                details = playlist.details
                artworkID = playlist.artworkID
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = request.playlistID {
            library.modifyPlaylist(id) { p in
                p.name = trimmed.isEmpty ? p.name : trimmed
                p.details = details
                p.artworkID = artworkID
            }
        } else {
            library.createPlaylist(name: trimmed, details: details, songIDs: request.initialSongIDs, artworkID: artworkID)
        }
        finish()
    }

    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }
}

struct AddToPlaylistSheet: View {
    let songIDs: [UUID]
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PlaylistEditorForm(
                        request: PlaylistEditRequest(playlistID: nil, initialSongIDs: songIDs),
                        onFinish: { dismiss() }
                    )
                } label: {
                    Label("New Playlist…", systemImage: "plus")
                        .foregroundStyle(Color.appAccent)
                }
                ForEach(library.playlists) { playlist in
                    Button {
                        library.addSongs(songIDs, to: playlist.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            PlaylistArtwork(playlist: playlist, pixelSize: 140, cornerRadius: 6)
                                .frame(width: 48, height: 48)
                            Text(playlist.name).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Multi-select song picker with search.
struct SongPickerSheet: View {
    let onAdd: ([UUID]) -> Void
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: [UUID] = []

    private var results: [Song] {
        let all = library.songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { song in
                let isChosen = chosen.contains(song.id)
                Button {
                    if let i = chosen.firstIndex(of: song.id) { chosen.remove(at: i) } else { chosen.append(song.id) }
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(artworkID: song.artworkID, pixelSize: 120, cornerRadius: 5)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).foregroundStyle(.primary).lineLimit(1)
                            Text(song.displayArtist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: isChosen ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title3)
                            .foregroundStyle(isChosen ? Color.appAccent : Color.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Your Library")
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Done" : "Add \(chosen.count)") {
                        onAdd(chosen)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
