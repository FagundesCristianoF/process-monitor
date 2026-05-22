import SwiftUI

struct ProcessRowView: View {
    let process: MonitoredProcess
    let onKillGroup: () -> Void
    let onRestart: () -> Void
    let onKillChildGroup: ([pid_t]) -> Void
    let onKillChild: (pid_t) -> Void

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
        HStack(spacing: 8) {
            expandButton
            statusIcon
            nameLabel
            Spacer()
            sparkline
            memoryLabel
            killButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            guard process.status != .notRunning, !process.childGroups.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var expandButton: some View {
        if process.status != .notRunning && !process.childGroups.isEmpty {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        } else {
            Spacer().frame(width: 12)
        }
    }

    private var statusIcon: some View {
        Group {
            switch process.status {
            case .notRunning:
                Circle()
                    .fill(.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            case .running:
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            case .overLimit:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var nameLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(process.definition.displayName)
                .font(.system(.body, weight: .medium))
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
                .foregroundStyle(.secondary)
            }
        }
    }

    private var memoryLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 6) {
                if process.status != .notRunning {
                    Text(process.formattedCPU)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(process.formattedMemory)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(process.status == .overLimit ? .orange : .primary)
            }

            if process.status != .notRunning {
                Text(String(format: NSLocalizedString("%@ swap", comment: "Swap memory label"), process.formattedSwap))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, alignment: .trailing)
    }

    @ViewBuilder
    private var sparkline: some View {
        if process.status != .notRunning && process.memoryHistory.count >= 2 {
            let samples = Array(process.memoryHistory.suffix(60))
            Canvas { ctx, size in
                guard let maxVal = samples.max(), maxVal > 0 else { return }
                let stepX = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
                var path = Path()
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * stepX
                    let norm = CGFloat(v / maxVal)
                    let y = size.height - (norm * size.height)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                ctx.stroke(path, with: .color(Color.accentColor.opacity(0.7)), lineWidth: 1)
            }
            .frame(width: 50, height: 16)
        }
    }

    @ViewBuilder
    private var killButton: some View {
        if process.status != .notRunning {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    confirmingKill.toggle()
                }
            }) {
                Text(confirmingKill ? "Cancel" : "Kill")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confirmingKill ? .gray.opacity(0.15) : .red.opacity(0.15))
                    .foregroundStyle(confirmingKill ? Color.secondary : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        } else {
            Spacer().frame(width: 48)
        }
    }

    // MARK: - Kill Confirm Bar

    private var killConfirmBar: some View {
        HStack(spacing: 8) {
            Text(process.definition.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if process.appBundlePath != nil {
                Button(action: {
                    withAnimation { confirmingKill = false }
                    onRestart()
                }) {
                    Text("Restart")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                withAnimation { confirmingKill = false }
                onKillGroup()
            }) {
                Text("Kill All")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.06))
        .transition(.opacity)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if process.status == .overLimit {
            RoundedRectangle(cornerRadius: 6)
                .fill(.orange.opacity(0.08))
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
