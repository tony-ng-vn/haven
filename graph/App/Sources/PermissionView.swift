import SwiftUI

/// Shown when chat.db could not be opened. Plain language: what to grant, where, and how to
/// retry, since this is very likely the very first screen a first-time user ever sees.
struct PermissionView: View {
    let explanation: String
    let onTryAgain: () -> Void

    /// Full Disk Access is a category inside Privacy & Security, not its own settings pane;
    /// this URL scheme opens straight to that category so there is no navigating to find it.
    private static let fullDiskAccessURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("ConnectionGraph needs Full Disk Access")
                .font(.title2)
                .bold()

            Text(explanation)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("To fix this:")
                    .bold()
                Text("1. Open System Settings > Privacy & Security > Full Disk Access.")
                Text("2. Add ConnectionGraph to the list, or turn on its toggle if it is already listed.")
                Text("3. Come back here and press Try Again (or relaunch the app).")
            }
            .frame(maxWidth: 420, alignment: .leading)

            // Contacts has no separate permission prompt here: the app reads the address
            // book database file directly, the same way it reads chat.db, so one grant
            // covers both names/photos and messages.
            Text("Contact names and photos arrive through this same grant -- there is no separate Contacts permission step.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(Self.fullDiskAccessURL)
                }
                .buttonStyle(.borderedProminent)

                Button("Try Again", action: onTryAgain)
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
