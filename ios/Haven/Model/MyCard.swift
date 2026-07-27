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
}
