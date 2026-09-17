import SwiftUI
import Charts

struct DiskUsageChartView: View {
    let entries: [DiskUsageEntry]
    let isScanning: Bool
    let lastScanDate: Date?
    let onScan: () -> Void

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Largest Folders", comment: "Disk usage chart title"))
                                .font(.system(.callout, weight: .semibold))
                                .foregroundStyle(.primary)
                            if let lastScanDate {
                                Text(lastScanDate, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
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
}
