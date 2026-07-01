import SwiftUI
import AppKit

struct ProcessRowView: View {
    let process: MonitoredProcess
    let onKillGroup: () -> Void
    let onRestart: () -> Void
    let onKillChildGroup: ([pid_t]) -> Void
    let onKillChild: (pid_t) -> Void
    let logWriter: ProcessLogWriterService
    let isLoggingEnabled: Bool
    let onToggleLogging: (Bool) -> Void

    @State private var isExpanded = false
    @State private var confirmingKill = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
                .zIndex(1)
            if confirmingKill {
                killConfirmBar
            }
            if isExpanded && !process.childGroups.isEmpty {
                childrenList
            }
        }
        .clipped()
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(spacing: 10) {
            expandButton
            appIcon
            statusIcon
            nameLabel
            Spacer(minLength: 6)
            sparkline
            memoryLabel
            killButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard process.status != .notRunning, !process.childGroups.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            onToggleLogging(!isLoggingEnabled)
        } label: {
            Label(
                NSLocalizedString("Log to File", comment: "Context menu: enable/disable file logging"),
                systemImage: isLoggingEnabled ? "checkmark.square" : "square"
            )
        }

        if let bytes = logWriter.fileSizeBytes(forAppID: process.definition.id) {
            Divider()

            let isOverThreshold = bytes >= ProcessLogWriterService.warningThresholdBytes
            Text(String(
                format: NSLocalizedString("Log size: %@", comment: "Context menu: current log file size"),
                formatMemory(Double(bytes) / 1_048_576)
            ))
            if isOverThreshold {
                Label(
                    NSLocalizedString("Log file is large", comment: "Context menu: log file over 10MB warning"),
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            Button {
                logWriter.revealLog(forAppID: process.definition.id)
            } label: {
                Label(NSLocalizedString("Reveal Log", comment: "Context menu action"), systemImage: "folder")
            }

            Button {
                logWriter.clearLog(forAppID: process.definition.id)
            } label: {
                Label(NSLocalizedString("Clear Log", comment: "Context menu action"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var expandButton: some View {
        if process.status != .notRunning && !process.childGroups.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.18), value: isExpanded)
        } else {
            Spacer().frame(width: 14)
        }
    }

    private var appIcon: some View {
        AppIconBadge(
            definition: process.definition,
            bundlePath: process.appBundlePath,
            size: 22,
            dimmed: process.status == .notRunning
        )
    }

    private var statusIcon: some View {
        Group {
            switch process.status {
            case .notRunning:
                Circle()
                    .fill(.gray.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(.gray.opacity(0.2), lineWidth: 0.5)
                    )
            case .running:
                Circle()
                    .fill(LinearGradient(
                        colors: [.green, Color.green.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 7, height: 7)
                    .shadow(color: .green.opacity(0.5), radius: 2)
            case .overLimit:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 12)
    }

    private var nameLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(process.definition.displayName)
                .font(.system(.callout, weight: .semibold))
                .lineLimit(1)

            if process.status != .notRunning && !process.children.isEmpty {
                let groupCount = process.childGroups.count
                let totalCount = process.children.count
                let processesLabel = totalCount == 1
                    ? NSLocalizedString("1 process", comment: "Singular process count")
                    : String(format: NSLocalizedString("%lld processes", comment: "Plural process count"), totalCount)
                let groupsLabel = groupCount == 1
                    ? NSLocalizedString("1 group", comment: "Singular group count")
                    : String(format: NSLocalizedString("%lld groups", comment: "Plural group count"), groupCount)
                Text(String(
                    format: NSLocalizedString("%1$@ in %2$@", comment: "Children summary: <N processes> in <M groups>"),
                    processesLabel,
                    groupsLabel
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            if process.status != .notRunning, let starter = process.startedBy {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(String(format: NSLocalizedString("Started by %@", comment: "Parent process info"), starter))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if process.status == .notRunning {
                Text("Not running")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var memoryLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 6) {
                if process.status != .notRunning {
                    Text(process.formattedCPU)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                Text(process.formattedMemory)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(process.status == .overLimit ? .orange : .primary)
            }

            if process.status != .notRunning {
                Text(String(format: NSLocalizedString("%@ swap", comment: "Swap memory label"), process.formattedSwap))
                    .font(.system(.caption2, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 120, alignment: .trailing)
    }

    @ViewBuilder
    private var sparkline: some View {
        if process.status != .notRunning && process.memoryHistory.count >= 2 {
            let samples = Array(process.memoryHistory.suffix(60))
            let accent: Color = process.status == .overLimit ? .orange : .accentColor
            if #available(macOS 26.0, *) {
                sparklineCanvas(samples: samples, accent: accent, fillOpacity: 0.0)
            } else {
                sparklineCanvas(samples: samples, accent: accent, fillOpacity: 0.35)
            }
        }
    }

    private func sparklineCanvas(samples: [Double], accent: Color, fillOpacity: Double) -> some View {
        Canvas { ctx, size in
            guard let maxVal = samples.max(), maxVal > 0 else { return }
            let stepX = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
            var line = Path()
            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let norm = CGFloat(v / maxVal)
                let y = size.height - (norm * (size.height - 1)) - 0.5
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            if fillOpacity > 0 {
                var fill = line
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                ctx.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [accent.opacity(fillOpacity), accent.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
            ctx.stroke(line, with: .color(accent.opacity(0.85)), lineWidth: 1.2)
        }
        .frame(width: 56, height: 18)
    }

    @ViewBuilder
    private var killButton: some View {
        if process.status != .notRunning {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    confirmingKill.toggle()
                }
            }) {
                Image(systemName: confirmingKill ? "xmark" : "power")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(confirmingKill ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                    .glassBackground(
                        in: Circle(),
                        interactive: true
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help(confirmingKill ? NSLocalizedString("Cancel", comment: "") : NSLocalizedString("Kill", comment: ""))
        } else {
            Spacer().frame(width: 32)
        }
    }

    // MARK: - Kill Confirm Bar

    private var killConfirmBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
            Text(process.definition.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            if process.canRestart {
                confirmActionButton(
                    title: NSLocalizedString("Restart", comment: ""),
                    tint: .blue,
                    action: {
                        withAnimation { confirmingKill = false }
                        onRestart()
                    }
                )
            }

            confirmActionButton(
                title: NSLocalizedString("Kill All", comment: ""),
                tint: .red,
                action: {
                    withAnimation { confirmingKill = false }
                    onKillGroup()
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Color.red.opacity(0.08)
                LinearGradient(
                    colors: [Color.red.opacity(0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.red.opacity(0.25))
                .frame(height: 0.5),
            alignment: .top
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func confirmActionButton(
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassBackground(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if process.status == .overLimit {
            if #available(macOS 26.0, *) {
                // On glass windows the gradient bleeds through prominently — accent bar only.
                Color.clear.overlay(
                    Rectangle()
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: 2),
                    alignment: .leading
                )
            } else {
                LinearGradient(
                    colors: [Color.orange.opacity(0.12), Color.orange.opacity(0.03)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .overlay(
                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 2),
                    alignment: .leading
                )
            }
        }
    }

    // MARK: - Children

    private var childrenList: some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 32)
            ForEach(process.childGroups) { group in
                ProcessChildGroupRowView(
                    group: group,
                    onKillGroup: { onKillChildGroup(group.pids) },
                    onKillChild: { pid in onKillChild(pid) }
                )
            }
            Divider().padding(.leading, 32)
        }
        .transition(.opacity)
    }
}
