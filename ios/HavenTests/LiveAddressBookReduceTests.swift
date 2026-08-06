import Contacts
import Testing
@testable import Haven

/// `LiveAddressBook.reduce` is the one mapping `ContactPicker`'s delegate now
/// relies on directly (see I3): the picker hands over a `CNContact` under
/// authorization levels where `CNContactStore` itself refuses every read, so
/// this mapping -- not a store re-fetch -- is what an import from the classic
/// picker is actually built from. `CNMutableContact` needs no store, no
/// permission and no device to construct, which is what makes this testable
/// as a delegate-style contact at all.
@Suite("Reducing a CNContact the way the picker's delegate hands one over")
struct LiveAddressBookReduceTests {
    @Test("a personal name joins given and family, plainly")
    func personalName() {
        let contact = CNMutableContact()
        contact.givenName = "Mai"
        contact.familyName = "Tran"
        contact.phoneNumbers = [CNLabeledValue(label: nil, value: CNPhoneNumber(stringValue: "+84901234567"))]

        let reduced = LiveAddressBook.reduce(contact)

        #expect(reduced.id == contact.identifier)
        #expect(reduced.name == "Mai Tran")
        #expect(reduced.phones == ["+84901234567"])
        #expect(reduced.emails.isEmpty)
    }

    @Test("no personal name falls back to the organization")
    func organizationFallback() {
        let contact = CNMutableContact()
        contact.organizationName = "Analytical Engines"
        contact.emailAddresses = [CNLabeledValue(label: nil, value: "ada@example.com" as NSString)]

        let reduced = LiveAddressBook.reduce(contact)

        #expect(reduced.name == "Analytical Engines")
        #expect(reduced.emails == ["ada@example.com"])
    }

    @Test("every phone and email on the card is kept, in order")
    func multipleHandles() {
        let contact = CNMutableContact()
        contact.givenName = "Mai"
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: "+84901234567")),
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+84907654321")),
        ]
        contact.emailAddresses = [
            CNLabeledValue(label: CNLabelHome, value: "mai@example.com" as NSString),
        ]

        let reduced = LiveAddressBook.reduce(contact)

        #expect(reduced.phones == ["+84901234567", "+84907654321"])
        #expect(reduced.emails == ["mai@example.com"])
    }

    @Test("neither a name nor an organization is a blank name, not a crash")
    func noNameAtAll() {
        let contact = CNMutableContact()
        contact.phoneNumbers = [CNLabeledValue(label: nil, value: CNPhoneNumber(stringValue: "+84901234567"))]

        let reduced = LiveAddressBook.reduce(contact)

        #expect(reduced.name.isEmpty)
    }
}
