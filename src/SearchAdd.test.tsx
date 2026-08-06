// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { useState } from "react";
import type { Id } from "../convex/_generated/dataModel";

// The sky reads one query twice (the stable field, and the live name search)
// and both are answered with the same list here: what these tests are about is
// the add form and what it is allowed to share a screen with, not search.
const people = vi.hoisted(() => ({ current: [] as unknown[] }));
// listPersonNames's own pool (S7): every one of the caller's people, not
// scoped to a query or capped at the sky's recent-20 the way searchPeople's
// two subscriptions are. Distinguished from them by args shape below --
// listPersonNames takes {}, searchPeople always takes {query}. Defaults to
// mirroring `people` in show() below, since most tests do not care about the
// distinction; the S7 test that does sets it independently.
const suggestionPool = vi.hoisted(() => ({ current: [] as unknown[] }));
const saved = vi.hoisted(() => ({ args: null as unknown }));
// addPerson returns a creation outcome, not a bare id (identity brief, task
// 2); this is the "created" case every test but the conflict one below
// wants, overridable per test for the others.
const addPersonResult = vi.hoisted(() => ({
  current: { status: "created", personId: "p9" } as unknown,
}));
const personQuery = vi.hoisted(() => ({
  current: async (..._args: unknown[]): Promise<unknown> => null,
}));
vi.mock("convex/react", () => ({
  useQuery: (_fn: unknown, args: Record<string, unknown>) =>
    "query" in args ? people.current : suggestionPool.current,
  useMutation: () => async (args: unknown) => {
    saved.args = args;
    return addPersonResult.current;
  },
  useAction: () => async () => [],
  // Only addPerson's attached/already branch reads from this, to fetch the
  // existing owner's real name; unreached by the created-outcome tests below.
  useConvex: () => ({
    query: (...args: unknown[]) => personQuery.current(...args),
  }),
}));

const { SearchAdd } = await import("./SearchAdd");

afterEach(() => {
  cleanup();
  personQuery.current = async () => null;
});

function show(field: { _id: string; name: string }[], query = "Mai") {
  const withCreationTime = field.map((p) => ({
    ...p,
    _creationTime: Date.UTC(2026, 6, 1),
  }));
  people.current = withCreationTime;
  suggestionPool.current = withCreationTime;
  return render(
    <SearchAdd
      query={query}
      onQueryChange={() => {}}
      onOpen={() => {}}
      onOpenCapture={() => {}}
      morphId={null as Id<"people"> | null}
    />,
  );
}

function openAddForm() {
  fireEvent.click(screen.getByText('Add "Mai" to your sky'));
}

describe("naming somebody the web has never seen", () => {
  // Two people typing "WhatsApp" and "whats app" made two identities for one
  // platform, invisibly. The list is the fix, and it is the same list iOS
  // offers.
  test("where you know them is a list, not a typing test", () => {
    show([]);
    openAddForm();
    const select = screen.getByLabelText("Where you know them") as HTMLSelectElement;
    const options = [...select.querySelectorAll("option")];
    expect(options.map((option) => option.textContent)).toEqual([
      "Instagram",
      "X",
      "LinkedIn",
      "Phone",
      "WhatsApp",
      "Telegram",
    ]);
    expect(select.value).toBe("instagram");
  });

  test("the handle field follows the platform", () => {
    show([]);
    openAddForm();
    const select = screen.getByLabelText("Where you know them");
    const handle = () =>
      screen.getByLabelText("Their handle there") as HTMLInputElement;

    expect(handle().placeholder).toBe("Paste a link or type the handle");
    expect(screen.getByText("@")).toBeTruthy();

    fireEvent.change(select, { target: { value: "phone" } });
    expect(handle().placeholder).toBe("Their number");
    expect(handle().inputMode).toBe("tel");
    // A number has no at-sign in front of it.
    expect(screen.queryByText("@")).toBeNull();
  });

  // The field says to paste a link, so a pasted link has to become a handle.
  // Stored whole it would open instagram.com/https://instagram.com/mai.makes.
  test("a pasted profile link is saved as the handle", async () => {
    saved.args = null;
    show([]);
    openAddForm();
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "https://instagram.com/mai.makes" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));

    await waitFor(() => expect(saved.args).not.toBeNull());
    expect(saved.args).toMatchObject({
      name: "Mai",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      context: "ceramics market",
    });
  });

  // The trigger somebody just pressed unmounts when the form replaces it, and
  // focus would land on the body -- the next Tab restarts at the top of the
  // page rather than in the form they just opened.
  test("focus lands in the form that replaced the trigger", () => {
    show([]);
    openAddForm();
    expect(document.activeElement).toBe(
      screen.getByLabelText("Where you know them"),
    );
  });
});

