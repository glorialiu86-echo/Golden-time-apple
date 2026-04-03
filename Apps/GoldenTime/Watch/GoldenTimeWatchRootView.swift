import SwiftUI
import GoldenTimeCore

struct GoldenTimeWatchRootView: View {
    @StateObject private var model = GoldenTimeWatchViewModel()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GoldenTimeWatchFace(now: context.date, model: model)
                .onChange(of: context.date) { _, newValue in
                    model.refreshForTimeline(now: newValue)
                }
        }
    }
}

private struct GoldenTimeWatchFace: View {
    let now: Date
    @ObservedObject var model: GoldenTimeWatchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("本地算法 · 不联网")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                phaseRow

                if model.snapshot.hasFix {
                    countdownBlock(
                        title: "下次蓝调",
                        date: model.snapshot.nextBlueStart,
                        accent: Color(red: 0.5, green: 0.58, blue: 0.71)
                    )
                    countdownBlock(
                        title: "下次金调",
                        date: model.snapshot.nextGoldenStart,
                        accent: Color(red: 1.0, green: 0.67, blue: 0.0)
                    )
                } else {
                    Text("需要至少一次有效 GPS，用于离线推算太阳高度与相位。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(model.locationHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .onAppear {
            model.refreshForTimeline(now: now)
        }
    }

    @ViewBuilder
    private var phaseRow: some View {
        HStack {
            Text("当前")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let phase = model.phase {
                Text(phaseDisplayName(phase))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(phaseColor(phase))
            } else {
                Text("—")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countdownBlock(title: String, date: Date?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(accent)
            if let date {
                Text(Self.relativeCountdown(from: now, to: date))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(Self.timeFormatter.string(from: date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("今日无")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func phaseDisplayName(_ phase: PhaseState) -> String {
        switch phase {
        case .night: "夜间"
        case .blue: "蓝调"
        case .golden: "金调"
        case .day: "日间"
        }
    }

    private func phaseColor(_ phase: PhaseState) -> Color {
        switch phase {
        case .night: .indigo
        case .blue: Color(red: 0.5, green: 0.58, blue: 0.71)
        case .golden: Color(red: 1.0, green: 0.67, blue: 0.0)
        case .day: .orange
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static func relativeCountdown(from now: Date, to target: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now).rounded())
        if seconds <= 0 {
            return "已开始"
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
