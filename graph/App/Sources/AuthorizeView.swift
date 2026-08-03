import SwiftUI
import GraphCore

/// Onboarding step 2: two live checks (not permission-API guesses -- see AppModel's
/// MessagesAccessProbe/ContactsAccessProbe calls), each shown as its own row. Continue only
/// enables once Messages is granted and Contacts is not actively blocked (an empty address
/// book is not a block -- see Onboarding.canProceedFromAuthorize's own doc comment).
struct AuthorizeView: View {
    let model: AppModel

    private var canContinue: Bool {
        Onboarding.canProceedFromAuthorize(
            messagesGranted: model.messagesAccessGranted,
            contactsState: model.contactsAccessState
        )
    }

    private var anyBlocked: Bool {
        !model.messagesAccessGranted || model.contactsAccessState == .blocked
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Authorize access")
                .font(.title2)
                .bold()

            Text(
                "Your Sky needs Full Disk Access to read Messages and Contacts directly "
                    + "off this Mac. One grant covers both -- there is no separate Contacts "
                    + "permission step."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 460)

            VStack(spacing: 10) {
                checkRow(
                    title: "Messages",
                    granted: model.messagesAccessGranted,
                    subtitle: model.messagesAccessGranted ? "Granted" : "Blocked"
                )
                checkRow(
                    title: "Contacts",
                    granted: model.contactsAccessState != .blocked,
                    subtitle: contactsSubtitle
                )
            }
            .frame(maxWidth: 420)

            if anyBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("To fix this:").bold()
                    Text("1. Open System Settings > Privacy & Security > Full Disk Access.")
                    Text("2. Add Your Sky to the list, or turn on its toggle if it is already listed.")
                    Text(
                        "3. The grant only takes effect the next time Your Sky starts -- quit and "
                            + "reopen the app (or press Relaunch below) after toggling. Re-check "
                            + "cannot show a grant made while this same running copy is still open."
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420, alignment: .leading)

                // Every rebuild is a new app to macOS TCC under ad-hoc signing (no Apple team on
                // this machine to give successive builds a stable identity): a grant from a
                // previous copy of Your Sky does not carry over, and the Full Disk Access list
                // can end up holding a stale entry for a copy that no longer exists. Naming the
                // running copy's own path is what lets the user tell which entry is the right one.
                Text(
                    "An updated or rebuilt copy of Your Sky counts as a new app to macOS. If Your "
                        + "Sky is already listed above but still shows Blocked, remove that old "
                        + "entry and add this copy instead -- it is currently running from:\n"
                        + Bundle.main.bundlePath
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(PermissionView.fullDiskAccessURL)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Re-check") {
                        model.refreshAccessState()
                    }
                    .buttonStyle(.bordered)

                    Button("Relaunch") {
                        model.relaunch()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Continue") {
                model.confirmPermissionsAndContinue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear { model.refreshAccessState() }
    }

    private var contactsSubtitle: String {
        switch model.contactsAccessState {
        case .granted: return "Granted"
        case .blocked: return "Blocked"
        case .noData: return "No Contacts data found on this Mac (optional)"
        }
    }

    private func checkRow(title: String, granted: Bool, subtitle: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
