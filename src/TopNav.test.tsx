// @vitest-environment happy-dom
import { afterEach, describe, expect, test } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { TopNav } from "./TopNav";

afterEach(cleanup);

// Shared by the landing hero, Your Sky, and the iOS page -- pure markup, no
// session and no backend, the same reasoning as SkyPage.test.tsx.
describe("the shared top nav", () => {
  test("wordmark links home, and all three links go where they say", () => {
    const { container } = render(<TopNav />);
    const links = Array.from(container.querySelectorAll("a")).map((a) => [
      a.textContent,
      a.getAttribute("href"),
    ]);
    expect(links).toContainEqual(["Haven", "/"]);
    expect(links).toContainEqual(["Your Sky", "#/sky"]);
    expect(links).toContainEqual(["iPhone", "#/ios"]);
    expect(links).toContainEqual(["Sign in", "#/sign-in"]);
  });
});
