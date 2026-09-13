import SwiftUI
import WidgetKit

// MARK: - Timeline

/// One entry, refreshed only when the app says the data changed.
///
/// `.never` is deliberate: WidgetKit would otherwise wake this extension on a
/// schedule to ask for new timelines. The app calls `reloadAllTimelines()` when
/// something actually changes, so the widget costs nothing in between.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Shared chrome

private extension Color {
    init(widgetHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct ThemeBackground: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        LinearGradient(
            colors: [Color(widgetHex: snapshot.startHex), Color(widgetHex: snapshot.endHex)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(widgetHex: snapshot.accentHex).opacity(0.28))
                .blur(radius: 40)
                .frame(width: 130, height: 130)
                .offset(x: 40, y: -40)
        }
    }
}

// MARK: - Quick Note

struct QuickNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetMacQuickNote", provider: SnapshotProvider()) { entry in
            QuickNoteWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { ThemeBackground(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Quick Note")
        .description("Your note, on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickNoteWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(widgetHex: snapshot.accentHex))
                    .frame(width: 6, height: 6)
                Text("QUICK NOTE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(snapshot.note.isEmpty ? "No note yet" : snapshot.note)
                .font(.system(size: family == .systemSmall ? 11 : 13, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(family == .systemSmall ? 6 : (family == .systemMedium ? 6 : 14))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Clipboard

struct ClipboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetMacClipboard", provider: SnapshotProvider()) { entry in
            ClipboardWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { ThemeBackground(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Clipboard")
        .description("What you copied most recently.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ClipboardWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var limit: Int { family == .systemLarge ? 5 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT CLIPBOARD")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))

            if snapshot.clips.isEmpty {
                Text("Nothing captured yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ForEach(snapshot.clips.prefix(limit)) { clip in
                    HStack(spacing: 7) {
                        Image(systemName: symbol(for: clip.kind))
                            .font(.system(size: 9))
                            .foregroundStyle(Color(widgetHex: snapshot.accentHex))
                            .frame(width: 14)
                        Text(clip.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if clip.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color(widgetHex: snapshot.accentHex))
                        }
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 26)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func symbol(for kind: String) -> String {
        switch kind {
        case "image": "photo"
        case "file": "doc"
        default: "doc.text"
        }
    }
}

// MARK: - Theme clock

struct ThemeClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetMacClock", provider: SnapshotProvider()) { entry in
            ThemeClockWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { ThemeBackground(snapshot: entry.snapshot) }
        }
        .configurationDisplayName("Theme Clock")
        .description("The time, in your desktop theme.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ThemeClockWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            // `Text(_:style:)` is rendered by WidgetKit itself, so the clock
            // stays live without ever reloading the timeline.
            Text(Date.now, style: .time)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
            Text(snapshot.themeName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(widgetHex: snapshot.accentHex))
                .lineLimit(1)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Photo

/// Entry for the photo widget: which picture to show, and when.
struct PhotoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let photo: String?
}

/// Rotation is expressed as a *timeline*, not a timer.
///
/// WidgetKit is handed one entry per photo with the time it should appear, and
/// renders each at the right moment on its own. The extension is not woken in
/// between, so a rotating photo widget costs the same as a static one.
struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: .now, snapshot: .placeholder, photo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder : SharedStore.load()
        completion(PhotoEntry(date: .now, snapshot: snapshot, photo: snapshot.photos.first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let snapshot = SharedStore.load()
        guard !snapshot.photos.isEmpty else {
            completion(Timeline(entries: [PhotoEntry(date: .now, snapshot: snapshot, photo: nil)], policy: .never))
            return
        }

        let step = TimeInterval(max(1, snapshot.photoRotationMinutes) * 60)
        // Cover roughly twelve hours, but never build more entries than needed.
        let count = min(max(snapshot.photos.count, 1), Int((12 * 3600) / step) + 1)
        let start = Date.now
        let entries = (0..<count).map { index in
            PhotoEntry(
                date: start.addingTimeInterval(step * Double(index)),
                snapshot: snapshot,
                photo: snapshot.photos[index % snapshot.photos.count]
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WidgetMacPhoto", provider: PhotoProvider()) { entry in
            PhotoWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    if let name = entry.photo, let image = PhotoStore.image(named: name) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ThemeBackground(snapshot: entry.snapshot)
                    }
                }
        }
        .configurationDisplayName("Photo")
        .description("Your pictures, rotating on the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PhotoWidgetView: View {
    let entry: PhotoEntry

    var body: some View {
        if entry.photo == nil {
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Add photos in WidgetMac")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A scrim only where the caption sits, so the picture stays clean.
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Text(entry.snapshot.themeName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

// MARK: - Bundle

@main
struct WidgetMacWidgets: WidgetBundle {
    var body: some Widget {
        QuickNoteWidget()
        ClipboardWidget()
        ThemeClockWidget()
        PhotoWidget()
    }
}