describe("one thing to do at a time", () => {
  test("the trigger and the form's submit never share the screen", () => {
    show([]);
    expect(screen.getAllByText('Add "Mai" to your sky')).toHaveLength(1);
    openAddForm();
    expect(screen.getAllByText('Add "Mai" to your sky')).toHaveLength(1);
    expect(screen.getByLabelText("How you met")).toBeTruthy();
  });

  // The empty state is telling you to add someone. While the form is open you
  // are doing exactly that, so its message is spent -- and it sat underneath
  // the growing form, which is what the screenshot showed.
  test("the empty sky steps aside for the form", () => {
    show([]);
    expect(screen.getByText("No one here yet")).toBeTruthy();
    openAddForm();
    expect(screen.queryByText("No one here yet")).toBeNull();
    expect(screen.queryByText("Capture someone new")).toBeNull();
  });

  test("the floating capture button does not compete with the form", () => {
    show([{ _id: "p1", name: "Zoe" }]);
    expect(screen.getByText("Capture someone new")).toBeTruthy();
    openAddForm();
    expect(screen.queryByText("Capture someone new")).toBeNull();
  });
});

// A host that actually owns the query, which is the only way to see what a
// keystroke does. The shipped harness passes a fixed query and a no-op
// onQueryChange, so it cannot express this at all -- and the bug it hides is
// the worst kind: not a broken screen, a handle filed under the wrong person.
function HostedSearchAdd({ initial }: { initial: string }) {
  const [query, setQuery] = useState(initial);
  return (
    <>
      <input
        aria-label="name"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      <SearchAdd
        query={query}
        onQueryChange={setQuery}
        onOpen={() => {}}
        onOpenCapture={() => {}}
        morphId={null as Id<"people"> | null}
      />
    </>
  );
}

describe("retyping the name does not carry the old form over", () => {
  test("a filled form empties when the name changes", () => {
    people.current = [];
    render(<HostedSearchAdd initial="Mai" />);
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "mai.makes" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });

    // Correct the name. The form was about Mai, so it must not come back
    // holding Mai's handle ready to be filed under Bob.
    fireEvent.change(screen.getByLabelText("name"), { target: { value: "Bob" } });

    expect(screen.queryByLabelText("How you met")).toBeNull();
    fireEvent.click(screen.getByText('Add "Bob" to your sky'));
    expect((screen.getByLabelText("Their handle there") as HTMLInputElement).value).toBe("");
    expect((screen.getByLabelText("How you met") as HTMLInputElement).value).toBe("");
  });
});

describe("a paste Haven cannot read a handle out of", () => {
  test("is refused rather than stored as wreckage", async () => {
    people.current = [];
    saved.args = null;
    show([]);
    openAddForm();
    fireEvent.change(screen.getByLabelText("Where you know them"), {
      target: { value: "linkedin" },
    });
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "https://www.linkedin.com/mwlite/in/mai-nguyen" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));

    await waitFor(() => {
      expect(screen.getByRole("alert").textContent).toContain("LinkedIn handle");
    });
    expect(saved.args).toBeNull();
  });
});

// addPerson can find that two submitted handles already belong to two
// different people (identity brief, task 2). This form only ever submits
// one handle, so the server never returns this today, but the client still
// has to survive the outcome honestly rather than open one of the two people
// as if the server had picked a winner.
describe("a handle addPerson cannot resolve to one person", () => {
  afterEach(() => {
    addPersonResult.current = { status: "created", personId: "p9" };
  });

  test("conflict leaves the form open and writes nothing", async () => {
    people.current = [];
    saved.args = null;
    addPersonResult.current = {
      status: "conflict",
      personIds: ["p1", "p2"],
    };
    let opened: unknown = null;
    render(
      <SearchAdd
        query="Mai"
        onQueryChange={() => {}}
        onOpen={(person) => {
          opened = person;
        }}
        onOpenCapture={() => {}}
        morphId={null as Id<"people"> | null}
      />,
    );
    openAddForm();
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "mai.makes" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));

    await waitFor(() => {
      expect(screen.getByRole("alert").textContent).toContain(
        "two different people",
      );
    });
    // The mutation still ran (this is a server outcome, not a client
    // refusal), but nothing was opened -- there is no winner to navigate to.
    expect(saved.args).not.toBeNull();
    expect(opened).toBeNull();
  });
});

