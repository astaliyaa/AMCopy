import SwiftUI
import Observation
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case home, new, radio, library, search
}

enum Route: Hashable {
    case playlists, artists, albums, songs, genres, favorites
    case album(String)
    case artist(String)
    case genre(String)
    case playlist(UUID)
}

enum EditorTab: String, CaseIterable, Identifiable {
    case details = "Details"
    case artwork = "Artwork"
    case lyrics = "Lyrics"
    case file = "File"
    var id: String { rawValue }
}

struct EditRequest: Identifiable {
    let id = UUID()
    let songIDs: [UUID]
    var tab: EditorTab = .details
}

struct SongSelection: Identifiable {
    let id = UUID()
    let songIDs: [UUID]
}

struct PlaylistEditRequest: Identifiable {
    let id = UUID()
    /// nil = create a new playlist.
    let playlistID: UUID?
    var initialSongIDs: [UUID] = []
}

enum ImportMode {
    case files, folder
    var types: [UTType] { self == .folder ? [.folder] : [.audio] }
}

/// App-wide presentation state (sheets, tabs, navigation).
@MainActor
@Observable
final class UIState {
    var tab: AppTab = .home
    var showPlayer = false
    var showSettings = false
    var showImporter = false
    var importMode: ImportMode = .files

    var editRequest: EditRequest?
    var playlistPicker: SongSelection?
    var playlistEditor: PlaylistEditRequest?
    var deleteRequest: SongSelection?

    var libraryPath = NavigationPath()

    func importFiles() {
        importMode = .files
        showImporter = true
    }

    func importFolder() {
        importMode = .folder
        showImporter = true
    }

    func edit(_ songs: [Song], tab: EditorTab = .details) {
        guard !songs.isEmpty else { return }
        editRequest = EditRequest(songIDs: songs.map(\.id), tab: tab)
    }

    func addToPlaylist(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        playlistPicker = SongSelection(songIDs: songs.map(\.id))
    }

    func confirmDelete(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        deleteRequest = SongSelection(songIDs: songs.map(\.id))
    }

    /// Jumps to a library page from anywhere (including Now Playing).
    func navigate(to route: Route) {
        showPlayer = false
        tab = .library
        libraryPath = NavigationPath()
        libraryPath.append(route)
    }
}

/// Sheets that can be opened from any screen. Attached both to the root and to
/// Now Playing; only the topmost one is active so a sheet can always present.
struct GlobalSheets: ViewModifier {
    let isActive: Bool
    @Environment(UIState.self) private var ui
    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content
            .sheet(item: gated(\.editRequest)) { request in
                TagEditorView(request: request)
            }
            .sheet(item: gated(\.playlistPicker)) { selection in
                AddToPlaylistSheet(songIDs: selection.songIDs)
            }
            .sheet(item: gated(\.playlistEditor)) { request in
                NavigationStack {
                    PlaylistEditorForm(request: request)
                }
            }
            .alert(
                deleteTitle,
                isPresented: Binding(
                    get: { isActive && ui.deleteRequest != nil },
                    set: { if !$0 { ui.deleteRequest = nil } }
                ),
                presenting: ui.deleteRequest
            ) { selection in
                Button("Delete", role: .destructive) {
                    library.delete(Set(selection.songIDs))
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The audio files will be removed from this iPhone.")
            }
    }

    private var deleteTitle: String {
        let count = ui.deleteRequest?.songIDs.count ?? 0
        return count == 1 ? "Delete Song from Library?" : "Delete \(count) Songs from Library?"
    }

    private func gated<T>(_ keyPath: ReferenceWritableKeyPath<UIState, T?>) -> Binding<T?> {
        Binding(
            get: { isActive ? ui[keyPath: keyPath] : nil },
            set: { ui[keyPath: keyPath] = $0 }
        )
    }
}
