import { useUser } from "@clerk/react";
import { isAdminEmail, parseAdminEmails } from "./lib";

// Resolved once at module load: import.meta.env is inlined at build time, so
// the allowlist never changes during a session.
const ADMIN_EMAILS = parseAdminEmails(
  import.meta.env.VITE_ADMIN_EMAILS as string | undefined,
);

// Whether the signed-in Clerk user is a Haven admin. Returns false while Clerk
// is still loading and for every signed-out or non-allowlisted visitor, so
// admin-only surfaces stay hidden by default. This is a UX gate, not a security
// boundary: any privileged action must be re-checked on the server.
export function useIsAdmin(): boolean {
  const { user } = useUser();
  return isAdminEmail(user?.primaryEmailAddress?.emailAddress, ADMIN_EMAILS);
}
