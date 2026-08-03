import XCTest
@testable import GraphCore

/// Every blob here is assembled byte by byte by TypedstreamFixture and every string is invented.
/// No real attributedBody blob is committed, printed, or read by this suite -- a real one is
/// message content (GOAL.md constraint 3).
///
/// The decoder's whole job is to fail closed: anything it cannot read with full confidence must
/// come back nil so the caller treats the message as having no snippet. Most cases below are
/// therefore negative ones.
final class AttributedBodyDecoderTests: XCTestCase {

    // MARK: - Decodes what it should

    func testShortASCIIStringDecodes() {
        let blob = TypedstreamFixture.blob(text: "see you saturday")

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), "see you saturday")
    }

    /// The length prefix counts BYTES, not characters. An accented letter is 2 UTF-8 bytes and an
    /// emoji is 4, so a decoder that read a character count worth of bytes would return a short,
    /// truncated, mojibake-tailed string here instead of failing -- exactly the "partial string
    /// fed to the model" outcome the brief forbids. Pinning the byte/character distinction is
    /// what stops that regression from being silent.
    func testNonASCIIStringDecodesAndLengthPrefixIsAByteCountNotACharacterCount() {
        let text = "cafe\u{0301} rendezvous \u{1F600}"
        let blob = TypedstreamFixture.blob(text: text)
        XCTAssertNotEqual(
            text.utf8.count, text.count,
            "fixture must actually exercise the distinction: byte count and character count have to differ here"
        )

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), text)
    }

    func testTwoByteLengthEncodingDecodes() {
        // Over 127 bytes, so the real format would use the 0x81 escape too.
        let text = String(repeating: "long thread recap. ", count: 20)
        XCTAssertGreaterThan(text.utf8.count, 0x7F, "fixture must be long enough to need the 2-byte length path")
        let blob = TypedstreamFixture.blob(text: text)

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), text)
    }

    func testFourByteLengthEncodingDecodes() {
        // Forced rather than grown to 64KB: the point is exercising the 0x82 reader, not the size.
        let text = "forced four byte length"
        let blob = TypedstreamFixture.blob(text: text, lengthEncoding: .fourByte(UInt32(text.utf8.count)))

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), text)
    }

    func testNSMutableStringClassNameAlsoDecodes() {
        let blob = TypedstreamFixture.blob(text: "running late", stringClass: .nsMutableString)

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), "running late")
    }

    /// An explicitly empty payload is a faithful decode, so the decoder returns "" rather than
    /// nil. Whether an empty string counts as "no evidence" is SnippetReader's call, not this
    /// function's (see SnippetReaderTests).
    func testEmptyStringDecodesAsEmptyRatherThanNil() {
        let blob = TypedstreamFixture.blob(text: "")

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), "")
    }

    /// The class-version byte is deliberately not constrained to a single expected value: a
    /// different NSString version is a plausible variant and is not itself a reason to distrust
    /// the fixed marker sequence that follows it.
    func testAnUnexpectedClassVersionByteStillDecodes() {
        let blob = TypedstreamFixture.blob(text: "version tolerant", classVersion: 0x02)

        XCTAssertEqual(AttributedBodyDecoder.decodeMessageText(from: blob), "version tolerant")
    }

    // MARK: - Fails closed on everything else

    func testNotATypedstreamReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: TypedstreamFixture.notATypedstream()))
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: Data()))
    }

    /// A blob that is nothing but the signature: valid magic, but there is no stream after it.
    func testMagicOnlyBlobReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: Data(TypedstreamFixture.magic)))
    }

    func testValidTypedstreamWithNoStringClassReturnsNil() {
        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: TypedstreamFixture.blobWithNoStringClass()))
    }

    func testTruncatedInsideTheTextReturnsNil() {
        var bytes = Array(TypedstreamFixture.blob(text: "this message is cut off partway"))
        bytes.removeLast(10) // length prefix still claims the full string

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: Data(bytes)))
    }

    /// Truncated INSIDE the length field, not inside the text: the 0x81 escape says "two more
    /// bytes follow" and the blob ends instead. This is the case a bounds check written against
    /// a single index rather than "cursor plus however many bytes the length read still needs"
    /// gets wrong.
    func testTruncatedInsideTheLengthFieldReturnsNil() {
        let blob = TypedstreamFixture.blob(text: "irrelevant", lengthEncoding: .twoByte(10))
        var bytes = Array(blob)
        // Drop the payload and both length bytes, leaving the bare 0x81 marker at the very end.
        bytes.removeLast(Array("irrelevant".utf8).count + 2)
        XCTAssertEqual(bytes.last, 0x81, "fixture must end exactly on the length-escape byte")

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: Data(bytes)))
    }

    func testLengthRunningPastTheEndOfTheBlobReturnsNil() {
        // Claims a 0x7F-byte string but the blob backing it is only 5 bytes long.
        let blob = TypedstreamFixture.blob(text: "short", lengthEncoding: .singleByte(0x7F))

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: blob))
    }

    /// 0x80 is unattested in the real data (only 0x00-0x7F literal, 0x81, and 0x82 were ever
    /// observed), so its meaning is unverified. Guessing at it is exactly how a wrong length --
    /// and therefore garbage text -- would get read, so it must fail closed instead.
    func testUnknownLengthMarkerReturnsNil() {
        let blob = TypedstreamFixture.blob(text: "unknown marker", lengthEncoding: .rawMarker(0x80))

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: blob))
    }

    /// The marker sequence between the class name and the payload is matched exactly, precisely
    /// so an unrecognized variant fails instead of the decoder guessing where the length starts.
    func testUnexpectedPayloadPreambleReturnsNil() {
        let blob = TypedstreamFixture.blob(
            text: "wrong preamble",
            preambleOverride: [0x94, 0x84, 0x01, 0x2C] // 0x2C, not the 0x2B inline-data marker
        )

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: blob))
    }

    /// Bytes that are not valid UTF-8 must never come back as a lossily-decoded string.
    func testInvalidUTF8PayloadReturnsNil() {
        let blob = TypedstreamFixture.blob(payload: [0x68, 0x69, 0xFF, 0xFE, 0xFD])

        XCTAssertNil(AttributedBodyDecoder.decodeMessageText(from: blob))
    }
}
