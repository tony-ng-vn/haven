import { useEffect } from "react";
import { useIsAdmin } from "./useIsAdmin";

// The widget is a browser custom element that touches HTMLElement at import
// time, so the definition must load client-side only. A top-level import would
// crash any SSR pass; a dynamic import inside an effect never runs on the server.
// Endpoint/token come from build-time env; the public submit token is safe to ship.
const endpoint = import.meta.env.VITE_FEEDBACK_ENDPOINT as string | undefined;
const token = import.meta.env.VITE_FEEDBACK_TOKEN as string | undefined;

// The feedback button is an admin-only surface for now: only allowlisted admins
// see it, so the rest of Haven stays clean while we dogfood feedback ourselves.
export function FeedbackWidget() {
  const isAdmin = useIsAdmin();
  const active = isAdmin && Boolean(endpoint) && Boolean(token);

  useEffect(() => {
    if (!active) return;
    void import("feedback-sdk-widget");
  }, [active]);

  if (!active) return null;
  // feedback-fab lifts the button above the Meet FAB, which shares the same
  // bottom-right corner (see index.css).
  return (
    <feedback-widget className="feedback-fab" endpoint={endpoint} token={token} />
  );
}
