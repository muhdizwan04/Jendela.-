import SwiftUI

/// Shown in place of a Pro tab once the trial is over.
///
/// Deliberately calm: it states what the tab does, what it costs, and gets out
/// of the way. Nothing is nagged at while the trial is running, and the free
/// features keep working forever.
struct PaywallView: View {
    @ObservedObject var state: JendelaState
    let feature: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(state.appliedTheme.accentColor)

            Text(feature)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("See pricing") { state.openPurchasePage() }
                    .buttonStyle(.borderedProminent)
                    .tint(state.appliedTheme.accentColor)
                    .controlSize(.small)
                Button("Enter key") { state.showLicenceEntry() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
    }
}

/// Licence status and key entry, in Settings.
struct LicenceCard: View {
    @ObservedObject var state: JendelaState
    @State private var key = ""
    @State private var justActivated = false

    var body: some View {
        ControlCard(
            title: "Licence",
            subtitle: state.licensing.summary,
            symbol: state.licensing.isPro ? "checkmark.seal.fill" : "seal"
        ) {
            switch state.licensing.status {
            case .licensed:
                HStack {
                    Text("Thank you — everything is unlocked.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button("Remove") { state.licensing.deactivate() }
                        .buttonStyle(SoftButtonStyle())
                        .frame(width: 90)
                }
            case .trial(let days):
                Text("Every feature is unlocked for \(days) more day\(days == 1 ? "" : "s"). After that the hub, notes and music keep working; clipboard history, the shelf, Day and AI need a licence.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                entry
            case .expired:
                Text("The trial has finished. The hub, notes and music still work.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                entry
            }
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TextField("Paste your licence key", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                Button("Activate") {
                    justActivated = state.licensing.activate(key)
                    if justActivated { key = "" }
                }
                .buttonStyle(.borderedProminent)
                .tint(state.appliedTheme.accentColor)
                .controlSize(.small)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error = state.licensing.lastError {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            Button("Buy a licence") { state.openPurchasePage() }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.appliedTheme.accentColor)
        }
    }
}
