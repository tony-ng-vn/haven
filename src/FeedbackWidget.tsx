import { useEffect } from "react";

// The widget is a browser custom element that touches HTMLElement at import
// time, so the definition must load client-side only. A top-level import would
// crash any SSR pass; a dynamic import inside an effect never runs on the server.
// Endpoint/token come from build-time env; the public submit token is safe to ship.
const endpoint = import.meta.env.VITE_FEEDBACK_ENDPOINT as string | undefined;
const token = import.meta.env.VITE_FEEDBACK_TOKEN as string | undefined;

export function FeedbackWidget() {
  useEffect(() => {
    if (!endpoint || !token) return;
    void import("feedback-sdk-widget");
  }, []);

  if (!endpoint || !token) return null;
  return <feedback-widget endpoint={endpoint} token={token} />;
}
