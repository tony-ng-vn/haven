import SwiftUI

/// The other side of the card: the code somebody else points a camera at.
///
/// This used to be a screen of its own, reached from the People toolbar and
/// from the Lock Screen widget. It is the back of the card now, because the two
/// were the same object described twice -- one door rather than two, and the
/// thing you hand someone is the thing you were already looking at.
///
/// Nothing here subscribes. The handle arrives on the card the front is already
/// showing, so turning the card over cannot be a moment where the code is still
/// loading.
struct CardBack: View {
    let card: MyCard

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            // Flexible rather than fixed. At an accessibility text size the
            // lines below take the room they need and the code gives it up;
            // a fixed 260 would push the address off the bottom of the card.
            QRCodeView(text: BeaconAddress.url(for: card.username))
                .frame(maxWidth: CardBackMetrics.codeWidth)

            // A card is a fixed height, so at large text sizes there is not
            // enough of it to go round and SwiftUI's answer is to truncate.
            // Shrinking is the better failure here: a name cut to "Tony Ng..."
            // is wrong about who this is, and a half an address is the one
            // thing on this card that has to survive a code failing to scan.
            VStack(spacing: 4) {
                if let name = card.name, !name.isEmpty {
                    Text(name)
                        .personName(.card)
                        .foregroundStyle(HavenColor.ink)
                        .minimumScaleFactor(CardBackMetrics.minimumScale)
                }
                Text(BeaconAddress.display(for: card.username))
                    .havenMono()
                    .minimumScaleFactor(CardBackMetrics.minimumScale)
            }
            .multilineTextAlignment(.center)

            // The one line that goes rather than shrinks. It is a hint for the
            // first time somebody turns the card over, and at an accessibility
            // size the room it wants is room the address needs more.
            if !typeSize.isAccessibilitySize {
                Text("Show this. Their camera lands on your card.")
                    .havenSecondary()
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(CardBackMetrics.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum CardBackMetrics {
    /// Held off the card's own double rule, not off the screen.
    static let inset: CGFloat = 22

    /// A ceiling, not a size. The code takes this much when the text below is
    /// at its usual size and less when it is not.
    static let codeWidth: CGFloat = 200

    /// The margin the QR spec asks for around a code. Without it a decoder has
    /// nothing to tell the code apart from whatever it is sitting on.
    static let quietZone: CGFloat = 16

    /// How far the name and the address may shrink before they would rather
    /// wrap. Not far: this exists to stop a truncation, not to undo somebody's
    /// text size setting.
    static let minimumScale: CGFloat = 0.7
}

/// The code itself, drawn square-edged.
///
/// `.interpolation(.none)` is the whole trick: a QR scaled with smoothing turns
/// every module boundary into a gradient, and a camera then has to decide where
/// black stops. Nearest-neighbour keeps the edges where the generator put them.
private struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let code = QRCode.image(for: text) {
                Image(decorative: code, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    // The quiet zone the QR spec asks for, in the code's own
                    // light tone so the margin is part of the panel rather than
                    // a gap the night shows through.
                    .padding(CardBackMetrics.quietZone)
                    .background(HavenColor.ink, in: RoundedRectangle(cornerRadius: 16))
            } else {
                Text("The code could not be drawn.")
                    .havenSecondary()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your code")
    }
}

// MARK: - Screen brightness

extension View {
    /// Raises the screen while a code is on it, and puts it back after.
    ///
    /// A code is read off a screen by a camera, and a dim screen is the most
    /// common reason that fails.
    func brightScreen(while raised: Bool) -> some View {
        modifier(BrightScreen(raised: raised))
    }
}

/// Every way out of a raised screen, which is why this is a modifier rather
/// than a pair of calls at the two obvious moments. The card can be turned
/// back, navigated away from while still showing the code, or left behind by
/// someone who switched apps mid-scan, and all three have to put the
/// brightness back.
private struct BrightScreen: ViewModifier {
    let raised: Bool

    @HavenReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// What the screen was at before we raised it. Nil means we never raised
    /// it, so there is nothing to put back.
    @State private var previous: CGFloat?

    func body(content: Content) -> some View {
        content
            // The Lock Screen widget opens the card already turned over, so
            // this can be true on the very first frame.
            .onAppear { apply(raised) }
            .onChange(of: raised) { _, now in apply(now) }
            .onChange(of: scenePhase) { _, phase in apply(raised && phase == .active) }
            .onDisappear { apply(false) }
    }

    private func apply(_ raise: Bool) {
        if raise {
            raiseBrightness()
        } else {
            restore()
        }
    }

    /// Skipped in Low Power Mode, where someone has explicitly asked the phone
    /// to spend less, and under Reduce Motion, where a sudden jump in
    /// brightness is the kind of abrupt change that setting exists to avoid. A
    /// slightly harder scan beats overriding either of those.
    private func raiseBrightness() {
        guard previous == nil else { return }
        guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard let screen = UIApplication.shared.havenScreen else { return }
        previous = screen.brightness
        screen.brightness = 1
    }

    /// Only forgets the old brightness once it has actually been written back.
    ///
    /// The write can fail: there is no scene to write to while the app is being
    /// torn down. Clearing `previous` regardless would leave the phone at full
    /// brightness with nothing left that remembers what it was, and the next
    /// raise would then record 1 as the value to go back to. Keeping it means
    /// a later exit -- `onDisappear`, or turning the card back -- can still put
    /// it right.
    private func restore() {
        guard let previous, let screen = UIApplication.shared.havenScreen else { return }
        screen.brightness = previous
        self.previous = nil
    }
}

private extension UIApplication {
    /// The screen this app is actually on. `UIScreen.main` is deprecated and
    /// wrong the moment the app is on an external display or in a second
    /// window.
    ///
    /// Foreground-inactive counts. That is what the scene is during the exact
    /// moment this matters most: SwiftUI reports `scenePhase == .inactive` as
    /// the phone locks or Control Center opens, and a lookup that insisted on
    /// active would find nothing and leave the screen at full brightness.
    var havenScreen: UIScreen? {
        let windowScenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first { $0.activationState == .foregroundInactive }
        return foreground?.screen
    }
}

// MARK: - Previews

// Only the handle and the name, because those are the only two fields the back
// reads. A fuller card here would suggest the city or the contact rows reach it.
private let previewCard = MyCard(username: "tonybuildd", name: "Tony Nguyen")

private func previewBack(_ card: MyCard = previewCard) -> some View {
    ZStack {
        NightBackground()
        CardObject { CardBack(card: card) }
            .padding(.horizontal, CardObjectMetrics.screenInset)
    }
    .ignoresSafeArea()
}

#Preview("Card back") {
    previewBack()
}

// The size that decides whether the code or the address gets pushed off the
// card. Neither should: the code gives up room, the explainer goes, and the
// name and the address shrink rather than truncate.
//
// A long name and a long handle on purpose. "Tony Nguyen" fits at any size, so
// a preview using it would show this working when it was not.
#Preview("Card back, accessibility XXXL") {
    previewBack(MyCard(username: "mariafernandarodriguez", name: "Maria Fernanda Rodriguez"))
        .environment(\.dynamicTypeSize, .accessibility3)
}
