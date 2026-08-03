// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

// The mutation is stood in for so submitting is a pure client-side check: what
// args reach the backend, and what the returned status renders as. Mirrors the
// useMutation stub in SearchAdd.test.tsx.
const submitted = vi.hoisted(() => ({
  args: null as unknown,
  result: { status: "joined" as "joined" | "already" },
}));
vi.mock("convex/react", () => ({
  useMutation: () => async (args: unknown) => {
    submitted.args = args;
    return submitted.result;
  },
}));

const { WaitlistForm } = await import("./WaitlistForm");

// Two tests below set this to pin the desktop/phone source; reset it so a
// later test in this file (or a file that runs after it) never silently
// inherits a narrowed viewport.
const originalInnerWidth = window.innerWidth;

afterEach(() => {
  cleanup();
  submitted.args = null;
  submitted.result = { status: "joined" };
  window.innerWidth = originalInnerWidth;
});

function fillAndSubmit(container: HTMLElement, name: string, email: string) {
  fireEvent.change(screen.getByPlaceholderText("Your name"), {
    target: { value: name },
  });
  fireEvent.change(screen.getByPlaceholderText("Your email"), {
    target: { value: email },
  });
  // Both submit buttons live in the one form; submitting the form itself
  // avoids depending on which of the two is the "live" one at a given width.
  fireEvent.submit(container.querySelector("form")!);
}

describe("the waitlist form", () => {
  test("renders with no session and no props", () => {
    render(<WaitlistForm />);
    expect(screen.getByPlaceholderText("Your name")).toBeTruthy();
  });

  // The refactor that extracted this component out of the old full-page
  // waitlist swapped how it tracks desktop/phone -- from the width of its own
  // (now much narrower) container to the viewport itself. The backend's
  // source field is a closed desktop/phone union, so this is the one thing a
  // silent regression here would corrupt without any type error to catch it.
  test("submits the trimmed name and email with the viewport's source", async () => {
    window.innerWidth = 1200;
    const { container } = render(<WaitlistForm />);
    fillAndSubmit(container, "  Ada Lovelace  ", "ada@example.com");
    await screen.findByText("You are on the list.");
    expect(submitted.args).toEqual({
      name: "Ada Lovelace",
      email: "ada@example.com",
      source: "desktop",
    });
  });

  test("reports a phone source on a narrow viewport", async () => {
    window.innerWidth = 375;
    const { container } = render(<WaitlistForm />);
    fillAndSubmit(container, "Ada Lovelace", "ada@example.com");
    await screen.findByText("You are on the list.");
    expect((submitted.args as { source: string }).source).toBe("phone");
  });

  // "already" is a first-class outcome, not an error -- see joinWaitlist's own
  // comment. A repeat submit must never be shown a false fresh join.
  test("shows the honest 'already' state instead of a false fresh join", async () => {
    submitted.result = { status: "already" };
    const { container } = render(<WaitlistForm />);
    fillAndSubmit(container, "Ada Lovelace", "ada@example.com");
    expect(
      await screen.findByText("You're already on the list."),
    ).toBeTruthy();
  });
});
