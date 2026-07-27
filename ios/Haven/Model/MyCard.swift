import Foundation

/// The caller's own card, as `profiles:getMyCard` and `profiles:updateMyProfile`
/// both return it. Convex also sends `_id`, `_creationTime` and `updatedAt`;
/// nothing in the app has a use for any of them, and an unknown key is ignored.
struct MyCard: Decodable, Equatable {
    let username: String
    var name: String?
    var photoStorageId: String?
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

extension MyCard.Platform {
    /// What sits in front of a stored value to make the address it points at.
    ///
    /// Phone has none, because a number is not an address. The onboarding
    /// contact screen keeps its own copy of these: it is parsing what someone
    /// pasted, which is a different job from showing what was stored.
    var addressPrefix: String {
        switch self {
        case .instagram: return "instagram.com/"
        case .x: return "x.com/"
        case .linkedin: return "linkedin.com/in/"
        case .phone: return ""
        }
    }

    /// The stored value as a card shows it.
    ///
    /// Instagram and X are read as handles, so they take the `@` their own
    /// products put in front of one. A LinkedIn slug means nothing on its own,
    /// so it shows as the address instead. A phone number is already itself.
    func display(_ value: String) -> String {
        switch self {
        case .instagram, .x: return "@\(value)"
        case .linkedin: return addressPrefix + value
        case .phone: return value
        }
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
    /// Which figure stars this card has earned. The slot mapping is fixed in
    /// `StarSlot`, so a field always lights the same star.
    var filledSlots: Set<StarSlot> {
        var slots: Set<StarSlot> = []
        if name?.isEmpty == false { slots.insert(.name) }
        if city != nil { slots.insert(.city) }
        if handles?.isEmpty == false { slots.insert(.primaryContact) }
        if photoStorageId != nil { slots.insert(.photo) }
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
