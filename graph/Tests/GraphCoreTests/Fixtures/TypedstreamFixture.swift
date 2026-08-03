import Foundation

/// Builds synthetic NSArchiver "typedstream" bytes shaped like a real `message.attributedBody`
/// blob, entirely programmatically -- every byte here is written by this file, never captured
/// from a real database. That is what keeps GOAL.md constraint 3 satisfiable at all: a real
/// attributedBody blob IS message content, so one could never be committed as a fixture.
///
/// The framing (class-chain preamble, then the string class, then a fixed marker sequence, then
/// a length-prefixed UTF-8 payload) mirrors the layout confirmed by structural inspection of a
/// real local database -- offsets and marker bytes only, never message text, and nothing from
/// that inspection is committed. The strings put through this builder are invented.
enum TypedstreamFixture {

    /// Which class the string payload is declared under. Real blobs observed all use NSString;
    /// NSMutableString is the plausible sibling the decoder also has to accept.
    enum StringClass {
        case nsString
        case nsMutableString

        var nameBytes: [UInt8] {
            switch self {
            case .nsString: return Array("NSString".utf8)
            case .nsMutableString: return Array("NSMutableString".utf8)
            }
        }
    }

    /// How to encode the payload length. `.natural` picks whatever encoding the real format
    /// would use for that byte count; the explicit cases force a specific path so the 2- and
    /// 4-byte readers are exercised even by a short fixture string.
    enum LengthEncoding {
        case natural
        case singleByte(UInt8)
        case twoByte(UInt16)
        case fourByte(UInt32)
        case rawMarker(UInt8)
    }

    static let magic: [UInt8] = [0x04, 0x0B] + Array("streamtyped".utf8)

    /// The class-chain preamble that precedes the string class in a real blob: an archive
    /// version field, then NSAttributedString and NSObject declarations. The decoder does not
    /// depend on these bytes being exactly this -- it searches for the string class name -- but
    /// including a realistic preamble means the fixtures exercise that search actually having to
    /// skip past other class names (none of which contain "NSString" as a substring).
    static let classChainPreamble: [UInt8] =
        [0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84, 0x12]
        + Array("NSAttributedString".utf8)
        + [0x00, 0x84, 0x84, 0x08]
        + Array("NSObject".utf8)
        + [0x00, 0x85, 0x92, 0x84, 0x84, 0x84]

    /// The fixed bytes observed between the class-version byte and the payload length. 0x2B
    /// marks "length-prefixed inline bytes follow".
    static let inlinePayloadPreamble: [UInt8] = [0x94, 0x84, 0x01, 0x2B]

    /// A well-formed blob carrying `text`.
    static func blob(
        text: String,
        stringClass: StringClass = .nsString,
        classVersion: UInt8 = 0x01,
        lengthEncoding: LengthEncoding = .natural,
        preambleOverride: [UInt8]? = nil
    ) -> Data {
        blob(
            payload: Array(text.utf8),
            stringClass: stringClass,
            classVersion: classVersion,
            lengthEncoding: lengthEncoding,
            preambleOverride: preambleOverride
        )
    }

    /// A blob carrying arbitrary payload bytes -- used for the invalid-UTF-8 case, where the
    /// payload deliberately is not a decodable string.
    static func blob(
        payload: [UInt8],
        stringClass: StringClass = .nsString,
        classVersion: UInt8 = 0x01,
        lengthEncoding: LengthEncoding = .natural,
        preambleOverride: [UInt8]? = nil
    ) -> Data {
        let className = stringClass.nameBytes
        var bytes = magic
        bytes += classChainPreamble
        bytes += [UInt8(className.count)]
        bytes += className
        bytes += [classVersion]
        bytes += preambleOverride ?? inlinePayloadPreamble
        bytes += encodedLength(lengthEncoding, naturalByteCount: payload.count)
        bytes += payload
        return Data(bytes)
    }

    /// A blob whose class chain is present and valid but which declares no string class at all --
    /// mirrors a message with no text component (a sticker or attachment-only row).
    static func blobWithNoStringClass() -> Data {
        Data(magic + classChainPreamble + [0x86, 0x86, 0x86])
    }

    /// Bytes that are not a typedstream in the first place.
    static func notATypedstream() -> Data {
        Data("this is not an archived attributed string".utf8)
    }

    private static func encodedLength(_ length: LengthEncoding, naturalByteCount: Int) -> [UInt8] {
        switch length {
        case .natural:
            if naturalByteCount < 0x80 {
                return [UInt8(naturalByteCount)]
            } else if naturalByteCount <= Int(UInt16.max) {
                return twoByteEncoding(UInt16(naturalByteCount))
            } else {
                return fourByteEncoding(UInt32(naturalByteCount))
            }
        case .singleByte(let value):
            return [value]
        case .twoByte(let value):
            return twoByteEncoding(value)
        case .fourByte(let value):
            return fourByteEncoding(value)
        case .rawMarker(let marker):
            return [marker]
        }
    }

    private static func twoByteEncoding(_ value: UInt16) -> [UInt8] {
        [0x81, UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private static func fourByteEncoding(_ value: UInt32) -> [UInt8] {
        [0x82] + (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }
    }
}
