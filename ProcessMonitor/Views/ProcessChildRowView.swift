import SwiftUI

struct ProcessChildRowView: View {
    let child: ProcessChild
    let onKill: () -> Void

    @State private var confirmingKill = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
                .zIndex(1)
            if confirmingKill {
                confirmBar
            }
        }
        .clipped()
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.tertiary)
                .frame(width: 3, height: 3)
                .frame(width: 10)

            Text(child.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: NSLocalizedString("PID %d", comment: "Process ID label"), child.id))
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Text(child.formattedCPU)
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 0) {
                Text(child.formattedMemory)
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Text(String(format: NSLocalizedString("%@ sw", comment: "Swap memory short label"), child.formattedSwap))
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
                Image(systemName: confirmingKill ? "xmark" : "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(confirmingKill ? NSLocalizedString("Cancel", comment: "") : NSLocalizedString("Kill this process", comment: ""))
        }
        .padding(.leading, 28)
        .padding(.trailing, 14)
        .padding(.vertical, 2)
    }

    private var confirmBar: some View {
        HStack(spacing: 8) {
            Text(String(
                format: NSLocalizedString("Kill %1$@ (PID %2$d)?", comment: "Kill child confirmation. %1=command, %2=pid"),
                child.command,
                child.id
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                withAnimation { confirmingKill = false }
                onKill()
            }) {
                Text("Kill")
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
}
