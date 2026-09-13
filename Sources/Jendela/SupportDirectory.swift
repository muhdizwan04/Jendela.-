import Foundation
import ObjectiveC

/// The one place the app keeps its files, and the one-time move from the old
/// name.
///
/// Renaming the app changed the Application Support folder, which silently
/// orphaned every existing settings file, note and sign-in. Anything that
/// writes to disk must go through here so that can't happen again.
enum SupportDirectory {
    private static let currentName = "Jendela"
    private static let previousNames = ["WidgetMac"]

    static let root: URL = {
        // Tests and diagnostics point this elsewhere so a run can never touch
        // real notes, clipboard history or sign-ins.
        // A test run must never touch real notes, clipboard history or
        // sign-ins, and relying on the caller to remember an environment
        // variable is one forgotten flag away from data loss.
        if NSClassFromString("XCTestCase") != nil {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("jendela-tests", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        if let override = ProcessInfo.processInfo.environment["JENDELA_SUPPORT_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(currentName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        migrate(into: url, from: base)
        return url
    }()

    /// Copies a previous name's contents across, once, and only into a folder
    /// that has nothing of its own to lose.
    private static func migrate(into destination: URL, from base: URL) {
        let manager = FileManager.default
        let marker = destination.appendingPathComponent(".migrated")
        guard !manager.fileExists(atPath: marker.path) else { return }

        for name in previousNames {
            let old = base.appendingPathComponent(name, isDirectory: true)
            guard manager.fileExists(atPath: old.path),
                  let items = try? manager.contentsOfDirectory(atPath: old.path)
            else { continue }

            for item in items where !item.hasPrefix(".") {
                let source = old.appendingPathComponent(item)
                let target = destination.appendingPathComponent(item)
                // Never overwrite: anything already written under the new name
                // is newer than what is being migrated.
                guard !manager.fileExists(atPath: target.path) else { continue }
                try? manager.copyItem(at: source, to: target)
            }
        }
        try? Data().write(to: marker)
    }
}
