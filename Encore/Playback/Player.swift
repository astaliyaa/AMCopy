import AVFoundation
import MediaPlayer
import Observation
import SwiftUI

enum RepeatMode: Int, Codable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// Playback engine. Uses AVQueuePlayer with the next song preloaded for gapless playback.
@MainActor
@Observable
final class Player {
    static let shared = Player()

    private(set) var queue: [UUID] = []
    private(set) var currentIndex = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var queueTitle = ""

    @ObservationIgnored private var originalQueue: [UUID] = []
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var upcomingItem: AVPlayerItem?
    @ObservationIgnored private var upcomingIndex: Int?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var nowPlayingArtwork: (id: String, artwork: MPMediaItemArtwork)?

    var currentSongID: UUID? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }
    var currentSong: Song? { currentSongID.flatMap { Library.shared.song($0) } }
    var upNext: [Song] {
        guard currentIndex + 1 < queue.count else { return [] }
        return queue[(currentIndex + 1)...].compactMap { Library.shared.song($0) }
    }

    private init() {
        player.actionAtItemEnd = .advance
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        observePlayer()
        configureRemoteCommands()
        observeSession()
        restoreState()
    }

    // MARK: - Starting playback

    /// Plays `songs`. With `shuffle: nil` the current shuffle mode is kept.
    func play(_ songs: [Song], startingAt index: Int? = nil, shuffle: Bool? = nil, from title: String = "") {
        guard !songs.isEmpty else { return }
        let ids = songs.map(\.id)
        originalQueue = ids
        queueTitle = title
        if let shuffle { isShuffled = shuffle }

        if isShuffled {
            if let index, ids.indices.contains(index) {
                var rest = ids
                let first = rest.remove(at: index)
                queue = [first] + rest.shuffled()
            } else {
                queue = ids.shuffled()
            }
            currentIndex = 0
        } else {
            queue = ids
            currentIndex = min(max(index ?? 0, 0), ids.count - 1)
        }
        consecutiveFailures = 0
        loadCurrent(autoplay: true)
    }

    func playNext(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else { play(songs); return }
        let ids = songs.map(\.id)
        queue.insert(contentsOf: ids, at: currentIndex + 1)
        if let current = currentSongID, let i = originalQueue.firstIndex(of: current) {
            originalQueue.insert(contentsOf: ids, at: i + 1)
        } else {
            originalQueue += ids
        }
        enqueueUpcoming()
        saveState()
    }

    func playLast(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        guard !queue.isEmpty else { play(songs); return }
        let ids = songs.map(\.id)
        queue += ids
        originalQueue += ids
        enqueueUpcoming()
        saveState()
    }

    // MARK: - Transport

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard currentSong != nil else { return }
        if player.currentItem == nil {
            loadCurrent(autoplay: true, at: currentTime)
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func pause() {
        player.pause()
        saveState()
    }

    func next() {
        guard !queue.isEmpty else { return }
        let wasPlaying = isPlaying
        if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else if repeatMode != .off {
            currentIndex = 0
        } else {
            currentIndex = 0
            loadCurrent(autoplay: false)
            return
        }
        loadCurrent(autoplay: wasPlaying || player.currentItem == nil)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || (currentIndex == 0 && repeatMode == .off) {
            seek(to: 0)
            return
        }
        let wasPlaying = isPlaying
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        loadCurrent(autoplay: wasPlaying)
    }

    func seek(to time: Double) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        currentTime = clamped
        guard player.currentItem != nil else { return }
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshNowPlayingInfo() }
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let current = currentSongID else { return }
        if isShuffled {
            var rest = originalQueue
            if let i = rest.firstIndex(of: current) { rest.remove(at: i) }
            queue = [current] + rest.shuffled()
            currentIndex = 0
        } else {
            queue = originalQueue.isEmpty ? queue : originalQueue
            currentIndex = queue.firstIndex(of: current) ?? 0
        }
        enqueueUpcoming()
        saveState()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        enqueueUpcoming()
        saveState()
    }

    // MARK: - Up Next editing

    func jump(toUpNext offset: Int) {
        let index = currentIndex + 1 + offset
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        loadCurrent(autoplay: true)
    }

    func removeFromUpNext(at offsets: IndexSet) {
        let absolute = IndexSet(offsets.map { $0 + currentIndex + 1 }.filter { queue.indices.contains($0) })
        for id in absolute.map({ queue[$0] }) {
            if let i = originalQueue.firstIndex(of: id) { originalQueue.remove(at: i) }
        }
        queue.remove(atOffsets: absolute)
        enqueueUpcoming()
        saveState()
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        guard currentIndex + 1 < queue.count else { return }
        var upcoming = Array(queue[(currentIndex + 1)...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue[...currentIndex]) + upcoming
        enqueueUpcoming()
        saveState()
    }

    func clearUpNext() {
        guard currentIndex + 1 < queue.count else { return }
        queue.removeSubrange((currentIndex + 1)...)
        enqueueUpcoming()
        saveState()
    }

    /// Called when songs are deleted from the library.
    func removeSongs(_ ids: Set<UUID>) {
        guard !queue.isEmpty else { return }
        let current = currentSongID
        let wasPlaying = isPlaying
        queue.removeAll { ids.contains($0) }
        originalQueue.removeAll { ids.contains($0) }
        if queue.isEmpty {
            stop()
        } else if let current, ids.contains(current) {
            currentIndex = min(currentIndex, queue.count - 1)
            loadCurrent(autoplay: wasPlaying)
        } else if let current {
            currentIndex = queue.firstIndex(of: current) ?? 0
            enqueueUpcoming()
        }
        saveState()
    }

    func stop() {
        player.removeAllItems()
        upcomingItem = nil
        upcomingIndex = nil
        queue = []
        originalQueue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        saveState()
    }

    // MARK: - Item management

    private func loadCurrent(autoplay: Bool, at time: Double = 0) {
        guard let song = currentSong else { stop(); return }
        let item = AVPlayerItem(url: song.fileURL)
        observeStatus(of: item)
        upcomingItem = nil
        upcomingIndex = nil
        player.removeAllItems()
        player.insert(item, after: nil)
        duration = song.duration
        currentTime = time
        if time > 0 {
            player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
        enqueueUpcoming()
        if autoplay {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            Library.shared.markPlayed(song.id)
        } else {
            player.pause()
        }
        refreshNowPlayingInfo()
        saveState()
    }

    private func nextIndex(after index: Int) -> Int? {
        switch repeatMode {
        case .one: return index
        case .all: return queue.isEmpty ? nil : (index + 1) % queue.count
        case .off: return index + 1 < queue.count ? index + 1 : nil
        }
    }

    /// Keeps exactly one preloaded item queued after the current one.
    private func enqueueUpcoming() {
        for item in player.items() where item !== player.currentItem {
            player.remove(item)
        }
        upcomingItem = nil
        upcomingIndex = nil
        guard let current = player.currentItem,
              let next = nextIndex(after: currentIndex),
              let song = Library.shared.song(queue[next]) else { return }
        let item = AVPlayerItem(url: song.fileURL)
        player.insert(item, after: current)
        upcomingItem = item
        upcomingIndex = next
    }

    private func handleCurrentItemChange() {
        guard let item = player.currentItem else {
            // Reached the end of the queue (repeat off).
            if !queue.isEmpty, upcomingItem == nil {
                if let finished = currentSongID { Library.shared.incrementPlayCount(finished) }
                currentIndex = 0
                loadCurrent(autoplay: false)
            }
            return
        }
        guard item === upcomingItem, let index = upcomingIndex else { return }
        if let finished = currentSongID { Library.shared.incrementPlayCount(finished) }
        currentIndex = index
        observeStatus(of: item)
        upcomingItem = nil
        upcomingIndex = nil
        duration = currentSong?.duration ?? 0
        currentTime = 0
        if let song = currentSong { Library.shared.markPlayed(song.id) }
        enqueueUpcoming()
        refreshNowPlayingInfo()
        saveState()
    }

    /// Skips songs whose files are missing or unreadable.
    private func observeStatus(of item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let failed = item.status == .failed
            let ready = item.status == .readyToPlay
            let seconds = item.duration.seconds
            Task { @MainActor in
                guard let self else { return }
                if ready {
                    self.consecutiveFailures = 0
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                } else if failed {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures < max(self.queue.count, 1) {
                        self.next()
                    } else {
                        self.player.pause()
                    }
                }
            }
        }
    }

    private func observePlayer() {
        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.handleCurrentItemChange() }
        })
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard let self, self.isPlaying != playing else { return }
                self.isPlaying = playing
                self.refreshNowPlayingInfo()
            }
        })
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard let self, seconds.isFinite, self.player.currentItem != nil else { return }
                self.currentTime = seconds
            }
        }
    }

    // MARK: - Audio session

    private func observeSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                guard let self, let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                if type == .ended, let rawOptions,
                   AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                    self.resume()
                }
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                if let rawReason, AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable {
                    self?.pause()
                }
            }
        }
    }

    // MARK: - Lock screen / Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    func refreshNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let elapsed = player.currentItem != nil ? player.currentTime().seconds : currentTime
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        if let artworkID = song.artworkID {
            if nowPlayingArtwork?.id != artworkID,
               let image = ArtworkStore.thumbnail(id: artworkID, maxPixel: 800) {
                nowPlayingArtwork = (artworkID, Self.makeArtwork(image))
            }
            if let cached = nowPlayingArtwork, cached.id == artworkID {
                info[MPMediaItemPropertyArtwork] = cached.artwork
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Built outside the main actor: the system calls this closure on a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Persistence

    private struct SavedState: Codable {
        var queue: [UUID]
        var originalQueue: [UUID]
        var index: Int
        var time: Double
        var shuffled: Bool
        var repeatMode: RepeatMode
        var title: String
    }

    func saveState() {
        let state = SavedState(
            queue: queue, originalQueue: originalQueue, index: currentIndex,
            time: currentTime, shuffled: isShuffled, repeatMode: repeatMode, title: queueTitle
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "playerState")
        }
    }

    private func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: "playerState"),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        let library = Library.shared
        let currentID = state.queue.indices.contains(state.index) ? state.queue[state.index] : nil
        queue = state.queue.filter { library.song($0) != nil }
        originalQueue = state.originalQueue.filter { library.song($0) != nil }
        isShuffled = state.shuffled
        repeatMode = state.repeatMode
        queueTitle = state.title
        if let currentID, let i = queue.firstIndex(of: currentID) {
            currentIndex = i
            currentTime = state.time
        } else {
            currentIndex = 0
            currentTime = 0
        }
        duration = currentSong?.duration ?? 0
        refreshNowPlayingInfo()
    }
}
