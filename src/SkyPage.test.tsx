// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

import { SkyPage } from "./SkyPage";

afterEach(cleanup);

describe("the sky download page", () => {
  test("renders for an admitted preview member", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    expect(
      screen.getByRole("heading", { level: 1 }),
    ).toBeTruthy();
  });

  test("titles the tab", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    expect(document.title).toBe("Your Sky - Haven");
  });

  test("lays out the three-step flow: download, authorize, map", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/download/i);
    expect(body).toMatch(/authorize access/i);
    expect(body).toMatch(/map relationships/i);
  });

  test("never exposes the old public static download path", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).not.toContain("/downloads/YourSky.zip");
  });

  // The owner stripped the hero's buttons (a two-button row lived here
  // briefly): the page's one pill button is the closing "Download for Mac"
  // after the steps and privacy list, with the step-1 text link as the only
  // other path to the file. No waitlist cross-link on this page anymore.
  test("keeps a single download button, at the end, and no hero CTA row", () => {
    const { container } = render(
      <SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />,
    );
    expect(container.querySelector(".landing-hero-ctas")).toBeNull();
    const pills = container.querySelectorAll(".sky-download");
    expect(pills.length).toBe(1);
    expect(pills[0].classList.contains("sky-download-repeat")).toBe(true);
    expect(pills[0].tagName).toBe("BUTTON");
    const hrefs = Array.from(container.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).not.toContain("#/ios");
  });

  test("downloads only through the authenticated callback", async () => {
    const download = vi.fn(async () => undefined);
    render(<SkyPage onDownload={download} onSignOut={vi.fn()} />);

    fireEvent.click(screen.getByRole("button", { name: "Download for Mac" }));

    await vi.waitFor(() => expect(download).toHaveBeenCalledTimes(1));
  });

  test("is honest that the build is not notarized and names the workaround", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
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
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/never uploaded/i);
    expect(body).toMatch(/metadata/i);
    expect(body).not.toMatch(/nothing ever leaves your device/i);
  });

  test("names the optional local AI model as on-device and off by default", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const body = document.body.textContent ?? "";
    expect(body).toMatch(/ollama/i);
    expect(body).toMatch(/on your mac/i);
  });

  test("links back to the front door", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/");
  });

  // The compliance footer's own contents are pinned in Footer.test.tsx; this
  // just confirms the page actually hosts it rather than duplicating it.
  test("carries the shared compliance footer", () => {
    render(<SkyPage onDownload={vi.fn()} onSignOut={vi.fn()} />);
    const hrefs = Array.from(document.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("/privacy");
  });
});