// R6 (identity brief, round 2): handleDropped used to be invisible on the
// web -- the save landed, the note was kept, but the handle silently never
// made it onto the person's card because they were already at the 8-handle
// cap, and the form navigated away as though everything had been saved.
describe("a save whose handle could not fit under the owner's cap", () => {
  afterEach(() => {
    addPersonResult.current = { status: "created", personId: "p9" };
  });

  test("handleDropped shows a notice instead of silently navigating, with a way to still open them", async () => {
    people.current = [];
    saved.args = null;
    addPersonResult.current = {
      status: "attached",
      personId: "p1",
      noteTruncated: false,
      handleDropped: true,
    };
    let opened: unknown = null;
    render(
      <SearchAdd
        query="Mai"
        onQueryChange={() => {}}
        onOpen={(person) => {
          opened = person;
        }}
        onOpenCapture={() => {}}
        morphId={null as Id<"people"> | null}
      />,
    );
    openAddForm();
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "mai.makes" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));

    await waitFor(() => {
      expect(screen.getByText(/Their handles are full/).textContent).toContain(
        "Instagram",
      );
    });
    // Saved, but not navigated automatically: the loss has to be seen first.
    expect(saved.args).not.toBeNull();
    expect(opened).toBeNull();

    fireEvent.click(screen.getByText("View them"));
    expect(opened).toEqual({
      _id: "p1",
      name: "Mai",
      _creationTime: expect.any(Number),
    });
  });
});

describe("a save that lands before its cosmetic name lookup", () => {
  afterEach(() => {
    addPersonResult.current = { status: "created", personId: "p9" };
  });

  test("a failed name lookup does not report the successful attach as failed", async () => {
    people.current = [];
    saved.args = null;
    addPersonResult.current = {
      status: "attached",
      personId: "p1",
      noteTruncated: false,
      handleDropped: false,
    };
    personQuery.current = async () => {
      throw new Error("name lookup failed");
    };
    let opened: unknown = null;
    render(
      <SearchAdd
        query="Mai"
        onQueryChange={() => {}}
        onOpen={(person) => {
          opened = person;
        }}
        onOpenCapture={() => {}}
        morphId={null as Id<"people"> | null}
      />,
    );
    openAddForm();
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "mai.makes" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "ceramics market" },
    });
    fireEvent.click(screen.getByText('Add "Mai" to your sky'));

    await waitFor(() => {
      expect(opened).toEqual({
        _id: "p1",
        name: "Mai",
        _creationTime: expect.any(Number),
      });
    });
    expect(screen.queryByRole("alert")).toBeNull();
  });
});

