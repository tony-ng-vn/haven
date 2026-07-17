// Clerk's prebuilt sign-in modal renders in Clerk's own component tree, not
// ours, so it cannot pick up index.css directly. Point it at the same
// Quiet Room CSS variables (see index.css) so the modal reads as part of
// the app rather than a bolted-on third-party widget.
export const clerkAppearance = {
  variables: {
    colorPrimary: "var(--accent-fill)",
    colorDanger: "var(--danger)",
    colorBackground: "var(--surface)",
    colorText: "var(--text)",
    colorTextSecondary: "var(--muted)",
    colorInputBackground: "var(--field-bg)",
    colorInputText: "var(--text)",
    borderRadius: "var(--radius)",
    fontFamily: "inherit",
  },
};
