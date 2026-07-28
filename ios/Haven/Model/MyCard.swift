import Foundation

/// The caller's own card, as `profiles:getMyCard` and `profiles:updateMyProfile`
/// both return it. Convex also sends `_id`, `_creationTime` and `updatedAt`;
/// nothing in the app has a use for any of them, and an unknown key is ignored.
struct MyCard: Decodable, Equatable {
    let username: String
    var name: String?
    var photoStorageId: String?
    /// Where the photo actually is. The server resolves it, because a storage
    /// id is not something a client can fetch. Absent on a card built in a test
    /// or a preview, which is the same as having no photo.
    var photoUrl: String?
    var city: City?
    var handles: [Handle]?
    var primaryPlatform: Platform?
    var company: String?
    var role: String?

    struct City: Decodable, Equatable {
        let name: String
        var admin: String?
        var country: String?
    }

    struct Handle: Decodable, Equatable {
        let platform: Platform
        let value: String
        let verified: Bool
    }

    /// Mirrors `platformValidator` in `convex/profileFields.ts`. Email is absent
    /// on purpose: it was cut as a platform and nothing reintroduces it.
    enum Platform: String, Decodable, Equatable {
        case instagram, x, linkedin, phone
    }
}

extension MyCard.Platform: Identifiable {
    public var id: String { rawValue }

    /// What the platform is called in the interface.
    ///
    /// Text rather than a mark: the brand glyphs are third-party trademarks
    /// with their own usage rules, and picking them is its own piece of work.
    var label: String {
        switch self {
        case .instagram: return "Instagram"
        case .x: return "X"
        case .linkedin: return "LinkedIn"
        case .phone: return "Phone"
        }
    }
}

extension MyCard.Platform {
    /// What sits in front of a stored value to make the address it points at.
    ///
    /// Phone has none, because a number is not an address.
    var addressPrefix: String {
        switch self {
        case .instagram: return "instagram.com/"
        case .x: return "x.com/"
        case .linkedin: return "linkedin.com/in/"
        case .phone: return ""
        }
    }

}

extension MyCard.Handle {
    /// How a card shows this handle: the address it points at, or the number
    /// itself for phone.
    ///
    /// The same shape for every platform on purpose. "@mayachen" is how people
    /// write a handle, but it reads identically for X and for Instagram, and
    /// the card has no brand glyph to tell them apart -- the marks are
    /// third-party trademarks with their own usage rules. An address says which
    /// platform it is by being one.
    var display: String {
        platform.addressPrefix + value
    }
}

extension MyCard.City {
    /// The city as one line: "Austin, TX, United States", or just the parts
    /// there are. A blank part is dropped rather than shown as a stray comma --
    /// MapKit hands back an empty admin area for countries that have no states.
    var line: String {
        [name, admin, country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension MyCard {
    /// The photo, ready to hand to a loader. Nil covers both "no photo" and a
    /// url the server sent that does not parse, because the card shows the same
    /// thing either way.
    var photoURL: URL? {
        photoUrl.flatMap(URL.init(string:))
    }

    /// Whether there is a photo at all.
    ///
    /// The stored id decides this, not the url: the id is what the row, the
    /// star and the remove option all key off, and a url that failed to resolve
    /// does not mean the photo is gone.
    var hasPhoto: Bool {
        photoStorageId != nil
    }

    /// Which figure stars this card has earned. The slot mapping is fixed in
    /// `StarSlot`, so a field always lights the same star.
    var filledSlots: Set<StarSlot> {
        var slots: Set<StarSlot> = []
        if name?.isEmpty == false { slots.insert(.name) }
        if city != nil { slots.insert(.city) }
        if handles?.isEmpty == false { slots.insert(.primaryContact) }
        if hasPhoto { slots.insert(.photo) }
        if company?.isEmpty == false { slots.insert(.company) }
        if role?.isEmpty == false { slots.insert(.role) }
        return slots
    }

    /// The one way to be reached that a card leads with.
    ///
    /// `primaryPlatform` is the choice the person made. A card that carries
    /// handles but no choice still falls back to the first one, because a card
    /// showing no way to reach someone who gave one is worse than a card
    /// picking for them.
    var primaryHandle: Handle? {
        guard let handles else { return nil }
        if let primaryPlatform,
           let chosen = handles.first(where: { $0.platform == primaryPlatform }) {
            return chosen
        }
        return handles.first
    }
}