// "Same person?" (identity brief, task 4): a name close enough to an
// existing person surfaces them while the name is still being typed, and
// picking one arms addPerson's attachToPersonId. The mocked useQuery answers
// every subscription with the same list, so the candidate here is also the
// live name search's own result -- exactly the pool nameSuggestions is meant
// to run over.
describe("Same person? while typing a name", () => {
  afterEach(() => {
    addPersonResult.current = { status: "created", personId: "p9" };
  });

  test("a close name match is offered, not silently skipped", () => {
    const { container } = show([{ _id: "p1", name: "Dun Duong" }], "Dun Duogn");
    expect(screen.getByText("Same person?")).toBeTruthy();
    expect(
      container.querySelector(".atlas-suggest-name")?.textContent,
    ).toBe("Dun Duong");
  });

  test("an unrelated name offers no suggestions", () => {
    show([{ _id: "p1", name: "Ada Lovelace" }], "Mai Tran");
    expect(screen.queryByText("Same person?")).toBeNull();
  });

  // S7: Convex's own text search does not typo-match, so a person the sky's
  // recent/search list never surfaced for this exact query still has to be
  // findable -- the suggester's pool is listPersonNames (every one of the
  // caller's people), not searchPeople's query-scoped or 20-capped results.
  test("a typo surfaces a suggestion even when the sky's own search list has nothing for this query", () => {
    people.current = [];
    suggestionPool.current = [
      { _id: "p1", name: "Maya Chen", _creationTime: Date.UTC(2026, 6, 1) },
    ];
    render(
      <SearchAdd
        query="Meya Chen"
        onQueryChange={() => {}}
        onOpen={() => {}}
        onOpenCapture={() => {}}
        morphId={null as Id<"people"> | null}
      />,
    );
    expect(screen.getByText("Same person?")).toBeTruthy();
    expect(screen.getByText("Maya Chen")).toBeTruthy();
  });

  test("clicking a suggestion picks it, and clicking it again unpicks it", () => {
    const { container } = show([{ _id: "p1", name: "Dun Duong" }], "Dun Duogn");
    const row = container.querySelector(".atlas-suggest-row") as HTMLElement;
    expect(row.className).not.toContain("is-picked");
    fireEvent.click(row);
    expect(row.className).toContain("is-picked");
    fireEvent.click(row);
    expect(row.className).not.toContain("is-picked");
  });

  test("picking a suggestion arms attachToPersonId on the save", async () => {
    saved.args = null;
    const { container } = show([{ _id: "p1", name: "Dun Duong" }], "Dun Duogn");
    const row = container.querySelector(".atlas-suggest-row") as HTMLElement;
    fireEvent.click(row);
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "dun.d" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "met at the market" },
    });
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));

    await waitFor(() => {
      expect(saved.args).not.toBeNull();
    });
    expect((saved.args as { attachToPersonId?: string }).attachToPersonId).toBe(
      "p1",
    );
  });

  test("saving without picking a suggestion creates as today", async () => {
    saved.args = null;
    show([{ _id: "p1", name: "Dun Duong" }], "Dun Duogn");
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "dun.d" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "met at the market" },
    });
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));

    await waitFor(() => {
      expect(saved.args).not.toBeNull();
    });
    expect(
      (saved.args as { attachToPersonId?: string }).attachToPersonId,
    ).toBeUndefined();
  });

  // Picking a suggestion is a guess against the currently typed name; a
  // correction to the name must not carry a stale attach into what gets
  // typed next.
  test("changing the name after picking a suggestion clears the pick", async () => {
    saved.args = null;
    const withDunDuong = [
      { _id: "p1", name: "Dun Duong", _creationTime: Date.UTC(2026, 6, 1) },
    ];
    people.current = withDunDuong;
    suggestionPool.current = withDunDuong;
    render(<HostedSearchAdd initial="Dun Duogn" />);
    const row = document.querySelector(".atlas-suggest-row") as HTMLElement;
    fireEvent.click(row);
    fireEvent.change(screen.getByLabelText("name"), {
      target: { value: "Someone Else" },
    });
    fireEvent.click(screen.getByText('Add "Someone Else" to your sky'));
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "someone" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "met at the market" },
    });
    fireEvent.click(screen.getByText('Add "Someone Else" to your sky'));

    await waitFor(() => {
      expect(saved.args).not.toBeNull();
    });
    expect(
      (saved.args as { attachToPersonId?: string }).attachToPersonId,
    ).toBeUndefined();
  });

  test("a conflict with a picked suggestion reports the refusal, not the two-people message", async () => {
    saved.args = null;
    addPersonResult.current = { status: "conflict", personIds: ["p2"] };
    const { container } = show([{ _id: "p1", name: "Dun Duong" }], "Dun Duogn");
    const row = container.querySelector(".atlas-suggest-row") as HTMLElement;
    fireEvent.click(row);
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));
    fireEvent.change(screen.getByLabelText("Their handle there"), {
      target: { value: "dun.d" },
    });
    fireEvent.change(screen.getByLabelText("How you met"), {
      target: { value: "met at the market" },
    });
    fireEvent.click(screen.getByText('Add "Dun Duogn" to your sky'));

    await waitFor(() => {
      expect(screen.getByRole("alert").textContent).toContain(
        "belongs to someone else",
      );
    });
  });
});
