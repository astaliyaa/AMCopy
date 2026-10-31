import Foundation

/// Where everything lives on disk.
///
/// - Library files (audio, artwork, animated covers, the database) live in
///   Application Support and are owned by the app.
/// - `Documents` is a drop folder: anything you copy there (Files app,
///   Finder, or the Apple Devices app on Windows) is imported on launch.
enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Encore", isDirectory: true)
    }()

    static let music = root.appendingPathComponent("Music", isDirectory: true)
    static let artwork = root.appendingPathComponent("Artwork", isDirectory: true)
    static let animatedCovers = root.appendingPathComponent("AnimatedCovers", isDirectory: true)
    static let libraryFile = root.appendingPathComponent("library.json")

    static let inbox: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    static func createDirectories() {
        for dir in [root, music, artwork, animatedCovers] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Returns a URL inside `directory` that doesn't exist yet, appending " 2", " 3"… if needed.
    static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var url = directory.appendingPathComponent(fileName)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            url = directory.appendingPathComponent(name)
            n += 1
        }
        return url
    }
}
