// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

import {
  initialPreviewAuthMode,
  previewAccessQueryArgs,
  PreviewCodeForm,
  PreviewHome,
  PreviewLoading,
  PreviewProfileSetup,
} from "./PreviewPortal";

afterEach(cleanup);

describe("the preview access flow", () => {
  test("keeps the invitation while letting an existing member switch to sign-in", () => {
    expect(initialPreviewAuthMode("/preview", "", "pending-code")).toBe(
      "sign-up",
    );
    expect(initialPreviewAuthMode("/sign-in", "", "pending-code")).toBe(
      "sign-in",
    );
    expect(initialPreviewAuthMode("/sign-up", "", null)).toBeNull();
    expect(initialPreviewAuthMode("/preview", "#/verify", null)).toBe(
      "sign-in",
    );
  });

  test("announces preview loading states to assistive technology", () => {
    render(<PreviewLoading label="Loading preview" />);

    expect(screen.getByRole("status").textContent).toBe("Loading preview");
  });

  test("partitions the access query when the signed-in account changes", () => {
    expect(previewAccessQueryArgs(false, null)).toBe("skip");
    expect(previewAccessQueryArgs(true, "user-a")).toEqual({
      sessionKey: "user-a",
    });
    expect(previewAccessQueryArgs(true, "user-b")).toEqual({
      sessionKey: "user-b",
    });
  });

  test("asks for a preview code before offering account creation", async () => {
    const submit = vi.fn(async () => undefined);
    render(<PreviewCodeForm onSubmit={submit} onSignIn={vi.fn()} />);

    expect(screen.getByRole("heading", { name: /preview access/i })).toBeTruthy();
    expect(screen.getByLabelText(/preview code/i)).toBeTruthy();
    expect(screen.getByRole("link", { name: /don't have a code/i })).toHaveProperty(
      "pathname",
      "/waitlist",
    );

    fireEvent.change(screen.getByLabelText(/preview code/i), {
      target: { value: " test-preview-code " },
    });
    fireEvent.submit(screen.getByRole("button", { name: /continue/i }).closest("form")!);

    await vi.waitFor(() =>
      expect(submit).toHaveBeenCalledWith("test-preview-code"),
    );
  });

  test("offers existing preview members a direct sign-in path", () => {
    const signIn = vi.fn();
    render(<PreviewCodeForm onSubmit={vi.fn()} onSignIn={signIn} />);

    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));
    expect(signIn).toHaveBeenCalledTimes(1);
  });

  test("collects only a name when creating the Haven profile", async () => {
    const create = vi.fn(async () => undefined);
    render(<PreviewProfileSetup onCreate={create} onSignOut={vi.fn()} />);

    expect(screen.getByLabelText(/your name/i)).toBeTruthy();
    expect(document.querySelectorAll("input")).toHaveLength(1);

    fireEvent.change(screen.getByLabelText(/your name/i), {
      target: { value: " Tony Nguyen " },
    });
    fireEvent.submit(
      screen.getByRole("button", { name: /create my profile/i }).closest("form")!,
    );

    await vi.waitFor(() => expect(create).toHaveBeenCalledWith("Tony Nguyen"));
  });

  test("sends an admitted member to the private Sky page", () => {
    render(<PreviewHome name="Tony" onSignOut={vi.fn()} />);

    expect(
      screen.getByRole("heading", { name: /haven on the web is coming soon/i }),
    ).toBeTruthy();
    expect(screen.getByRole("link", { name: /try your sky/i })).toHaveProperty(
      "pathname",
      "/sky",
    );
  });
});
