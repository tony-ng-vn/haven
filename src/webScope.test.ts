import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

// What the web is for, encoded so it cannot drift back.
//
// iOS is the primary Haven client. The web is the front door and the viewing
// surface: the waitlist and sign-in, your network as a sky, search, adding
// somebody by typing their name, the public card a stranger opens, and the
// legal and support pages. Ways of MEETING people -- exchanging contact in
// person, proximity radar -- are things you do with a phone in your hand, and
// they live in the iPhone app.
//
// This is a scope test, not a style test. It fails when a feature that belongs
// on the phone grows a web UI again, which is how the two clients quietly
// became two half-products the first time.

const sources = readdirSync("src").filter(
  (name) => /\.(ts|tsx)$/.test(name) && !name.includes(".test."),
);

function sourceText(name: string): string {
  return readFileSync(join("src", name), "utf8");
}

describe("the web stays a front door and a viewer", () => {
  test("no in-person contact exchange", () => {
    // profiles.connect and profiles.setUsername still exist on the backend --
    // the iPhone app calls them (ios/Haven/Connect/ConnectModel.swift). What
    // must not come back is a web UI for them.
    for (const name of sources) {
      const source = sourceText(name);
      expect(source, `${name} calls profiles.connect`).not.toMatch(
        /api\.profiles\.connect/,
      );
      expect(source, `${name} calls profiles.setUsername`).not.toMatch(
        /api\.profiles\.setUsername/,
      );
    }
  });

  test("no proximity radar", () => {
    // The loveAlarm tables, functions and sweep cron are untouched; only the
    // web panel is gone. Whether the feature lives at all is decision D1 in
    // docs/superpowers/plans/2026-07-28-backend-completion-plan.md.
    for (const name of sources) {
      expect(sourceText(name), `${name} calls loveAlarm`).not.toMatch(
        /api\.loveAlarm/,
      );
    }
  });

  test("nothing asks the browser to listen or locate", () => {
    // Speech recognition came in with the Meet sheet; geolocation would come
    // in with a radar. Both are permission prompts a viewing surface has no
    // business raising.
    for (const name of sources) {
      const source = sourceText(name);
      expect(source, `${name} uses SpeechRecognition`).not.toMatch(
        /SpeechRecognition/,
      );
      expect(source, `${name} uses geolocation`).not.toMatch(
        /navigator\.geolocation/,
      );
    }
  });

  test("the surfaces the web does own are still here", () => {
    // The other half of the rule: this list is what the web IS, so a cleanup
    // pass cannot quietly take one of these away either.
    const present = sources.join(" ");
    for (const surface of [
      "Waitlist.tsx", // the front door
      "SearchAdd.tsx", // your network as a sky, search, add by name
      "PersonDetail.tsx", // one person's page
      "CardPage.tsx", // the public card a stranger opens
      "LegalPage.tsx",
      "SupportPage.tsx",
    ]) {
      expect(present, `${surface} is missing`).toContain(surface);
    }
  });
});
