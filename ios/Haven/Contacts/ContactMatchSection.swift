import ContactsUI
import SwiftUI

/// Device-contact rows for a name or phone number somebody just typed.
///
/// Only ever "where else does this person live" -- a match already in Haven
/// is not drawn here at all, because the screen hosting this section is
/// already showing that person as a normal result. This is only the people
/// the caller's own directory does not yet cover.
struct ContactMatchSection: View {
    @ObservedObject var model: ContactMatchModel
    let query: String
    /// Runs once an import has landed on disk, so the host can ask for a
    /// drain the same way `AddPersonSheet` and the share sheet already do.
    let onImported: () -> Void

    @State private var pickerPresented = false

    var body: some View {
        Group {
            switch model.state.status {
            case .denied, .restricted:
                deniedRow
            case .notDetermined:
                accessButtonRow
            case .limited:
                VStack(alignment: .leading, spacing: 0) {
                    resultRows
                    accessButtonRow
                }
            case .authorized:
                resultRows
            @unknown default:
                EmptyView()
            }
        }
        .task(id: query) {
            await model.search(query)
        }
    }

    @ViewBuilder
    private var resultRows: some View {
        if model.state.searchFailed {
            Text("Could not search your contacts.")
                .havenSecondary()
        } else {
            ForEach(model.state.rows) { contact in
                importRow(contact)
            }
        }
    }

    private func importRow(_ contact: AddressBookContact) -> some View {
        HavenRow(
            title: contact.name,
            detail: "In Contacts",
            accessibilityText: "\(contact.name), in your contacts, not yet in Haven",
            action: { Task { await importTapped(contact) } }
        ) {
            RowAccessory(text: "Add")
        }
    }

    /// Covers contacts this authorization level cannot see: it does its own
    /// search over the unshared set and grants exactly the contact somebody
    /// taps inside it, moving `.notDetermined` to `.limited` on first use
    /// without Haven ever prompting for anything up front.
    private var accessButtonRow: some View {
        ContactAccessButton(
            queryString: query,
            ignoredEmails: model.ignoredEmails,
            ignoredPhoneNumbers: model.ignoredPhoneNumbers
        ) { identifiers in
            Task { await model.reveal(identifiers: identifiers) }
        }
        .accessibilityLabel("See more matches from Contacts")
        .accessibilityHint("Opens a search over contacts Haven cannot see yet")
    }

    private var deniedRow: some View {
        HavenRow(
            title: "Open from Contacts",
            accessibilityText: "Open from Contacts. Browse your address book without giving Haven access.",
            action: { pickerPresented = true }
        ) {
            RowMark.chevron
        }
        .sheet(isPresented: $pickerPresented) {
            ContactPicker { contact in
                Task { await pickerPicked(contact) }
            }
        }
    }

    private func importTapped(_ contact: AddressBookContact) async {
        guard model.enqueueImport(contact) else { return }
        onImported()
    }

    private func pickerPicked(_ contact: AddressBookContact) async {
        guard await model.importPicked(contact) else { return }
        pickerPresented = false
        onImported()
    }
}
