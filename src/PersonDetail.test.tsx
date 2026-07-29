// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import type { Id } from "../convex/_generated/dataModel";

// The page subscribes to two queries and calls three mutations, none of which
// this is about. What is being checked is what somebody sees after they saved a
// handle, and that is decided entirely by the person doc the query hands back.
//
// The two subscriptions are told apart by their arguments: getPerson is asked
// for an id, the shared note for a personId.
const person = vi.hoisted(() => ({ current: undefined as unknown }));
vi.mock("convex/react", () => ({
  useQuery: (_fn: unknown, args: Record<string, unknown>) =>
    "personId" in args ? null : person.current,
  useMutation: () => async () => undefined,
}));
vi.mock("./PersonSky", () => ({ PersonSky: () => null }));

const { PersonDetail } = await import("./PersonDetail");

afterEach(cleanup);

const id = "p1" as Id<"people">;

type Doc = {
  _id: string;
  _creationTime: number;
  name: string;
  link?: string;
  context?: string;
  contactHandles?: { platform: string; value: string }[];
  preferredPlatform?: string;
  photoUrl: string | null;
  connection: null;
  updatedAt: number;
};

const base: Doc = {
  _id: "p1",
  _creationTime: Date.UTC(2026, 6, 1),
  name: "Mai Nguyen",
  photoUrl: null,
  connection: null,
  updatedAt: 0,
};

function show(doc: Doc) {
  person.current = doc;
  return render(<PersonDetail id={id} initial={null} onSaved={() => {}} />);
}

describe("the handles on a person's page", () => {
  test("a saved handle is a row you can actually open", () => {
    show({
      ...base,
      contactHandles: [
        { platform: "instagram", value: "mai.makes" },
        { platform: "phone", value: "+84 90 123 4567" },
      ],
      preferredPlatform: "instagram",
    });

    const instagram = screen.getByText("Instagram").closest("a");
    expect(instagram?.getAttribute("href")).toBe(
      "https://instagram.com/mai.makes",
    );
    // Leaving Haven for the open web opens a tab of its own, and never hands
    // the destination a window.opener it could steer.
    expect(instagram?.getAttribute("target")).toBe("_blank");
    expect(instagram?.getAttribute("rel")).toBe("noopener noreferrer");
    expect(screen.getByText("mai.makes")).toBeTruthy();

    // A number is dialled in place: a new tab for a tel: link opens an empty
    // window that never comes back.
    const phone = screen.getByText("Phone").closest("a");
    expect(phone?.getAttribute("href")).toBe("tel:+84901234567");
    expect(phone?.getAttribute("target")).toBeNull();
  });

  test("the platform they said to use first is marked", () => {
    show({
      ...base,
      contactHandles: [
        { platform: "instagram", value: "mai.makes" },
        { platform: "telegram", value: "maimakes" },
      ],
      preferredPlatform: "telegram",
    });
    const marked = screen.getByText("preferred").closest("a");
    expect(marked?.getAttribute("href")).toBe("https://t.me/maimakes");
  });

  // A handle Haven cannot open is still how you reach them, so the row stays
  // and only the promise of a tap goes.
  test("a platform Haven cannot open still shows the handle", () => {
    const { container } = show({
      ...base,
      contactHandles: [{ platform: "signal", value: "mai.99" }],
    });
    expect(screen.getByText("signal")).toBeTruthy();
    expect(screen.getByText("mai.99")).toBeTruthy();
    expect(container.querySelector(".person-handle")?.tagName).toBe("SPAN");
  });

  test("no handles means no empty box", () => {
    const { container } = show(base);
    expect(container.querySelector(".person-handles")).toBeNull();
    expect(screen.queryByText("Ways to reach them")).toBeNull();
  });

  // The handles are added beside the free-text link, not instead of it: one is
  // a platform Haven knows, the other is whatever page they sent you.
  test("the link field and the rest of the page are untouched", () => {
    show({
      ...base,
      link: "https://mai.example",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
    });
    const linkField = screen.getByLabelText("Link") as HTMLInputElement;
    expect(linkField.value).toBe("https://mai.example");
    expect(screen.getByText("Private context")).toBeTruthy();
    expect(screen.getByText("Save")).toBeTruthy();
    expect(screen.getByText("Shared notes")).toBeTruthy();
    expect(screen.getByText("Remove from your network")).toBeTruthy();
  });
});
