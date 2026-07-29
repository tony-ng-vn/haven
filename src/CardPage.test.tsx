// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";

// The page's only dependency on Convex is one public query, so it is stood in
// for rather than run against a deployment. What is being checked here is what
// a stranger sees, and that is decided entirely by the value that query hands
// back.
const answer = vi.hoisted(() => ({ current: undefined as unknown }));
vi.mock("convex/react", () => ({ useQuery: () => answer.current }));
// Stood in, but not thrown away: what this page seeds the sky with is the one
// thing keeping the web card and the iPhone card the same figure, so the stub
// records it.
const skySeed = vi.hoisted(() => ({ current: null as string | null }));
vi.mock("./PersonSky", () => ({
  PersonSky: ({ seed }: { seed: string }) => {
    skySeed.current = seed;
    return null;
  },
}));

const { CardPage } = await import("./CardPage");

afterEach(cleanup);

type Card = {
  handle: string;
  name: string;
  photoUrl: string | null;
  city?: { name: string; admin?: string; country?: string };
  handles: { platform: string; value: string }[];
  primaryPlatform?: string;
};

function show(card: Card | null | undefined) {
  answer.current = card;
  return render(<CardPage handle="mayachen" />);
}

const bare: Card = {
  handle: "mayachen",
  name: "Maya Chen",
  photoUrl: null,
  handles: [],
};

describe("the public card page", () => {
  // The query in flight and a handle nobody holds are different answers, and
  // only one of them is final.
  test("waiting and not-found do not share a screen", () => {
    show(undefined);
    expect(screen.getByRole("status").textContent).toBe("Loading");
    cleanup();

    show(null);
    expect(screen.getByRole("heading").textContent).toBe("Nobody here");
    expect(screen.getByRole("link").getAttribute("href")).toBe("/");
  });

  test("a card with handles links out to each of them", () => {
    show({
      ...bare,
      city: { name: "Ho Chi Minh City", country: "Vietnam" },
      handles: [
        { platform: "instagram", value: "mayachen" },
        { platform: "linkedin", value: "maya-chen-8a91b2" },
      ],
      primaryPlatform: "instagram",
    });

    expect(screen.getByRole("heading").textContent).toBe("Maya Chen");
    expect(screen.getByText("Ho Chi Minh City, Vietnam")).toBeTruthy();
    expect(screen.getByText("Instagram").closest("a")?.getAttribute("href")).toBe(
      "https://instagram.com/mayachen",
    );
    expect(screen.getByText("LinkedIn").closest("a")?.getAttribute("href")).toBe(
      "https://linkedin.com/in/maya-chen-8a91b2",
    );
  });

  // A card whose primary is a phone number publishes no handle for it, on
  // purpose, so the page says the rest is on Haven rather than showing nothing.
  test("a private primary is explained rather than left blank", () => {
    show({ ...bare, primaryPlatform: "phone" });
    expect(screen.getByText("The rest is on Haven.")).toBeTruthy();
  });

  // The iPhone app seeds this person's sky with their username and nothing
  // else. If the web card mixes the display name in, the same person has two
  // different constellations, and renaming themselves scrambles the web one.
  test("the sky is seeded by the username alone", () => {
    show({ ...bare, name: "Maya Chen", handle: "mayachen" });
    expect(skySeed.current).toBe("mayachen");
    expect(skySeed.current).not.toBe("Maya Chenmayachen");
  });

  test("a card with a photo shows it", () => {
    // Queried by class rather than by role: the photo carries an empty alt on
    // purpose -- the name is right below it -- so it is presentational to a
    // screen reader and has no img role to find.
    const { container } = show({ ...bare, photoUrl: "https://example.test/photo.jpg" });
    expect(container.querySelector(".card-photo")?.getAttribute("src")).toBe(
      "https://example.test/photo.jpg",
    );
  });

  // Convex storage urls are signed and can stop resolving. A broken image glyph
  // is the worst possible first sight of Haven, and a card without a photo is
  // an ordinary card.
  test("a photo that will not load leaves an ordinary card behind", () => {
    const { container } = show({ ...bare, photoUrl: "https://example.test/gone.jpg" });
    const photo = container.querySelector(".card-photo");
    expect(photo).not.toBeNull();
    fireEvent.error(photo!);
    expect(container.querySelector(".card-photo")).toBeNull();
    expect(screen.getByRole("heading").textContent).toBe("Maya Chen");
  });

  // The platform list is closed by the validator today. If it ever grows a
  // member this page has no address for, the row is dropped -- a stranger's
  // first sight of Haven must not be a white screen.
  test("a platform the page has no address for is skipped, not crashed on", () => {
    show({
      ...bare,
      handles: [
        { platform: "instagram", value: "mayachen" },
        { platform: "signal", value: "maya.99" },
      ],
    });
    expect(screen.getByText("Instagram")).toBeTruthy();
    expect(screen.queryByText("maya.99")).toBeNull();
  });
});
