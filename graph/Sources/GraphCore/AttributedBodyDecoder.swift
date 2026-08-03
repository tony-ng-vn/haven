import Foundation

/// Decodes the plain message string out of a `message.attributedBody` BLOB.
///
/// Messages stores this column as an archived NSAttributedString in Apple's OLD "typedstream"
/// format (NSArchiver) -- NOT a modern keyed archive. NSKeyedUnarchiver cannot read it, and
/// NSUnarchiver is not available from Swift, so this is a small, purpose-built reader rather
/// than a general typedstream implementation: it locates the top-level NSString/NSMutableString
/// payload (the message's full text, confirmed by structural inspection of a real local
/// database to appear before any attribute-run metadata) and returns exactly that. It never
/// attempts to reconstruct attribute runs, formatting, links, mentions, or attachments -- the
/// plain string is all the caller wants (SnippetReader, building a model prompt).
///
/// Fails closed on everything it cannot read with full confidence: a malformed, truncated, or
/// unrecognized-variant blob returns nil rather than a crash or a partial/garbage string. Never
/// touched by anything outside GraphCore -- see SnippetReader, the only caller.
public enum AttributedBodyDecoder {
    // "\x04\x0Bstreamtyped": NSArchiver's fixed typedstream signature, present at the start of
    // every attributedBody blob observed. Anything else at this position is not a typedstream
    // this decoder understands.
    private static let magic: [UInt8] = [0x04, 0x0B] + Array("streamtyped".utf8)

    private static let nsMutableStringMarker = Array("NSMutableString".utf8)
    private static let nsStringMarker = Array("NSString".utf8)

    // Observed immediately after the string class's name and a single class-version byte, in
    // every real sample regardless of message length or content: the class-version byte itself
    // is deliberately not matched here (see the decoder's own doc comment), only this fixed
    // marker sequence, ending in 0x2B ("length-prefixed inline bytes follow").
    private static let inlinePayloadPreamble: [UInt8] = [0x94, 0x84, 0x01, 0x2B]

    public static func decodeMessageText(from data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > magic.count, Array(bytes[0..<magic.count]) == magic else {
            return nil // not a typedstream blob at all
        }

        guard let classNameEnd = firstEndIndex(ofAnyOf: [nsMutableStringMarker, nsStringMarker], in: bytes) else {
            return nil // no NSString/NSMutableString found -- e.g. a non-text message
        }

        // Skip exactly one class-version byte, then require the fixed preamble immediately
        // after it. Bounded, not a blob-wide search: this only ever looks at the few bytes
        // right after the class name, so it cannot accidentally match an unrelated 0x2B deep in
        // later attribute-dictionary data.
        let versionByteIndex = classNameEnd
        let preambleStart = versionByteIndex + 1
        let preambleEnd = preambleStart + inlinePayloadPreamble.count
        guard versionByteIndex < bytes.count,
              preambleEnd <= bytes.count,
              Array(bytes[preambleStart..<preambleEnd]) == inlinePayloadPreamble else {
            return nil
        }

        var cursor = preambleEnd
        guard let length = readLength(bytes: bytes, cursor: &cursor) else {
            return nil
        }
        guard cursor + length <= bytes.count else {
            return nil // truncated blob
        }
        guard length > 0 else {
            return "" // a valid, explicitly empty string
        }

        let textBytes = bytes[cursor..<(cursor + length)]
        guard let text = String(bytes: textBytes, encoding: .utf8) else {
            return nil // not valid UTF-8 -- never surface a partial/garbage string
        }
        return text
    }

    /// Typedstream's small-integer length encoding: a literal byte for 0-127, or an escape byte
    /// (0x81/0x82) signalling a little-endian 2- or 4-byte length follows. Any other leading
    /// byte is an unrecognized, unattested variant, handled defensively by returning nil rather
    /// than guessed at.
    private static func readLength(bytes: [UInt8], cursor: inout Int) -> Int? {
        guard cursor < bytes.count else { return nil }
        let marker = bytes[cursor]
        switch marker {
        case 0..<0x80:
            cursor += 1
            return Int(marker)
        case 0x81:
            guard cursor + 2 < bytes.count else { return nil }
            let value = UInt16(bytes[cursor + 1]) | (UInt16(bytes[cursor + 2]) << 8)
            cursor += 3
            return Int(value)
        case 0x82:
            guard cursor + 4 < bytes.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 {
                value |= UInt32(bytes[cursor + 1 + i]) << (8 * i)
            }
            cursor += 5
            return Int(value)
        default:
            return nil
        }
    }

    /// The index just past the first occurrence of whichever pattern in `patterns` appears
    /// earliest in `bytes`, or nil if none appear at all.
    private static func firstEndIndex(ofAnyOf patterns: [[UInt8]], in bytes: [UInt8]) -> Int? {
        var bestRange: Range<Int>?
        for pattern in patterns {
            guard let range = firstRange(of: pattern, in: bytes) else { continue }
            if bestRange == nil || range.lowerBound < bestRange!.lowerBound {
                bestRange = range
            }
        }
        return bestRange?.upperBound
    }

    private static func firstRange(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        let lastStart = bytes.count - pattern.count
        guard lastStart >= 0 else { return nil }
        for start in 0...lastStart {
            if Array(bytes[start..<(start + pattern.count)]) == pattern {
                return start..<(start + pattern.count)
            }
        }
        return nil
    }
}
