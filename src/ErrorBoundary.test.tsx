// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { ErrorBoundary } from "./ErrorBoundary";

afterEach(cleanup);

// A child that throws on render until told to stop -- the exact situation an
// error boundary exists for. React logs the caught error to console.error;
// silence it so a passing test stays quiet.
function Bomb({ explode }: { explode: boolean }) {
  if (explode) throw new Error("boom");
  return <p>Recovered content</p>;
}

describe("ErrorBoundary", () => {
  test("renders its children when nothing throws", () => {
    render(
      <ErrorBoundary>
        <p>All good</p>
      </ErrorBoundary>,
    );
    expect(screen.getByText("All good")).toBeTruthy();
  });

  test("catches a render error and shows the fallback instead of unmounting", () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    render(
      <ErrorBoundary>
        <Bomb explode={true} />
      </ErrorBoundary>,
    );
    // The fallback stands in for the crashed tree -- no white screen.
    expect(screen.getByRole("alert")).toBeTruthy();
    expect(screen.getByText(/sneaky sneaky/i)).toBeTruthy();
    // The child that threw is gone, not rendered half-broken.
    expect(screen.queryByText("Recovered content")).toBeNull();
    consoleError.mockRestore();
  });

  test("retry clears the error so a recovered child renders again", () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});

    // A parent whose child stops throwing after the user acts, so pressing
    // "Try again" lands on a tree that now renders cleanly.
    function Harness() {
      const [explode, setExplode] = useState(true);
      return (
        <>
          <button type="button" onClick={() => setExplode(false)}>
            defuse
          </button>
          <ErrorBoundary>
            <Bomb explode={explode} />
          </ErrorBoundary>
        </>
      );
    }

    render(<Harness />);
    expect(screen.getByRole("alert")).toBeTruthy();

    // Stop the child from throwing, then ask the boundary to re-render.
    fireEvent.click(screen.getByText("defuse"));
    fireEvent.click(screen.getByRole("button", { name: /try again/i }));

    expect(screen.getByText("Recovered content")).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
    consoleError.mockRestore();
  });
});
