// @vitest-environment happy-dom
import { afterEach, describe, expect, test, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import type { Id } from "../convex/_generated/dataModel";

// The sky reads one query twice (the stable field, and the live name search)
// and both are answered with the same list here: what these tests are about is
// the add form and what it is allowed to share a screen with, not search.
const people = vi.hoisted(() => ({ current: [] as unknown[] }));
const saved = vi.hoisted(() => ({ args: null as unknown }));
vi.mock("convex/react", () => ({
  useQuery: () => people.current,
  useMutation: () => async (args: unknown) => {
    saved.args = args;
    return "p9";
  },
  useAction: () => async () => [],
}));

const { SearchAdd } = await import("./SearchAdd");

afterEach(cleanup);

function show(field: { _id: string; name: string }[], query = "Mai") {
  people.current = field.map((p) => ({ ...p, _creationTime: Date.UTC(2026, 6, 1) }));
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
