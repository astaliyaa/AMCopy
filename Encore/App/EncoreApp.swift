import SwiftUI

@main
struct EncoreApp: App {
    @State private var library = Library.shared
    @State private var player = Player.shared
    @State private var ui = UIState()

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.writeTags: true,
            SettingsKey.animatedCovers: true,
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(ui)
                .tint(.appAccent)
                .onOpenURL { url in
                    Task { await Importer.importOpenedFile(url, library: library) }
                }
        }
    }
}

enum SettingsKey {
    static let writeTags = "writeTagsToFiles"
    static let animatedCovers = "animatedCovers"
}

extension Color {
    static let appAccent = Color(red: 0.98, green: 0.176, blue: 0.282)
}
