// @vitest-environment happy-dom
import { readFileSync } from "node:fs";
import { afterEach, describe, expect, test, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
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
  headline?: string;
  bio?: string;
  company?: string;
  role?: string;
  city?: { name: string; admin?: string; country?: string };
  contactHandles?: {
    platform: string;
    value: string;
    platformId?: string;
    addedAt?: number;
  }[];
  preferredPlatform?: string;
  photoUrl: string | null;
  connection: { state: "connected" | "ended"; peerUsername: string } | null;
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

/// What one part of the page says for this person, or null when that part is
/// not drawn at all. Every field below is a line that has to disappear rather
/// than render empty, so "no element" is the answer being checked as often as
/// the text is.
function shown(doc: Partial<Doc>, selector: string): string | null {
  const { container } = show({ ...base, ...doc });
  return container.querySelector(selector)?.textContent ?? null;
}

/// The platform names down the reach rows, in the order they are drawn.
function reachOrder(container: HTMLElement): (string | null)[] {
  return [
    ...container.querySelectorAll(".person-handle .card-handle-label"),
  ].map((node) => node.textContent);
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

  // LinkedIn frees a vanity slug back into its pool six months after the
  // account holding it moves on -- an old enough saved handle is worth a
  // quiet second look.
  test("a linkedin handle saved more than six months ago gets a staleness hint", () => {
    const sixMonthsMs = 1000 * 60 * 60 * 24 * 30 * 6;
    show({
      ...base,
      contactHandles: [
        {
          platform: "linkedin",
          value: "mai-tran-8a91b2",
          addedAt: Date.now() - sixMonthsMs - 1,
        },
      ],
    });
    expect(screen.getByText("Saved a while ago -- still the right link?")).toBeTruthy();
  });

  test("a recently saved linkedin handle gets no staleness hint", () => {
    show({
      ...base,
      contactHandles: [
        { platform: "linkedin", value: "mai-tran-8a91b2", addedAt: Date.now() },
      ],
    });
    expect(screen.queryByText(/still the right link/)).toBeNull();
  });

  // Legacy rows saved before addedAt existed must not read as stale by
  // default -- there is nothing to date them against.
  test("a linkedin handle with no addedAt gets no staleness hint", () => {
    show({
      ...base,
      contactHandles: [{ platform: "linkedin", value: "mai-tran-8a91b2" }],
    });
    expect(screen.queryByText(/still the right link/)).toBeNull();
  });

  // The reclaim window is LinkedIn's own policy -- an equally old handle on
  // any other platform stays quiet.
  test("an old handle on a platform other than linkedin gets no staleness hint", () => {
    const sixMonthsMs = 1000 * 60 * 60 * 24 * 30 * 6;
    show({
      ...base,
      contactHandles: [
        {
          platform: "instagram",
          value: "mai.makes",
          addedAt: Date.now() - sixMonthsMs - 1,
        },
      ],
    });
    expect(screen.queryByText(/still the right link/)).toBeNull();
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
    expect(screen.getByText("What you remember")).toBeTruthy();
    expect(screen.getByText("Save")).toBeTruthy();
    expect(screen.getByText("Shared notes")).toBeTruthy();
    expect(screen.getByText("Remove from your network")).toBeTruthy();
  });

  // The one they said to use first leads, because that is what choosing it
  // meant. Everything else keeps the order it was saved in.
  test("the platform they chose comes first", () => {
    const { container } = show({
      ...base,
      contactHandles: [
        { platform: "instagram", value: "mai.makes" },
        { platform: "telegram", value: "maimakes" },
        { platform: "phone", value: "+84 90 123 4567" },
      ],
      preferredPlatform: "telegram",
    });
    expect(reachOrder(container)).toEqual(["Telegram", "Instagram", "Phone"]);
  });

  // The server stores the platform string verbatim, so a row can hold
  // "Instagram" while preferredPlatform says "instagram". A raw === would
  // quietly bury the row somebody actually picked.
  test("different capitals are still the platform they chose", () => {
    const { container } = show({
      ...base,
      contactHandles: [
        { platform: "telegram", value: "maimakes" },
        { platform: "Instagram", value: "mai.makes" },
      ],
      preferredPlatform: "instagram",
    });
    expect(reachOrder(container)).toEqual(["Instagram", "Telegram"]);
    expect(screen.getByText("preferred").closest("a")?.getAttribute("href")).toBe(
      "https://instagram.com/mai.makes",
    );
  });

  test("no preference leaves the order alone", () => {
    const { container } = show({
      ...base,
      contactHandles: [
        { platform: "telegram", value: "maimakes" },
        { platform: "instagram", value: "mai.makes" },
      ],
    });
    expect(reachOrder(container)).toEqual(["Telegram", "Instagram"]);
    expect(screen.queryByText("preferred")).toBeNull();
  });
});

