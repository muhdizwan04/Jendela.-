import EventKit
import Foundation

/// The next thing in your calendar, and a way into it.
///
/// Refreshed when the calendar itself changes and when the hub opens — never on
/// a timer. EventKit posts a notification on every edit, so polling would only
/// add wakeups without adding information.
@MainActor
final class Meetings: ObservableObject {
    struct Meeting: Identifiable, Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var calendarColour: Int
        var joinURL: URL?
        var isAllDay: Bool

        var isNow: Bool { Date() >= start && Date() < end }

        var whenText: String {
            if isAllDay { return "All day" }
            if isNow {
                // Rounded, not truncated: a meeting ten minutes away should not
                // read "in 9m" because a fraction of a second has elapsed.
                let remaining = Int((end.timeIntervalSinceNow / 60).rounded())
                return remaining > 0 ? "Now · \(remaining)m left" : "Now"
            }
            let minutes = Int((start.timeIntervalSinceNow / 60).rounded())
            if minutes < 1 { return "Starting" }
            if minutes < 60 { return "in \(minutes)m" }
            return start.formatted(date: .omitted, time: .shortened)
        }
    }

    @Published private(set) var upcoming: [Meeting] = []
    @Published private(set) var access: EKAuthorizationStatus = .notDetermined

    private let store = EKEventStore()
    nonisolated(unsafe) private var observer: Any?

    init() {
        access = EKEventStore.authorizationStatus(for: .event)
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if access == .fullAccess { refresh() }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var needsPermission: Bool { access != .fullAccess }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = EKEventStore.authorizationStatus(for: .event)
                    if granted { self.refresh() }
                }
            }
        }
    }

    func refresh() {
        guard access == .fullAccess else { return }
        let now = Date()
        let horizon = now.addingTimeInterval(36 * 3600)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                 end: horizon,
                                                 calendars: nil)
        upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map { event in
                Meeting(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    calendarColour: Meetings.colourValue(event),
                    joinURL: Meetings.joinURL(in: event),
                    isAllDay: event.isAllDay
                )
            }
    }

    var next: Meeting? { upcoming.first }

    private static func colourValue(_ event: EKEvent) -> Int {
        guard let colour = event.calendar?.cgColor,
              let components = colour.components, components.count >= 3 else { return 0x6C6CE5 }
        let r = Int(components[0] * 255), g = Int(components[1] * 255), b = Int(components[2] * 255)
        return (r << 16) | (g << 8) | b
    }

    /// Finds a link worth pressing. Conferencing details land in different
    /// fields depending on who made the invitation, so all of them are searched.
    static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                               "webex.com", "whereby.com", "meet.jit.si", "discord.com", "around.co"]

    /// Whether a link may be offered as a Join button.
    ///
    /// Matched on the host itself, or a subdomain of it. A plain `contains`
    /// check was used here, which also accepted `zoom.us.example.com` — an
    /// invitation is written by whoever sent it, so that turned any calendar
    /// invite into a trusted-looking button pointing anywhere.
    static func isMeetingLink(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func joinURL(in event: EKEvent) -> URL? {
        func matches(_ url: URL?) -> URL? {
            guard let url, isMeetingLink(url) else { return nil }
            return url
        }

        if let direct = matches(event.url) { return direct }

        let haystack = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !haystack.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let range = NSRange(haystack.startIndex..., in: haystack)
        for match in detector.matches(in: haystack, range: range) {
            if let found = matches(match.url) { return found }
        }
        return nil
    }
}
