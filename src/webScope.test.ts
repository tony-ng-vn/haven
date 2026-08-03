import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

// What the web is for, encoded so it cannot drift back.
//
// iOS is the primary Haven client. The web is the front door and the viewing
// surface: the Haven landing and sign-in, the Sky and iOS product pages
// (which carries the waitlist signup), your network as a sky, search, adding
// somebody by typing their name, the public card a stranger opens, and the
// legal and support pages. Ways of MEETING people -- exchanging contact in
// person, proximity radar -- are things you do with a phone in your hand, and
// they live in the iPhone app.
//
// This is a scope test, not a style test. It fails when a feature that belongs
// on the phone grows a web UI again, which is how the two clients quietly
// became two half-products the first time.

// Recursive on purpose. src/ is flat today, so this finds the same files a
// plain readdir would -- but the day somebody adds src/meet/ is exactly the
// day these guards must not go blind.
function sourceFiles(dir = "src"): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return sourceFiles(path);
    if (!/\.(ts|tsx)$/.test(entry.name) || entry.name.includes(".test.")) {
      return [];
    }
    return [path];
  });
}

const sources = sourceFiles().map((path) => path.replace(/^src\//, ""));

function sourceText(name: string): string {
  return readFileSync(join("src", name), "utf8");
}

// Matches api.profiles.connect and api["profiles"]["connect"] alike: the guard
// should not be defeatable by respelling the same call.
function apiCall(...path: string[]): RegExp {
  const step = (name: string) =>
    `(?:\\.${name}\\b|\\[\\s*["'\`]${name}["'\`]\\s*\\])`;
  return new RegExp(`\\bapi${path.map(step).join("")}`);
}

describe("the web stays a front door and a viewer", () => {
  test("no in-person contact exchange", () => {
    // profiles.connect and profiles.setUsername still exist on the backend --
    // the iPhone app calls them (ios/Haven/Connect/ConnectModel.swift). What
    // must not come back is a web UI for them.
    for (const name of sources) {
      const source = sourceText(name);
      expect(source, `${name} calls profiles.connect`).not.toMatch(
        apiCall("profiles", "connect"),
      );
      expect(source, `${name} calls profiles.setUsername`).not.toMatch(
        apiCall("profiles", "setUsername"),
      );
    }
  });

  test("no proximity radar", () => {
    // The loveAlarm tables, functions and sweep cron are untouched; only the
    // web panel is gone. Whether the feature lives at all is decision D1 in
    // docs/superpowers/plans/2026-07-28-backend-completion-plan.md.
    for (const name of sources) {
      expect(sourceText(name), `${name} calls loveAlarm`).not.toMatch(
        apiCall("loveAlarm"),
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

  test("the surfaces the web does own are still here, and still routed", () => {
    // The other half of the rule: this list is what the web IS, so a cleanup
    // pass cannot quietly take one of these away either.
    //
    // Both halves are load-bearing. Existing as a file is not the same as
    // being reachable, and a surface nothing renders is gone as far as anyone
    // visiting the site is concerned -- so the component has to be mounted in
    // App.tsx too, not merely present on disk.
    const app = readFileSync(join("src", "App.tsx"), "utf8");
    for (const surface of [
      "LandingPage", // the front door
      "SkyPage", // Your Sky for Mac, the download landing
      "IosPage", // Haven for iPhone, the waitlist landing
      "SearchAdd", // your network as a sky, search, add by name
      "PersonDetail", // one person's page
      "CardPage", // the public card a stranger opens
      "LegalPage",
      "SupportPage",
    ]) {
      // Array membership, not a substring of the joined list: "HomeWaitlist"
      // must not satisfy "Waitlist".
      expect(sources, `${surface}.tsx is missing`).toContain(`${surface}.tsx`);
      expect(app, `${surface} is never rendered`).toMatch(
        new RegExp(`<${surface}[\\s/>]`),
      );
    }
  });
});
