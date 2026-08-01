// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

import { SkyDemoEmbed } from "./SkyDemoEmbed";

const originalInnerWidth = window.innerWidth;

afterEach(() => {
  cleanup();
  window.innerWidth = originalInnerWidth;
});

describe("the sample sky demo embed", () => {
  test("on a wide viewport, a click swaps the teaser for an iframe", () => {
    window.innerWidth = 1200;
    render(<SkyDemoEmbed />);
    expect(document.querySelector("iframe")).toBeNull();
    fireEvent.click(screen.getByText("Explore a sample sky"));
    const frame = document.querySelector("iframe");
    expect(frame?.getAttribute("src")).toBe("/demo-sky.html");
  });

  test("on a wide viewport, the teaser is a real button (keyboard operable)", () => {
    window.innerWidth = 1200;
    render(<SkyDemoEmbed />);
    const button = screen.getByRole("button", {
      name: /explore a sample sky/i,
    });
    expect(button.tagName).toBe("BUTTON");
  });

  // A pan-zoom canvas has little room in a small inline frame and fights the
  // page's own scroll, so a narrow viewport gets a direct link that opens the
  // demo in its own tab instead of an inline swap.
  test("on a narrow viewport, opens in a new tab instead of an inline frame", () => {
    window.innerWidth = 375;
    render(<SkyDemoEmbed />);
    expect(document.querySelector("iframe")).toBeNull();
    const link = screen.getByRole("link", { name: /explore a sample sky/i });
    expect(link.getAttribute("href")).toBe("/demo-sky.html");
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")).toContain("noopener");
  });

  test("always captions the sample as invented people", () => {
    render(<SkyDemoEmbed />);
    expect(screen.getByText("A sample sky, invented people.")).toBeTruthy();
  });
});
