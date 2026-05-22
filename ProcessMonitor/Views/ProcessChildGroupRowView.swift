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
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if group.count > 1 {
                Text("×\(group.count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(.quaternary.opacity(0.6))
                    )
                    .foregroundStyle(.secondary)
            }

            Text(group.formattedCPU)
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 0) {
                Text(group.formattedMemory)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(String(format: NSLocalizedString("%@ sw", comment: "Swap memory short label"), group.formattedSwap))
                    .font(.system(.caption2, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 70, alignment: .trailing)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    confirmingKill.toggle()
                }
            }) {
                Image(systemName: confirmingKill ? "xmark" : "minus.circle.fill")
                    .font(.system(size: 11))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(confirmingKill ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red.opacity(0.7)))
                    .frame(width: 16, height: 16)
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
        .padding(.leading, 28)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeOut(duration: 0.18), value: isExpanded)
        } else {
            Circle()
                .fill(.tertiary)
                .frame(width: 3, height: 3)
                .frame(width: 10)
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
