import SwiftUI

/// Which side of the card is facing you, as a function of how far it has
/// turned.
///
/// SwiftUI has no backface culling. A view turned past 90 degrees keeps
/// drawing, mirrored, and keeps taking taps and reading aloud, so without a
/// rule the front prints through the back and VoiceOver reads both sides of
/// the card at once. This is that rule, kept pure so it can be pinned by
/// `CardFlipTests` rather than judged by watching a card spin.
enum CardFlip {
    /// A half turn: the back, face on.
    static let backAngle: Double = 180

    /// How much the turn foreshortens.
    ///
    /// Well under SwiftUI's default of 1, which throws the near edge of a card
    /// this size most of the way across the screen. Enough to say the card has
    /// a thickness and is turning in space, not enough to look like a camera
    /// trick.
    static let perspective: CGFloat = 0.4

    /// Whether the back is the side you are looking at.
    ///
    /// Exactly at the halfway point the card is edge-on and has no area to
    /// show, so that is the only place the swap is invisible.
    static func showsBack(angle: Double) -> Bool {
        angle >= backAngle / 2
    }

    /// How far a given face has turned.
    ///
    /// The back is drawn already reversed, so the container's half turn brings
    /// it to a whole one. A whole turn is the identity, which is what keeps the
    /// back's gradients and its rules painting the way they were authored
    /// instead of mirrored.
    static func faceAngle(_ angle: Double, isBack: Bool) -> Double {
        isBack ? angle + backAngle : angle
    }

    /// How opaque a face is at this angle.
    ///
    /// A hard step, never a fade. Two opaque cards stacked do not dissolve into
    /// each other -- they composite, so at half opacity each you see both, and
    /// the name on the front prints straight through the code on the back.
    static func opacity(angle: Double, isBack: Bool) -> Double {
        showsBack(angle: angle) == isBack ? 1 : 0
    }
}

/// A card you can turn over: two faces, one of which is facing you.
///
/// Generic over both faces and ignorant of what is printed on either. The
/// reveal deliberately does not use this -- it shows a bare `CardObject`,
/// because that screen is a paced moment ending in one button and a card that
/// invites a tap would compete with it.
struct TwoSidedCard<Front: View, Back: View>: View {
    @Binding var showingBack: Bool
    @ViewBuilder var front: () -> Front
    @ViewBuilder var back: () -> Back

    private var angle: Double { showingBack ? CardFlip.backAngle : 0 }

    var body: some View {
        ZStack {
            front().modifier(CardFace(angle: angle, isBack: false))
            back().modifier(CardFace(angle: angle, isBack: true))
        }
        // Under Reduce Motion the card is simply already turned over: the flip
        // stays reachable, which is the part that matters, and only the turn
        // goes. A cross fade is not the alternative -- two opaque cards do not
        // dissolve, they print through each other.
        .havenAnimation(HavenMotion.cardFlip, value: showingBack)
        .contentShape(Rectangle())
        .onTapGesture { showingBack.toggle() }
        // Light. Turning a card over is a small physical act, not a commit.
        .sensoryFeedback(.impact(weight: .light), trigger: showingBack)
        // The faces keep their own elements -- the name and city still read as
        // themselves -- and the turn is offered as an action on the container.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: showingBack ? "Show your card" : "Show your code") {
            showingBack.toggle()
        }
    }
}

/// One face of the card: turned, and culled when it is not the one facing you.
///
/// `Animatable` on the angle is what makes the cull exact. The opacity is then
/// read off the interpolated angle every frame, so the faces swap precisely as
/// the card goes edge-on. Driving it off the boolean instead would animate the
/// opacity too, and the two faces would dissolve through each other across the
/// whole turn.
private struct CardFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        // Culled three ways, because invisible is only one of them: a face at
        // zero opacity still takes the taps meant for the other side, and
        // VoiceOver still reads it.
        let facing = CardFlip.showsBack(angle: angle) == isBack
        return content
            .opacity(CardFlip.opacity(angle: angle, isBack: isBack))
            .allowsHitTesting(facing)
            .accessibilityHidden(!facing)
            .rotation3DEffect(
                .degrees(CardFlip.faceAngle(angle, isBack: isBack)),
                axis: (x: 0, y: 1, z: 0),
                perspective: CardFlip.perspective
            )
    }
}
