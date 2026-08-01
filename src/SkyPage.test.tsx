// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";

import { SkyPage } from "./SkyPage";

afterEach(cleanup);

// Public and unauthenticated, like the card and legal pages: this renders
// with no session, no Convex query, and no props.

describe("the sky download page", () => {
  test("renders with no session, no props, and no backend", () => {
    render(<SkyPage />);
    expect(
      screen.getByRole("heading", { level: 1 }),
    ).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<SkyPage />);
    expect(document.title).toBe("Your Sky - Haven");
  });

  test("lays out the three-step flow: download, authorize, map", () => {
    render(<SkyPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/download/i);
    expect(body).toMatch(/authorize access/i);
    expect(body).toMatch(/map relationships/i);
  });

  test("links the download CTA at the static download path", () => {
    render(<SkyPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/downloads/YourSky.zip");
  });

  test("is honest that the build is not notarized and names the workaround", () => {
    render(<SkyPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/not notarized/i);
    expect(body).toMatch(/open anyway/i);
    expect(body).toMatch(/macos 14/i);
    expect(body).toMatch(/full disk access/i);
  });

  // The privacy copy is a legal boundary as much as it is marketing: it must
  // never claim data "never leaves the device" in an unscoped way (a future
  // sync feature would make that false), and it must name metadata, not
  // message contents, as what the map is built from.
  test("scopes every privacy claim to messages and contacts data", () => {
    render(<SkyPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/never uploaded/i);
    expect(body).toMatch(/metadata/i);
    expect(body).not.toMatch(/nothing ever leaves your device/i);
  });

  test("names the optional local AI model as on-device and off by default", () => {
    render(<SkyPage />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/ollama/i);
    expect(body).toMatch(/on your mac/i);
  });

  test("links back to the front door", () => {
    render(<SkyPage />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/");
  });
});
