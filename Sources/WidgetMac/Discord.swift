import AppKit
import Combine
import SwiftUI

/// A floating call overlay: always on top, on every Space, resizable, and
/// remembered where you left it.
///
/// What it *shows* is driven by the switches in the hub, not read from Discord.
/// Discord exposes call state only through its RPC interface, which needs an
/// application you register and your authorisation; there is no public way to
/// observe a call from outside. Running state is real; the rest is yours to set.
@MainActor
final class DiscordOverlayCoordinator {
    private let state: WidgetMacState
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var observers: [Any] = []

    init(state: WidgetMacState) {
        self.state = state
        panel = InteractiveNotchPanel(
            contentRect: state.discordOverlayFrame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 210, height: 132)
        panel.maxSize = NSSize(width: 900, height: 700)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = FirstClickHostingView(rootView: DiscordOverlayView(state: state))
        panel.setFrame(state.discordOverlayFrame, display: false)

        // Visibility follows the switches directly.
        state.$discordPipEnabled
            .combineLatest(state.$discordCameraOn, state.$discordSharingOn, state.$discordOverlayPinned)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, camera, sharing, pinned in
                guard let self else { return }
                if enabled && (camera || sharing || pinned) { self.show() } else { self.panel.orderOut(nil) }
            }
            .store(in: &cancellables)

        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state.discordOverlayFrame = self.panel.frame
                }
            })
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

struct DiscordOverlayView: View {
    @ObservedObject var state: WidgetMacState
    @State private var hovering = false

    private var tiles: [DiscordTile] {
        var out: [DiscordTile] = []
        if state.discordCameraOn { out.append(.camera) }
        if state.discordSharingOn { out.append(.screen) }
        if out.isEmpty { out.append(.idle) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                let stacked = proxy.size.width < 320 || tiles.count == 1
                let layout = stacked
                    ? AnyLayout(VStackLayout(spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 6))
                layout {
                    ForEach(tiles) { tile in
                        DiscordTileView(tile: tile, state: state)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            footer
        }
        .background(Color(hex: 0x0E0F14).opacity(state.discordOverlayOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(hovering ? 0.2 : 0.08))
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(state.discordRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(state.discordChannelName.isEmpty ? "Discord" : state.discordChannelName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button { state.discordOverlayPinned.toggle() } label: {
                    Image(systemName: state.discordOverlayPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(state.discordOverlayPinned ? "Unpin (hides when no call)" : "Keep visible")

                Button { state.hideDiscordOverlay() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide overlay")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill").font(.system(size: 10))
            Image(systemName: state.discordCameraOn ? "video.fill" : "video.slash.fill")
                .font(.system(size: 10))
                .foregroundStyle(state.discordCameraOn ? .white : .white.opacity(0.4))
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 10))
                .foregroundStyle(state.discordSharingOn ? .white : .white.opacity(0.4))
            Spacer(minLength: 4)
            Button { state.openDiscord() } label: {
                Text("Open")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(.white.opacity(0.12), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.white.opacity(0.05))
    }
}

enum DiscordTile: String, Identifiable {
    case camera, screen, idle
    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .screen: "Screen"
        case .idle: "No call"
        }
    }
    var symbol: String {
        switch self {
        case .camera: "video.fill"
        case .screen: "rectangle.on.rectangle.fill"
        case .idle: "moon.zzz.fill"
        }
    }
}

struct DiscordTileView: View {
    let tile: DiscordTile
    @ObservedObject var state: WidgetMacState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: tile == .idle
                    ? [Color(hex: 0x1B1D24), Color(hex: 0x14161B)]
                    : [Color(hex: 0x2B2A5E), Color(hex: 0x14161B)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 5) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(tile == .idle ? 0.35 : 0.9))
                Text(tile.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(tile == .idle ? 0.35 : 0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
