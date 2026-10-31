import SwiftUI

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.writeTags) private var writeTags = true
    @AppStorage(SettingsKey.animatedCovers) private var animatedCovers = true
    @State private var importMode = ImportMode.files
    @State private var showImporter = false
    @State private var confirmDeleteAll = false
    @State private var retagProgress: ImportStatus?
    @State private var retagFailures = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Songs", value: "\(library.songs.count)")
                    LabeledContent("Albums", value: "\(library.albums.count)")
                    LabeledContent("Artists", value: "\(library.artists.count)")
                    LabeledContent("Storage", value: ByteCountFormatter.string(fromByteCount: library.storageUsed, countStyle: .file))
                } header: {
                    Text("Library")
                }

                Section {
                    Button {
                        importMode = .files
                        showImporter = true
                    } label: {
                        Label("Import Songs…", systemImage: "music.note")
                    }
                    Button {
                        importMode = .folder
                        showImporter = true
                    } label: {
                        Label("Import a Folder…", systemImage: "folder")
                    }
                    Button {
                        Task { await Importer.scanInbox(library: library) }
                    } label: {
                        Label("Check Encore Folder for New Files", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Add Music")
                } footer: {
                    Text("Anything you put in On My iPhone › Encore (Files app), or copy into Encore with Finder on a Mac or the Apple Devices app on Windows, is imported automatically when you open the app. Matching .lrc files and cover.jpg / folder.jpg images are picked up too.")
                }

                Section {
                    Toggle("Write Tags to Files", isOn: $writeTags)
                    Button {
                        Task { await retagAll() }
                    } label: {
                        if let retagProgress {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Writing \(retagProgress.done) of \(retagProgress.total)…")
                            }
                        } else {
                            Label("Rewrite Tags in All Files", systemImage: "tag")
                        }
                    }
                    .disabled(retagProgress != nil)
                    if retagFailures > 0 {
                        Text("\(retagFailures) files couldn't be updated.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("When on, edits to title, artist, album, artwork, lyrics and more are saved into MP3 (ID3v2), FLAC (Vorbis comments) and M4A (iTunes) files, so they show up in other apps when you share them.")
                }

                Section {
                    Toggle("Animated Covers", isOn: $animatedCovers)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Shows looping video artwork on album pages and in Now Playing. Turn off to save battery.")
                }

                Section {
                    Button("Delete Entire Library", role: .destructive) {
                        confirmDeleteAll = true
                    }
                    .disabled(library.songs.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: importMode.types, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await Importer.importItems(at: urls, library: library) }
                }
            }
            .confirmationDialog(
                "Delete all \(library.songs.count) songs and playlists?",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { library.deleteEverything() }
            } message: {
                Text("This removes the audio files, artwork and animated covers from this iPhone. It can't be undone.")
            }
        }
    }

    private func retagAll() async {
        let songs = library.songs.filter(TagWriter.canWrite)
        retagFailures = 0
        retagProgress = ImportStatus(done: 0, total: songs.count)
        for (i, song) in songs.enumerated() {
            do { try await TagWriter.write(song) } catch { retagFailures += 1 }
            retagProgress = ImportStatus(done: i + 1, total: songs.count)
        }
        retagProgress = nil
    }
}