// What they do and where they are, as one line under their name. The formula is
// PersonModel.detail's: the work, then the city, and nothing at all when there
// is nothing to say.
describe("the line under their name", () => {
  test("what they do, then where they are", () => {
    expect(shown({ role: "Engineer" }, ".person-detail-line")).toBe("Engineer");
    expect(shown({ company: "Analytical Engines" }, ".person-detail-line")).toBe(
      "Analytical Engines",
    );
    expect(
      shown(
        { role: "Engineer", company: "Analytical Engines" },
        ".person-detail-line",
      ),
    ).toBe("Engineer, Analytical Engines");
    expect(
      shown({ city: { name: "Sai Gon", country: "Vietnam" } }, ".person-detail-line"),
    ).toBe("Sai Gon, Vietnam");
    expect(
      shown(
        {
          role: "Engineer",
          company: "Analytical Engines",
          city: { name: "Sai Gon", admin: "Ho Chi Minh", country: "Vietnam" },
        },
        ".person-detail-line",
      ),
    ).toBe("Engineer, Analytical Engines | Sai Gon, Ho Chi Minh, Vietnam");
  });

  test("nothing to say draws no line", () => {
    expect(shown({}, ".person-detail-line")).toBeNull();
    // A field somebody blanked is not a fact about them.
    expect(
      shown({ role: "", company: "", city: { name: "" } }, ".person-detail-line"),
    ).toBeNull();
  });

  // MapKit hands back an empty admin area for countries that have no states.
  test("a city with no state gets no stray comma", () => {
    expect(
      shown(
        { city: { name: "Sai Gon", admin: "", country: "Vietnam" } },
        ".person-detail-line",
      ),
    ).toBe("Sai Gon, Vietnam");
  });
});

describe("what they say about themselves", () => {
  test("the headline is the line, and the bio stands in for it", () => {
    expect(shown({ headline: "Compiler engineer" }, ".person-about")).toBe(
      "Compiler engineer",
    );
    expect(shown({ bio: "Builds ceramics." }, ".person-about")).toBe(
      "Builds ceramics.",
    );
    expect(
      shown(
        { headline: "Compiler engineer", bio: "Builds ceramics." },
        ".person-about",
      ),
    ).toBe("Compiler engineer");
  });

  test("nothing written means no line", () => {
    expect(shown({}, ".person-about")).toBeNull();
    // An empty headline is still the headline: it stands in front of the bio and
    // then draws nothing, which is what iOS's `headline ?? bio` does.
    expect(shown({ headline: "", bio: "Builds ceramics." }, ".person-about")).toBeNull();
  });
});

describe("their photo", () => {
  test("rides in the sky band with their name", () => {
    const { container } = show({
      ...base,
      photoUrl: "https://files.example/mai.jpg",
    });
    const photo = container.querySelector(".person-sky-band .person-photo");
    expect(photo?.getAttribute("src")).toBe("https://files.example/mai.jpg");
    // The name beside it says who this is; announcing "photo" gives a screen
    // reader nothing it can use.
    expect(photo?.getAttribute("aria-hidden")).toBe("true");
    expect(photo?.getAttribute("alt")).toBe("");
  });

  // A Convex storage url is signed and can stop resolving, and a person with no
  // photo is an ordinary person -- so a url that fails leaves the page it was
  // decorating, not a broken-image glyph.
  test("a url that stops resolving leaves an ordinary person", () => {
    const { container } = show({
      ...base,
      photoUrl: "https://files.example/gone.jpg",
    });
    const photo = container.querySelector(".person-photo");
    expect(photo).not.toBeNull();
    fireEvent.error(photo as Element);
    expect(container.querySelector(".person-photo")).toBeNull();
    expect(container.querySelector(".person-name")?.textContent).toBe("Mai Nguyen");
  });

  test("most people have no photo", () => {
    expect(show(base).container.querySelector(".person-photo")).toBeNull();
  });
});

describe("whether this row still follows a card", () => {
  test("a live connection says so", () => {
    expect(
      shown(
        { connection: { state: "connected", peerUsername: "mai" } },
        ".person-connection",
      ),
    ).toBe("Connected");
  });

  // The state that has to be legible: a frozen row and a person who never
  // changes anything look identical without it.
  test("an ended one says what that means for the fields", () => {
    const { container } = show({
      ...base,
      connection: { state: "ended", peerUsername: "mai" },
    });
    expect(container.querySelector(".person-connection")?.textContent).toBe(
      "No longer connected",
    );
    expect(container.querySelector(".person-frozen")).not.toBeNull();
  });

  test("somebody you saved yourself has neither", () => {
    const { container } = show(base);
    expect(container.querySelector(".person-connection")).toBeNull();
    expect(container.querySelector(".person-frozen")).toBeNull();
  });

  test("a live connection is not warned about", () => {
    expect(
      shown(
        { connection: { state: "connected", peerUsername: "mai" } },
        ".person-frozen",
      ),
    ).toBeNull();
  });
});

