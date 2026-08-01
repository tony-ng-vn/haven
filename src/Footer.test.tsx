// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { Footer } from "./Footer";

afterEach(cleanup);

// Shared by the landing page, Your Sky, and the iOS page -- pure markup, no
// session and no backend, the same reasoning as TopNav.test.tsx.
describe("the compliance footer", () => {
  test("links to the existing privacy, terms, and support documents", () => {
    const { container } = render(<Footer />);
    const hrefs = Array.from(container.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toEqual(["/privacy", "/terms", "/support"]);
  });

  test("carries a plain copyright line and no authored legal text", () => {
    const { getByText } = render(<Footer />);
    expect(getByText("(c) 2026 Haven")).toBeTruthy();
  });
});
