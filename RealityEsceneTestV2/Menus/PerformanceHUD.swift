// PerformanceHUD.swift
// RealityEsceneTestV2
//
// One HUD for every scene.
//
// V1 had three near-identical HUD files, each showing instantaneous FPS and a
// CPU percentage. A demo whose argument is "this machine can run real-time 3D"
// has to show the numbers a benchmark would: average and 1% low frame rate,
// frame time against the display's own budget, GPU utilisation, memory, and
// the frame time graph where stutter is visible rather than averaged away.

import SwiftUI

// MARK: - Model

struct HUDStat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var tint: Color = .white
}

// MARK: - HUD

struct PerformanceHUD: View {
    let title: String
    let subtitle: String
    let feature: String

    let stats: FrameStats
    let hardware: HardwareMetrics
    let quality: QualityPreset
    let extraStats: [HUDStat]
    var expanded: Bool = true

    private var info: SystemInfo { .current }

    // Colour against the display's own ceiling, not an arbitrary 60.
    private var fpsTint: Color {
        let ratio = stats.averageFPS / Double(stats.displayRefreshRate)
        if ratio > 0.92 { return .green }
        if ratio > 0.70 { return .yellow }
        return .orange
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: Top bar
            HStack(alignment: .top) {
                sceneBadge
                Spacer()
                machineBadge
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)

            Spacer()

            // MARK: Bottom bar
            HStack(alignment: .bottom) {
                controlsBadge
                Spacer()
                if expanded { metricsPanel } else { compactMetrics }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Top left

    private var sceneBadge: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 6) {
                Circle().fill(.cyan).frame(width: 5, height: 5)
                Text(feature)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.9))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(panel)
    }

    // MARK: - Top right

    private var machineBadge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(info.shortChip)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text("\(info.coreSummary)  ·  \(info.gpuSummary)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(info.memoryGB) GB unified  ·  \(info.displayRefreshRate) Hz  ·  \(info.osVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(panel)
    }

    // MARK: - Bottom left

    private var controlsBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            keyRow("WASD", "move")
            keyRow("SHIFT", "sprint")
            keyRow("E", "fire")
            keyRow("TAB", "menu")
            keyRow("1 2 3", "quality")
            keyRow("R", "reload")
            keyRow("H", "hud")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(panel)
    }

    private func keyRow(_ key: String, _ action: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 42, alignment: .leading)
            Text(action)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Bottom right

    private var compactMetrics: some View {
        HStack(spacing: 14) {
            Text("\(Int(stats.fps.rounded()))")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(fpsTint)
            Text("FPS")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(panel)
    }

    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Headline frame rate against the panel's refresh rate.
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(Int(stats.fps.rounded()))")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(fpsTint)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 0) {
                    Text("FPS")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("/ \(stats.displayRefreshRate) Hz")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Text(quality.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.cyan))
            }

            frameGraph

            divider

            // Benchmark-style rows.
            statRow("AVG", String(format: "%.0f fps", stats.averageFPS))
            statRow("1% LOW", String(format: "%.0f fps", stats.onePercentLowFPS),
                    tint: stats.onePercentLowFPS < Double(stats.displayRefreshRate) * 0.5 ? .orange : .white)
            statRow("FRAME", String(format: "%.2f ms", stats.frameTimeMS))
            statRow("P99", String(format: "%.2f ms", stats.p99FrameTimeMS))
            if stats.droppedFrames > 0 {
                statRow("DROPPED", "\(stats.droppedFrames)", tint: .orange)
            }

            divider

            statRow("CPU", String(format: "%.0f%%", hardware.cpuUsage))
            if hardware.gpuAvailable {
                statRow("GPU", String(format: "%.0f%%", hardware.gpuUtilization))
            }
            statRow("ALLOC", byteString(hardware.allocatedBytes))

            if !extraStats.isEmpty {
                divider
                ForEach(extraStats) { stat in
                    statRow(stat.label, stat.value, tint: stat.tint)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 272, alignment: .leading)
        .background(panel)
    }

    // Frame time history. The dashed line is the display's budget: bars above
    // it are frames that missed it.
    // Drawn in a Canvas rather than as a stack of Rectangles. A ForEach over
    // 120 bars rebuilds 120 views every time the stats publish, ten times a
    // second, which was itself showing up as a hitch in the graph it draws.
    private var frameGraph: some View {
        Canvas { context, size in
            let samples = stats.graph
            guard !samples.isEmpty else { return }

            // The display's budget sits at half height: FrameStats normalises
            // against twice it, so anything above this line missed the frame.
            let budgetY = size.height * 0.5
            context.stroke(
                Path { $0.move(to: .init(x: 0, y: budgetY))
                        $0.addLine(to: .init(x: size.width, y: budgetY)) },
                with: .color(.white.opacity(0.18)),
                lineWidth: 1
            )

            let step = size.width / CGFloat(samples.count)
            let width = max(step - 1, 1)

            for (index, value) in samples.enumerated() {
                let height = max(1, size.height * value)
                let rect = CGRect(
                    x: CGFloat(index) * step,
                    y: size.height - height,
                    width: width,
                    height: height
                )
                context.fill(
                    Path(rect),
                    with: .color(value > 0.5 ? .orange : .cyan.opacity(0.85))
                )
            }
        }
        .frame(height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.04)))
    }

    private func statRow(_ label: String, _ value: String, tint: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.black.opacity(0.62))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
    }

    private func byteString(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024
            ? String(format: "%.2f GB", mb / 1024)
            : String(format: "%.0f MB", mb)
    }
}