describe("the note you keep", () => {
  test("is called what the app calls it, and says how to write it", () => {
    const { container } = show(base);
    expect(screen.getByLabelText("What you remember")).toBeTruthy();
    expect(
      screen.getByText("One line per thing. Each is searchable on its own."),
    ).toBeTruthy();
    // The web's own name for it, which nothing else in Haven ever used --
    // including the shared-note card, which pointed at it by name.
    expect(container.textContent?.toLowerCase()).not.toContain(
      "private context",
    );
  });

  test("still saves the same field", () => {
    show({ ...base, context: "Met at the Hanoi meetup." });
    const field = screen.getByLabelText("What you remember") as HTMLTextAreaElement;
    expect(field.id).toBe("person-context");
    expect(field.value).toBe("Met at the Hanoi meetup.");
  });
});

// Pinned to the iOS source, the way designTokens.test.ts pins the palette and
// reach.test.ts pins the addresses. Nothing imports across the platform
// boundary, so a sentence reworded on the phone drifts silently here. Every pin
// below asserts its parse found something first, because a regex that quietly
// matches nothing turns the assertion under it into a green no-op.
describe("the iOS screen this mirrors", () => {
  const screenSwift = readFileSync(
    "ios/Haven/Directory/PersonScreen.swift",
    "utf8",
  );
  const modelSwift = readFileSync(
    "ios/Haven/Directory/PersonModel.swift",
    "utf8",
  );

  /// The slice of the Swift between two landmarks, so one ternary's strings
  /// cannot be read as another's.
  function section(from: string, to: string): string {
    const start = screenSwift.indexOf(from);
    expect(start, `PersonScreen.swift no longer has "${from}"`).toBeGreaterThan(-1);
    const end = screenSwift.indexOf(to, start);
    expect(end, `PersonScreen.swift no longer has "${to}"`).toBeGreaterThan(start);
    return screenSwift.slice(start, end);
  }

  /// What a pattern captured, having checked that it captured anything at all.
  function pin(source: string, pattern: RegExp, what: string): string[] {
    const found = source.match(pattern);
    expect(found, `the iOS source no longer has ${what}`).not.toBeNull();
    const groups = found!.slice(1);
    expect(groups.length, `${what} captured nothing`).toBeGreaterThan(0);
    for (const group of groups) {
      expect(group ?? "", `${what} parsed empty`).not.toBe("");
    }
    return groups;
  }

  test("says the same two things about a connection", () => {
    // Anchored on `label`: the ternary a few lines above it picks SF Symbol
    // names in exactly this shape, and a loose regex grabs those instead.
    const chip = section("private var label: String {", "/// The address is worth");
    const [connected, ended] = pin(
      chip,
      /\.connected \? "([^"]*)" : "([^"]*)"/,
      "the connection labels",
    );
    expect(
      shown(
        { connection: { state: "connected", peerUsername: "mai" } },
        ".person-connection",
      ),
    ).toBe(connected);
    expect(
      shown(
        { connection: { state: "ended", peerUsername: "mai" } },
        ".person-connection",
      ),
    ).toBe(ended);
  });

  test("says the same sentence about a row that stopped following a card", () => {
    const [sentence] = pin(
      screenSwift,
      /Text\("(This is the last thing[^"]*)"\)/,
      "the frozen-row sentence",
    );
    expect(
      shown({ connection: { state: "ended", peerUsername: "mai" } }, ".person-frozen"),
    ).toBe(sentence);
  });

  test("calls the note and its two headings the same thing", () => {
    const [heading] = pin(
      screenSwift,
      /Text\("(What you remember)"\)\s*\.havenGroupLabel\(\)/,
      "the note heading",
    );
    const [supporting] = pin(
      screenSwift,
      /Text\("(One line per thing[^"]*)"\)/,
      "the note's supporting line",
    );
    const [reachHeading] = pin(
      screenSwift,
      /Text\("(Ways to reach them)"\)/,
      "the reach heading",
    );
    show(base);
    expect(screen.getByLabelText(heading)).toBeTruthy();
    expect(screen.getByText(supporting)).toBeTruthy();
    cleanup();
    show({ ...base, contactHandles: [{ platform: "signal", value: "mai.99" }] });
    expect(screen.getByText(reachHeading)).toBeTruthy();
  });

  test("hides the photo from a screen reader for the same reason", () => {
    const header = section("if let photo {", "VStack(alignment: .leading");
    expect(header).toContain("accessibilityHidden(true)");
    const { container } = show({
      ...base,
      photoUrl: "https://files.example/mai.jpg",
    });
    expect(
      container.querySelector(".person-photo")?.getAttribute("aria-hidden"),
    ).toBe("true");
  });

  test("builds the line under the name from the same parts", () => {
    const [order] = pin(
      modelSwift,
      /let work = \[([^\]]*)\]\s*\.compactMap/,
      "the order work reads in",
    );
    expect(order).toBe("role, company");
    const [work] = pin(
      modelSwift,
      /\[work\.joined\(separator: "([^"]*)"\)\]/,
      "how a role and a company are joined",
    );
    const [halves] = pin(
      modelSwift,
      /all\.joined\(separator: "([^"]*)"\)/,
      "how the work and the city are joined",
    );
    const [cityOrder, cityJoin] = pin(
      modelSwift,
      /\[([^\]]*)\]\s*\.compactMap \{ \$0 \}\s*\.filter \{ !\$0\.isEmpty \}\s*\.joined\(separator: "([^"]*)"\)/,
      "how a city line is joined",
    );
    expect(cityOrder).toBe("name, admin, country");
    expect(
      shown(
        {
          role: "Engineer",
          company: "Analytical Engines",
          city: { name: "Sai Gon", admin: "Ho Chi Minh", country: "Vietnam" },
        },
        ".person-detail-line",
      ),
    ).toBe(
      `Engineer${work}Analytical Engines${halves}Sai Gon${cityJoin}Ho Chi Minh${cityJoin}Vietnam`,
    );
  });

  test("prefers the headline over the bio, the same way", () => {
    pin(
      screenSwift,
      /if let about = person\.(headline) \?\? person\.(bio)/,
      "the about line",
    );
    expect(
      shown(
        { headline: "Compiler engineer", bio: "Builds ceramics." },
        ".person-about",
      ),
    ).toBe("Compiler engineer");
  });
});

