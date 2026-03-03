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
                Text(
                    "\(totalCount) process\(totalCount == 1 ? "" : "es")"
                    + " in \(groupCount) group\(groupCount == 1 ? "" : "s")"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var memoryLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(process.formattedMemory)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(process.status == .overLimit ? .orange : .primary)

            if process.status != .notRunning {
                Text("\(process.formattedSwap) swap")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, alignment: .trailing)
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
