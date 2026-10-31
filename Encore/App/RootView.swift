import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var playerNamespace

    var body: some View {
        @Bindable var ui = ui
        TabView(selection: $ui.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView().legacyMiniPlayer(namespace: playerNamespace)
            }
            Tab("New", systemImage: "square.grid.2x2.fill", value: AppTab.new) {
                NewView().legacyMiniPlayer(namespace: playerNamespace)
            }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: AppTab.radio) {
                RadioView().legacyMiniPlayer(namespace: playerNamespace)
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                LibraryView().legacyMiniPlayer(namespace: playerNamespace)
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView().legacyMiniPlayer(namespace: playerNamespace)
            }
        }
        .modifier(TabAccessoryMiniPlayer(namespace: playerNamespace))
        .fullScreenCover(isPresented: $ui.showPlayer) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "miniPlayer", in: playerNamespace))
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsView()
        }
        .fileImporter(
            isPresented: $ui.showImporter,
            allowedContentTypes: ui.importMode.types,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await Importer.importItems(at: urls, library: library) }
            }
        }
        .modifier(GlobalSheets(isActive: !ui.showPlayer && !ui.showSettings))
        .overlay(alignment: .top) {
            if let status = library.importStatus {
                ImportBanner(status: status)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: library.importStatus)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Task { await Importer.scanInbox(library: library) }
            case .background:
                player.saveState()
                library.saveNow()
            default:
                break
            }
        }
    }
}

private struct ImportBanner: View {
    let status: ImportStatus

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(status.done), total: Double(max(status.total, 1)))
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Importing \(min(status.done + 1, status.total)) of \(status.total)…")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.top, 4)
    }
}

// MARK: - Mini player placement

enum MiniPlayerSupport {
    /// iOS 26 puts the mini player in the tab bar's bottom accessory (Liquid Glass).
    static var usesTabAccessory: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

private struct TabAccessoryMiniPlayer: ViewModifier {
    let namespace: Namespace.ID
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui
    @Environment(Library.self) private var library

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .tabViewBottomAccessory {
                    MiniPlayerView(namespace: namespace, style: .accessory)
                        .environment(player)
                        .environment(ui)
                        .environment(library)
                }
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct LegacyMiniPlayerInset: ViewModifier {
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if MiniPlayerSupport.usesTabAccessory {
            content
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerView(namespace: namespace, style: .floating)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }
}

extension View {
    func legacyMiniPlayer(namespace: Namespace.ID) -> some View {
        modifier(LegacyMiniPlayerInset(namespace: namespace))
    }
}

// MARK: - Mini player

struct MiniPlayerView: View {
    enum Style { case accessory, floating }

    let namespace: Namespace.ID
    let style: Style
    @Environment(Player.self) private var player
    @Environment(UIState.self) private var ui

    var body: some View {
        let song = player.currentSong
        HStack(spacing: 12) {
            ArtworkView(artworkID: song?.artworkID, pixelSize: 120, cornerRadius: style == .accessory ? 6 : 5)
                .frame(width: style == .accessory ? 32 : 40, height: style == .accessory ? 32 : 40)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text(song?.title ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let song, style == .floating {
                    Text(song.displayArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(song == nil)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .frame(width: 36, height: 36)
            }
            .disabled(song == nil)
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.leading, style == .accessory ? 10 : 8)
        .padding(.trailing, style == .accessory ? 6 : 8)
        .padding(.vertical, style == .floating ? 8 : 0)
        .background {
            if style == .floating {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if song != nil { ui.showPlayer = true }
        }
        .matchedTransitionSource(id: "miniPlayer", in: namespace)
    }
}
