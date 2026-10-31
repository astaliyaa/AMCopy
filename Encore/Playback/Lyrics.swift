import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double?
    let text: String
}

struct ParsedLyrics: Equatable {
    var lines: [LyricLine]
    var isSynced: Bool

    static let empty = ParsedLyrics(lines: [], isSynced: false)

    /// Index of the line being sung at `time`.
    func activeIndex(at time: Double) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.time ?? .infinity) <= time + 0.15 }
    }
}

/// Plain text lyrics, or LRC: "[01:23.45] line" (multiple timestamps per line allowed).
enum LyricsParser {
    static func parse(_ raw: String) -> ParsedLyrics {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        var timed: [(Double, String)] = []
        var plain: [String] = []
        var offset = 0.0

        for rawLine in raw.components(separatedBy: .newlines) {
            var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            var isMetadata = false

            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                if let time = parseTime(tag) {
                    times.append(time)
                    line = line[line.index(after: close)...]
                } else if let colon = tag.firstIndex(of: ":"), tag[..<colon].allSatisfy(\.isLetter) {
                    // [ar:Artist] [ti:Title] [offset:+200] …
                    if tag[..<colon].lowercased() == "offset", let ms = Double(tag[tag.index(after: colon)...]) {
                        offset = ms / 1000
                    }
                    isMetadata = true
                    break
                } else {
                    break
                }
            }
            if isMetadata { continue }

            let text = line.trimmingCharacters(in: .whitespaces)
            if times.isEmpty {
                plain.append(text)
            } else {
                for time in times { timed.append((time, text)) }
            }
        }

        if timed.count >= 2 {
            let sorted = timed.sorted { $0.0 < $1.0 }
            let lines = sorted.enumerated().map { i, entry in
                LyricLine(id: i, time: max(0, entry.0 - offset), text: entry.1)
            }
            return ParsedLyrics(lines: lines, isSynced: true)
        }

        // Collapse runs of blank lines.
        var lines: [LyricLine] = []
        for text in plain {
            if text.isEmpty, lines.last?.text.isEmpty ?? true { continue }
            lines.append(LyricLine(id: lines.count, time: nil, text: text))
        }
        while lines.last?.text.isEmpty == true { lines.removeLast() }
        return ParsedLyrics(lines: lines, isSynced: false)
    }

    /// "01:23.45", "1:23", "01:23:45" (mm:ss:cc).
    private static func parseTime(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let minutes = Double(parts[0]), parts[0].allSatisfy(\.isNumber) else { return nil }
        let secondsText = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsText) else { return nil }
        return minutes * 60 + seconds
    }
}
