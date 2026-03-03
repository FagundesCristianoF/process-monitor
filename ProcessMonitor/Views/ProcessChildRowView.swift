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
            Text("├")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(child.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("PID \(child.id)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            VStack(alignment: .trailing, spacing: 0) {
                Text(child.formattedMemory)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(child.formattedSwap) sw")
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
                    .foregroundStyle(confirmingKill ? .secondary : .secondary)
            }
            .buttonStyle(.plain)
            .help(confirmingKill ? "Cancel" : "Kill this process")
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }

    private var confirmBar: some View {
        HStack(spacing: 8) {
            Text("Kill \(child.command) (PID \(child.id))?")
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
