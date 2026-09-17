import SwiftUI
import Charts

struct DiskUsageChartView: View {
    let entries: [DiskUsageEntry]
    let suggestions: [(entry: DiskUsageEntry, command: CleanupCommand)]
    let isScanning: Bool
    let anyRunning: Bool
    let onScan: () -> Void
    let onRunSuggestion: (UUID) -> Void

    @AppStorage("storageChartExpanded") private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(NSLocalizedString("Largest Folders", comment: "Disk usage chart title"))
                            .font(.system(.callout, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                Button(action: onScan) {
                    HStack(spacing: 4) {
                        if isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(NSLocalizedString("Scan", comment: "Scan disk usage button"))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassBackground(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(isScanning)
            }

            if isExpanded {
                chartContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var chartContent: some View {
        if isScanning && entries.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                    Text(NSLocalizedString("Scanning folders…", comment: "Disk scan in progress"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
                Spacer()
            }
        } else if entries.isEmpty {
            Text(NSLocalizedString("Tap Scan to find which folders use the most space.", comment: "Disk chart empty state"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
        } else {
            if !suggestions.isEmpty {
                suggestionsSection
            }

            Chart(entries) { entry in
                BarMark(
                    x: .value("Size", entry.bytes),
                    y: .value("Folder", entry.displayName)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(entry.formattedSize)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(height: CGFloat(min(entries.count, 10)) * 28 + 16)
            .chartPlotStyle { plot in
                plot.padding(.trailing, 52)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries.prefix(5)) { entry in
                    HStack(spacing: 6) {
                        Text(entry.formattedSize)
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        Text(entry.path)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(NSLocalizedString("Reveal in Finder", comment: ""))
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("Suggested cleanups", comment: "Header for folder-based cleanup suggestions"))
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(suggestions, id: \.command.id) { item in
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.command.name)
                            .font(.system(.caption, weight: .semibold))
                        Text(String(
                            format: NSLocalizedString("%@ in %@", comment: "Cleanup suggestion size in folder"),
                            item.entry.formattedSize,
                            item.entry.displayName
                        ))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        onRunSuggestion(item.command.id)
                    } label: {
                        Text(NSLocalizedString("Run", comment: ""))
                            .font(.system(.caption2, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassBackground(in: Capsule(), tint: .accentColor, interactive: true)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(anyRunning || !item.command.isEnabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
        .padding(.bottom, 4)
    }
}
