import SwiftUI

/// Banner row shown at the top of the popover when a normal release is
/// available. "Update" hands off to Sparkle's standard install UI; "Later"
/// hides the banner for this session.
struct UpdateBannerView: View {
    let update: AvailableUpdate
    let onUpdate: () -> Void
    let onLater: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 18)

            Text(String(format: NSLocalizedString("Update available: v%@", comment: "Update banner text. %@ = version"), update.version))
                .font(.system(.caption, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onLater) {
                Text("Later")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Later", comment: "Hide the update banner for this session"))

            Button(action: onUpdate) {
                Text("Update")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .glassBackground(in: Capsule(), tint: .accentColor, interactive: true)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("Update", comment: "Install the available update"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
