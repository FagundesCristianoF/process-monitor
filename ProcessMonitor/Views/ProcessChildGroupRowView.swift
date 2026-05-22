import SwiftUI

struct ProcessChildGroupRowView: View {
    let group: ProcessChildGroup
    let onKillGroup: () -> Void
    let onKillChild: (pid_t) -> Void

    @State private var isExpanded = false
    @State private var confirmingKill = false

    var body: some View {
        VStack(spacing: 0) {
            groupRow
                .zIndex(1)
            if confirmingKill {
                confirmBar
            }
            if isExpanded && group.count > 1 {
                childrenList
            }
        }
        .clipped()
    }

    // MARK: - Group Row

    private var groupRow: some View {
        HStack(spacing: 8) {
            expandIndicator

            Text(group.name)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if group.count > 1 {
                Text("×\(group.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text(group.formattedCPU)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            VStack(alignment: .trailing, spacing: 0) {
                Text(group.formattedMemory)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(String(format: NSLocalizedString("%@ sw", comment: "Swap memory short label"), group.formattedSwap))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 64, alignment: .trailing)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    confirmingKill.toggle()
                }
            }) {
                Image(systemName: confirmingKill ? "xmark" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(
                confirmingKill
                ? NSLocalizedString("Cancel", comment: "Cancel button")
                : (group.count > 1
                    ? String(format: NSLocalizedString("Kill all %@", comment: "Kill all of a given process name"), group.name)
                    : NSLocalizedString("Kill this process", comment: "Kill a single process"))
            )
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard group.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var expandIndicator: some View {
        if group.count > 1 {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 7))
                .foregroundStyle(.tertiary)
                .frame(width: 8)
        } else {
            Text("├")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Confirm Bar

    private var confirmBar: some View {
        HStack(spacing: 8) {
            Text(group.count > 1
                 ? String(format: NSLocalizedString("Kill all %1$lld %2$@?", comment: "Kill all N of NAME confirmation"), group.count, group.name)
                 : String(format: NSLocalizedString("Kill %1$@ (PID %2$d)?", comment: "Kill child confirmation. %1=command, %2=pid"), group.name, group.children.first?.id ?? 0))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                withAnimation { confirmingKill = false }
                onKillGroup()
            }) {
                Text(group.count > 1 ? "Kill All" : "Kill")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 36)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(Color.red.opacity(0.06))
        .transition(.opacity)
    }

    // MARK: - Individual Children

    private var childrenList: some View {
        VStack(spacing: 0) {
            ForEach(group.children) { child in
                ProcessChildRowView(child: child) {
                    onKillChild(child.id)
                }
            }
        }
        .padding(.leading, 12)
        .transition(.opacity)
    }
}
