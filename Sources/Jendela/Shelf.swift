import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A file parked on the shelf.
///
/// Paths, not copies: the shelf is a holding place, not a second copy of your
/// documents. If the original moves or is deleted the entry says so rather than
/// silently handing out a dead path.
struct ShelfItem: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var isDirectory: Bool {
        var directory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        return directory.boolValue
    }

    var sizeText: String {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: path)[.size] as? Int64, size > 0
        else { return isDirectory ? "Folder" : "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func make(_ url: URL) -> ShelfItem {
        ShelfItem(id: UUID(), path: url.path, addedAt: .now)
    }
}

enum ShelfStore {
    private static var fileURL: URL { SupportDirectory.root.appendingPathComponent("shelf.json") }

    static func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return [] }
        // Drop anything that has since been moved or deleted.
        return items.filter(\.exists)
    }

    static func save(_ items: [ShelfItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct ShelfNotchSection: View {
    @ObservedObject var state: JendelaState
    @State private var targeted = false
    @State private var hoveredID: ShelfItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shelf").font(.headline)
                    Text(state.shelfItems.isEmpty
                         ? "Drop files to hold them here"
                         : "\(state.shelfItems.count) held · drag one out to move it")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if !state.shelfItems.isEmpty {
                    Button { state.clearShelf() } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Empty the shelf")
                }
            }

            if state.shelfItems.isEmpty {
                dropWell
            } else {
                // The card stops growing after a few files; the rest were
                // drawn past the bottom of the hub.
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(state.shelfItems) { item in
                            row(item)
                        }
                    }
                }
                dropWell.frame(height: 44)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            state.addToShelf(from: providers)
            return true
        }
    }

    private var dropWell: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
            )
            .foregroundStyle(targeted ? state.appliedTheme.accentColor : .white.opacity(0.18))
            .background(
                (targeted ? state.appliedTheme.accentColor.opacity(0.12) : Color.white.opacity(0.03)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text(targeted ? "Release to hold" : "Drop files here")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(targeted ? state.appliedTheme.accentColor : .white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .frame(height: state.shelfItems.isEmpty ? 92 : 44)
    }

    private func row(_ item: ShelfItem) -> some View {
        let hovered = hoveredID == item.id
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12)).lineLimit(1)
                Text(item.sizeText)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 4)
            if hovered {
                Button { state.removeFromShelf(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Take off the shelf")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            hovered ? .white.opacity(0.12) : .white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hoveredID = $0 ? item.id : nil }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Remove", role: .destructive) { state.removeFromShelf(item) }
        }
        .help("Double-click to open · drag out to move")
    }
}
