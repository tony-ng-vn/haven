/// <reference types="vite/client" />
import { afterEach, describe, expect, test, vi } from "vitest";
import { renderConfirmation, sendWaitlistConfirmation } from "./emailClient";

describe("renderConfirmation", () => {
  test("greets the person by name in every part", () => {
    const { subject, html, text } = renderConfirmation("Ada");
    expect(subject).toBe("You're on the Haven waitlist");
    expect(html).toContain("Ada, you're on the list.");
    expect(text).toContain("Ada,");
  });

  test("escapes HTML in the name so a crafted name cannot inject markup", () => {
    const { html } = renderConfirmation('<script>alert("x")</script>');
    // The raw tag must never reach the HTML body...
    expect(html).not.toContain("<script>");
    // ...it lands as escaped entities instead.
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("&quot;");
  });

  test("escapes an ampersand so the name renders as typed", () => {
    const { html } = renderConfirmation("Tom & Jerry");
    expect(html).toContain("Tom &amp; Jerry");
    expect(html).not.toContain("Tom & Jerry");
  });

  test("leaves the plain-text part unescaped", () => {
    // Text has no markup to break out of, so entities would be noise there.
    const { text } = renderConfirmation("Tom & Jerry");
    expect(text).toContain("Tom & Jerry,");
  });
});

describe("sendWaitlistConfirmation", () => {
  const original = {
    key: process.env.RESEND_API_KEY,
    from: process.env.WAITLIST_FROM_EMAIL,
  };

  afterEach(() => {
    vi.unstubAllGlobals();
    if (original.key === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = original.key;
    if (original.from === undefined) delete process.env.WAITLIST_FROM_EMAIL;
    else process.env.WAITLIST_FROM_EMAIL = original.from;
  });

  test("skips (never sends, never throws) when credentials are unset", async () => {
    delete process.env.RESEND_API_KEY;
    delete process.env.WAITLIST_FROM_EMAIL;
    const fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);

    const result = await sendWaitlistConfirmation({
      to: "a@b.com",
      name: "Ada",
    });

    expect(result.status).toBe("skipped");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("posts to Resend and reports sent once both credentials are set", async () => {
    process.env.RESEND_API_KEY = "re_test_key";
    process.env.WAITLIST_FROM_EMAIL = "Haven <hello@inhavens.com>";
    // Typed params so mock.calls[0] is [string, RequestInit], not [] -- the
    // Convex deploy typechecks this file and rejects a cast from an empty tuple.
    const fetchSpy = vi.fn((_url: string, _init: RequestInit) =>
      Promise.resolve(Response.json({ id: "email_123" })),
    );
    vi.stubGlobal("fetch", fetchSpy);

    const result = await sendWaitlistConfirmation({
      to: "a@b.com",
      name: "Ada",
    });

    expect(result).toEqual({ status: "sent", id: "email_123" });
    expect(fetchSpy).toHaveBeenCalledOnce();
    const [url, init] = fetchSpy.mock.calls[0];
    expect(url).toBe("https://api.resend.com/emails");
    const body = JSON.parse(init.body as string);
    expect(body.from).toBe("Haven <hello@inhavens.com>");
    expect(body.to).toBe("a@b.com");
    expect(body.subject).toBe("You're on the Haven waitlist");
  });

  test("reports failed (not thrown) when Resend rejects the request", async () => {
    process.env.RESEND_API_KEY = "re_test_key";
    process.env.WAITLIST_FROM_EMAIL = "hello@inhavens.com";
    vi.stubGlobal(
      "fetch",
      async () => new Response("domain not verified", { status: 403 }),
    );

    const result = await sendWaitlistConfirmation({
      to: "a@b.com",
      name: "Ada",
    });

    expect(result.status).toBe("failed");
  });
});
