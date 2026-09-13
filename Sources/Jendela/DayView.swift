import EventKit
import SwiftUI

/// "Day": what is next, and what is running out of charge.
struct DayNotchSection: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        // A busy day and several batteries together run past the card, which
        // is a fixed height.
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                meetings
                Divider().overlay(.white.opacity(0.08))
                batteries
            }
        }
        .onAppear {
            state.batteries.refresh()
            state.meetings.refresh()
        }
    }

    // MARK: - Meetings

    @ViewBuilder
    private var meetings: some View {
        if state.meetings.needsPermission {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show your next meeting").font(.system(size: 12, weight: .semibold))
                    Text("Needs access to your calendar")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 4)
                Button("Allow") { state.meetings.requestAccess() }
                    .buttonStyle(.borderedProminent)
                    .tint(state.appliedTheme.accentColor)
                    .controlSize(.small)
            }
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        } else if state.meetings.upcoming.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.white.opacity(0.35))
                Text("Nothing else today")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            VStack(spacing: 6) {
                ForEach(state.meetings.upcoming.prefix(3)) { meeting in
                    row(meeting)
                }
            }
        }
    }

    private func row(_ meeting: Meetings.Meeting) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: UInt32(meeting.calendarColour)))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title).font(.system(size: 12)).lineLimit(1)
                Text(meeting.whenText)
                    .font(.system(size: 9, weight: meeting.isNow ? .bold : .regular))
                    .foregroundStyle(meeting.isNow ? Color.green : .white.opacity(0.45))
            }
            Spacer(minLength: 4)
            if let url = meeting.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                    state.closeNotch()
                } label: {
                    Text("Join")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(state.appliedTheme.accentColor, in: Capsule())
                        .foregroundStyle(Color.black.opacity(0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Batteries

    @ViewBuilder
    private var batteries: some View {
        HStack(spacing: 10) {
            if let mac = state.batteries.mac {
                level(
                    symbol: mac.charging ? "battery.100.bolt" : "laptopcomputer",
                    name: "This Mac",
                    detail: mac.timeText ?? (mac.charging ? "Charging" : ""),
                    percent: mac.percent
                )
            }
            ForEach(state.batteries.devices.prefix(2)) { device in
                level(
                    symbol: device.symbol,
                    name: device.name,
                    detail: device.left != nil && device.right != nil
                        ? "L \(device.left!)% · R \(device.right!)%"
                        : (device.caseLevel.map { "Case \($0)%" } ?? ""),
                    percent: device.lowest ?? 0
                )
            }
        }
    }

    private func level(symbol: String, name: String, detail: String, percent: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(percent <= 20 ? .orange : .white.opacity(0.75))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(percent <= 20 ? .orange : .white)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }
}
