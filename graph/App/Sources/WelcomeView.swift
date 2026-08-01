import SwiftUI

/// Onboarding step 1: first thing a first-time user ever sees. Same visual language as
/// PermissionView (black background, centered VStack, title2 bold, secondary body text) so
/// the whole onboarding flow reads as one screen sequence, not three different apps.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Your Sky")
                .font(.title2)
                .bold()

            Text(
                "Your Sky reads your own Messages and Contacts, entirely on this Mac, "
                    + "and turns years of conversations into a living map of everyone you "
                    + "know -- who you talk to, which group chats you share, and how close "
                    + "you really are. Nothing you say ever leaves this computer."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 460)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