// The path every user actually takes, and the one nothing covered: tap a star
// on the atlas and the band renders from the snapshot while getPerson is still
// in flight. If the band waits for the live doc, the name morph settles and
// then jumps, because .person-sky-content is bottom-anchored and everything
// arriving below the name pushes it up after the transition has landed.
describe("the snapshot a tap hands over", () => {
  const snapshot = {
    _id: "p1" as never,
    _creationTime: Date.UTC(2026, 6, 1),
    name: "Mai Nguyen",
    role: "Ceramicist",
    company: "Kiln Studio",
    city: { name: "Sai Gon", country: "Vietnam" },
    headline: "Makes teapots",
    photoUrl: "https://example.invalid/mai.jpg",
    connection: { state: "connected" as const, peerUsername: "mai" },
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
    preferredPlatform: "instagram",
  };

  test("the band is complete before the live doc lands", () => {
    // undefined is the query in flight, which is exactly the frame the view
    // transition captures.
    person.current = undefined;
    render(<PersonDetail id={id} initial={snapshot} onSaved={() => {}} />);

    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Mai Nguyen");
    expect(
      screen.getByText("Ceramicist, Kiln Studio | Sai Gon, Vietnam"),
    ).toBeTruthy();
    expect(screen.getByText("Connected")).toBeTruthy();
    expect(screen.getByText("Makes teapots")).toBeTruthy();
    expect(screen.getByText("mai.makes")).toBeTruthy();
    expect(document.querySelector(".person-photo")).not.toBeNull();
  });
});

describe("a photo that stops resolving", () => {
  test("a later url is not suppressed by the one that failed", () => {
    // Keyed to the url rather than to a boolean: one flaky request used to hide
    // the photo for the rest of the visit, and a photo replaced from a phone
    // arrived on the live subscription only to be swallowed by a stale flag.
    person.current = { ...base, photoUrl: "https://example.invalid/one.jpg" };
    const view = render(<PersonDetail id={id} initial={null} onSaved={() => {}} />);
    const img = document.querySelector(".person-photo") as HTMLImageElement;
    fireEvent.error(img);
    expect(document.querySelector(".person-photo")).toBeNull();

    person.current = { ...base, photoUrl: "https://example.invalid/two.jpg" };
    view.rerender(<PersonDetail id={id} initial={null} onSaved={() => {}} />);
    expect(
      (document.querySelector(".person-photo") as HTMLImageElement)?.src,
    ).toContain("two.jpg");
  });
});

describe("the note hint reaches a screen reader", () => {
  test("the field is described by it, not merely followed by it", () => {
    show(base);
    const field = screen.getByLabelText("What you remember");
    const hintId = field.getAttribute("aria-describedby");
    expect(hintId).toBe("person-context-hint");
    expect(document.getElementById(hintId as string)?.textContent).toBe(
      "One line per thing. Each is searchable on its own.",
    );
  });
});
