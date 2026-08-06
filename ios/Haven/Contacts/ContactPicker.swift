import ContactsUI
import SwiftUI

/// The classic system picker, for `.denied`/`.restricted` access.
///
/// Needs no permission at all: the system hands over only the one contact
/// somebody explicitly picks, the same way a share sheet only ever sees what
/// was explicitly shared, and Haven never learns anything about the rest of
/// the address book.
///
/// Hands back the delegate's own contact, reduced through the exact mapping
/// `LiveAddressBook` uses everywhere else (`LiveAddressBook.reduce`) -- not
/// just its identifier. `displayedPropertyKeys` is left unset above, which is
/// what makes this safe: Apple fetches every property on the contact it hands
/// the delegate when that property is left nil, the same guarantee
/// `LiveAddressBook.keysToFetch` exists to make explicit everywhere else in
/// this pipeline. That data is also the only data an import here can ever
/// have -- `ContactMatchModel.importPicked` still tries a store re-fetch by
/// identifier first, but that read is refused outright at exactly the
/// authorization levels this picker is shown for (`.denied`/`.restricted`),
/// so without the delegate's own contact there is nothing to fall back to at
/// all.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (AddressBookContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (AddressBookContact) -> Void

        init(onPick: @escaping (AddressBookContact) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(LiveAddressBook.reduce(contact))
        }
    }
}
