import AppKit
import SwiftUI

/// First-run introduction.
///
/// The app previously dropped panels on screen and asked for Automation and
/// Accessibility with no explanation, which reads as malware. Each permission
/// is explained here, in the user's own time, and every one is optional: the
/// app is useful without granting any of them.
struct OnboardingView: View {
    @ObservedObject var state: JendelaState
    @State private var step = 0

    private struct Page {
        var symbol: String
        var title: String
        var body: String
        var action: String?
        var run: ((JendelaState) -> Void)?
    }

    private var pages: [Page] {
        [
            Page(
                symbol: "rectangle.topthird.inset.filled",
                title: "Everything lives at the notch",
                body: "Move the pointer to the notch and the hub opens. It holds your clipboard, notes, music, sound, a file shelf and a quick chat. Move away and it closes again.",
                action: nil, run: nil
            ),
            Page(
                symbol: "command",
                title: "Or use the keyboard",
                body: "⌘⇧Space opens the hub, ⌘⇧V goes straight to the clipboard, ⌘⇧N to your notes. All of them can be changed in Settings.",
                action: nil, run: nil
            ),
            Page(
                symbol: "lock.shield",
                title: "Permissions, only if you want them",
                body: "Controlling Music or Spotify needs Automation. Driving YouTube Music with the media keys needs Accessibility. Nothing else asks for anything, and the app works without either — you will only be prompted when you first use those controls.",
                action: "Open Privacy settings",
                run: { _ in Permissions.openSettings(.automation) }
            ),
            Page(
                symbol: "bolt.badge.clock",
                title: "Built to stay out of the way",
                body: "Music, audio and power changes all arrive as system events rather than being polled, and effects step down on battery. Your clipboard history is encrypted on this Mac and never leaves it.",
                action: "Open at login",
                run: { state in state.launchAtLogin = true }
            )
        ]
    }

    var body: some View {
        let page = pages[min(step, pages.count - 1)]

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: page.symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(state.appliedTheme.accentColor)
                .padding(.bottom, 22)

            Text(page.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(page.body)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, 10)

            if let action = page.action, let run = page.run {
                Button(action) { run(state) }
                    .buttonStyle(.bordered)
                    .padding(.top, 16)
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == step ? state.appliedTheme.accentColor : .white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 18)

            HStack {
                Button("Skip") { state.finishOnboarding() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button(step == pages.count - 1 ? "Start using Jendela." : "Next") {
                    if step == pages.count - 1 { state.finishOnboarding() } else { step += 1 }
                }
                .buttonStyle(.borderedProminent)
                .tint(state.appliedTheme.accentColor)
            }
        }
        .padding(30)
        .frame(width: 540, height: 420)
        .background(Color(hex: 0x121318))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}
