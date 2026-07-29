// Where Haven's sign-in lives, told to Clerk explicitly.
//
// This exists because of a production-only redirect loop. A Clerk production
// instance has an Account Portal at accounts.<domain>, and its environment
// advertises that portal as the instance's sign-in url:
//
//     sign_in_url = https://accounts.inhavens.com/sign-in
//
// Mount <SignIn/> with no routing props and Clerk consults that value, decides
// sign-in lives somewhere else, and navigates there. The portal honours its
// redirect_url and sends the person back to inhavens.com, which mounts <SignIn/>
// again. Round and round, with nothing on screen but the "Signing in" fallback.
//
// None of it reproduces on a development instance, because development
// instances have no Account Portal -- so this was invisible until the day the
// production key shipped, which is exactly the day it was found.
//
// Two things break the loop, and both are here rather than one:
//
//   1. signInUrl / signUpUrl override the instance's values, so every redirect
//      Clerk initiates lands back in Haven instead of on the portal.
//   2. routing: "hash" keeps the component's own steps in the fragment and
//      stops it navigating anywhere at all.
//
// Either alone should be enough. Both, because this failure is only observable
// against a production instance, which means CI cannot see it and neither can
// the simulator -- so the belt and the braces are both cheap next to finding
// out again from a person who cannot sign in.
//
// The paths are real routes: `resolveView` sends /sign-in, /sign-up and their
// sub-paths to the sign-in view, and every one of those words is reserved in
// handleNames so none can ever be somebody's card.

export const CLERK_SIGN_IN_URL = "/sign-in";
export const CLERK_SIGN_UP_URL = "/sign-up";

/// Props for `<ClerkProvider>`, kept out of `main.tsx` so they can be asserted.
export const clerkUrlProps = {
  signInUrl: CLERK_SIGN_IN_URL,
  signUpUrl: CLERK_SIGN_UP_URL,
} as const;

/// How the prebuilt `<SignIn/>` and `<SignUp/>` components navigate.
///
/// "hash" rather than "path" because Haven is hash-routed already: the app
/// reads `#/sso-callback` and friends through `isClerkFlowHash`, so Clerk's own
/// steps land on the sign-in view without any extra route handling.
export const CLERK_ROUTING = "hash" as const;
