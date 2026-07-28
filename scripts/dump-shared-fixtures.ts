// Dumps the cross-language contract between the TypeScript helpers and their
// Swift ports in ios/Haven/Shared.
//
// The share extension parses a profile URL to decide *identity*: (platform,
// handle) is the dedup key that saveSharedProfile writes. If Swift and
// TypeScript ever disagree about what a URL points at, the result is not a
// visible bug -- it is two rows for one person. So the expected values are
// generated from the real implementations here rather than copied by hand,
// and re-running this after any change to src/lib.ts or convex/nameSearch.ts
// regenerates the vectors the Swift tests assert against.
//
// Usage:
//   npx vite-node scripts/dump-shared-fixtures.ts
// then paste the output over the generated block in
// ios/HavenTests/SharedFixtures.swift.

import { normalizeUrl, parseProfileUrl, nameGuessFromSlug } from "../src/lib";
import { normalizeName } from "../convex/nameSearch";
import { handleDisplayValue, handleValueKey } from "../convex/handleKeys";

// Swift source files in this repo are plain ASCII, so every character outside
// printable ASCII is emitted as a \u{...} escape rather than a literal.
function swiftString(value: string): string {
  let out = '"';
  for (const character of value) {
    const code = character.codePointAt(0) as number;
    if (character === "\\") out += "\\\\";
    else if (character === '"') out += '\\"';
    else if (code >= 0x20 && code <= 0x7e) out += character;
    else out += `\\u{${code.toString(16)}}`;
  }
  return out + '"';
}

function swiftOptionalString(value: string | null): string {
  return value === null ? "nil" : swiftString(value);
}

// Every URL shape the share sheet can be handed, including the three payloads
// captured from the real Instagram, LinkedIn and X apps.
const URL_INPUTS = [
  // The plain profile on each platform.
  "https://instagram.com/mai.makes",
  "https://www.linkedin.com/in/mai-tran-8a91b2",
  "https://x.com/mai_makes",
  "https://twitter.com/mai_makes",
  // Real share payloads, captured from the apps on 2026-07-27. X hands over a
  // URL with no scheme at all.
  "x.com/mai_makes?s=11",
  "https://www.linkedin.com/in/mai-tran-8a91b2?utm_source=share_via&utm_content=profile&utm_medium=member_ios",
  "https://www.instagram.com/mai.makes/?igsh=MXc4b2k5",
  // Host and scheme variants share sheets actually produce.
  "https://www.instagram.com/mai.makes/",
  "https://m.instagram.com/mai.makes",
  "https://mobile.twitter.com/mai_makes",
  "HTTPS://WWW.Instagram.COM/MaiMakes",
  "http://x.com/mai_makes",
  "  instagram.com/mai.makes  ",
  "https://vn.linkedin.com/in/mai-tran-8a91b2",
  "https://uk.linkedin.com/in/mai-tran-8a91b2",
  "https://de.linkedin.com/in/mai-tran-8a91b2",
  "https://www.linkedin.com/mwlite/in/mai-tran-8a91b2",
  // Tracking noise and fragments.
  "https://instagram.com/mai.makes/?igsh=abc123&utm=share",
  "https://www.linkedin.com/in/mai-tran-8a91b2/#profile",
  // A leading @, and a handle that is nothing but @.
  "https://x.com/@MaiMakes",
  "https://x.com/@",
  // A post under a handle is content, not the profile.
  "https://x.com/mai_makes/status/17999",
  "https://x.com/mai_makes/%73tatus/17999",
  "https://instagram.com/mai.makes/p/Cxyz123",
  "https://instagram.com/mai.makes/reel/Cxyz123/",
  // Reserved Instagram surfaces.
  "https://instagram.com/p/Cxyz123",
  "https://instagram.com/reel/Cxyz123",
  "https://instagram.com/reels/Cxyz123",
  "https://instagram.com/stories/mai.makes/123",
  "https://instagram.com/tv/Cxyz123",
  "https://instagram.com/explore/tags/hanoi",
  "https://instagram.com/accounts/login",
  "https://instagram.com/direct/inbox",
  "https://instagram.com/about",
  // Reserved X surfaces.
  "https://x.com/i/flow/login",
  "https://x.com/home",
  "https://x.com/explore",
  "https://x.com/search?q=hanoi",
  "https://x.com/intent/follow",
  "https://x.com/hashtag/hanoi",
  "https://x.com/messages",
  "https://x.com/notifications",
  "https://x.com/settings/account",
  "https://x.com/compose/tweet",
  "https://x.com/share",
  // Reserved segments match whole and case-insensitively; a handle that only
  // starts with a reserved word is still a person.
  "https://instagram.com/REEL/Cxyz123",
  "https://x.com/I/flow/login",
  "https://x.com/ihateflying",
  "https://instagram.com/pho.reels",
  // Percent-encoding must not smuggle a reserved segment or a second path
  // segment past the checks.
  "https://instagram.com/%70/Cxyz123",
  "https://x.com/%69/flow/login",
  "https://instagram.com/mai%2Fmakes",
  // A deeper profile tab still identifies the person.
  "https://www.linkedin.com/in/mai-tran-8a91b2/details/experience/",
  "https://instagram.com/mai.makes/tagged/",
  // LinkedIn profiles live only under /in/.
  "https://www.linkedin.com/company/convex",
  "https://www.linkedin.com/posts/mai-tran-abc",
  "https://www.linkedin.com/pub/mai-tran",
  "https://www.linkedin.com/feed/",
  "https://www.linkedin.com/jobs/view/123",
  "https://www.linkedin.com/in/",
  // Percent-decoded accents, and malformed encoding that must not throw.
  "https://www.linkedin.com/in/nguy%E1%BB%85n-mai",
  "https://www.linkedin.com/in/%E0%A4%A",
  "https://instagram.com/%E0%A4%A",
  // Dot segments: the URL parser collapses these before the path is read, so
  // the Swift port has to as well or the handle it reads is a different one.
  "https://instagram.com/./mai.makes",
  "https://instagram.com/a/../mai.makes",
  "https://x.com/mai_makes/./status/17999",
  // A dot segment is still one when it is percent-encoded, so the collapse
  // has to happen before the segments are decoded, not after.
  "https://instagram.com/%2e/mai.makes",
  "https://instagram.com/a/%2E%2E/mai.makes",
  // Host case, and hosts that only look like ours.
  "https://INSTAGRAM.COM/mai.makes",
  "https://Instagram.com/mai.makes",
  "https://WWW.instagram.COM/mai.makes",
  "https://notinstagram.com/mai",
  "https://evil.example/instagram.com/mai",
  "instagram.com/mai.makes",
  // More than one leading @, and a handle that is nothing but them.
  "https://x.com/@@MaiMakes",
  "https://x.com/@@@",
  // Not one person's profile at all.
  "https://facebook.com/mai",
  "https://instagram.com.evil.example/mai",
  "https://instagram.com/",
  "https://x.com",
  "met at the conference",
  "",
  "   ",
  "ftp://instagram.com/mai.makes",
  "https://example.com/a",
  "http://example.com",
  "linkedin.com/in/tony",
  "  https://a.com  ",
  // Handles deriveProfileUrl round-trips, which the web card builds.
  "https://x.com/mai.makes",
  "https://x.com/ada_l",
  "https://x.com/caf%C3%A9",
  "https://instagram.com/ada_l",
  "https://instagram.com/caf%C3%A9",
];

const SLUG_INPUTS = [
  "mai-tran-8a91b2",
  "john-doe",
  "m3-tran-8a91b2",
  "nguyễn-mai-8a91b2",
  "đức-anh",
  "8a91b2",
  "8a91b2-7c4d",
  "",
  "   ",
  "---",
  "mai--tran-",
  // Known and deliberate: a trailing segment that mixes letters and digits is
  // dropped whole, so this loses "name". A rule loose enough to keep it would
  // also keep the common hex suffix. The user confirms the field, and the
  // ports must be wrong in exactly the same way.
  "first-last-name216",
  "mai.makes",
  "MaiMakes",
  // JS \d is ASCII only, so an Arabic-Indic numeral is part of the name, not
  // the id junk. Swift's CharacterSet.decimalDigits would disagree.
  "mai-tran-١٢",
];

const NAME_INPUTS = [
  "Mai Tran",
  "MAI  TRAN",
  "  Nguyễn Mai  ",
  "Đà Nẵng",
  "đức anh",
  "Café",
  "",
  "   ",
  "Dun\tDun",
  "José García",
  // Lowercasing this yields an i plus a combining dot, which the mark strip
  // then removes -- but only if both ports fold before they decompose.
  "İstanbul",
  // Non-breaking space and the other separators JS \s matches.
  "Mai Tran",
  "Mai Tran",
  "Mai　Tran",
  "Mai﻿Tran",
  "MaiTran",
];

// The shapes one account arrives in. Two of these have to collapse to one
// identity or a re-share creates a twin.
const HANDLE_INPUTS = [
  "mai.makes",
  "@mai.makes",
  "@@mai.makes",
  "  @Mai.Makes  ",
  "MAI_MAKES",
  "mai-tran-8a91b2",
  "@",
  "",
  "   ",
  "café",
  "CAFÉ",
];

const lines: string[] = [];

lines.push("let normalizeUrlCases: [(input: String, want: String?)] = [");
for (const input of URL_INPUTS) {
  lines.push(
    `    (${swiftString(input)}, ${swiftOptionalString(normalizeUrl(input))}),`,
  );
}
lines.push("]");
lines.push("");

lines.push(
  "let parseProfileUrlCases: [(input: String, want: ProfileLink?)] = [",
);
for (const input of URL_INPUTS) {
  const parsed = parseProfileUrl(input);
  const want =
    parsed === null
      ? "nil"
      : `ProfileLink(platform: .${parsed.platform}, handle: ${swiftString(parsed.handle)})`;
  lines.push(`    (${swiftString(input)}, ${want}),`);
}
lines.push("]");
lines.push("");

lines.push("let nameGuessCases: [(slug: String, want: String)] = [");
for (const slug of SLUG_INPUTS) {
  lines.push(`    (${swiftString(slug)}, ${swiftString(nameGuessFromSlug(slug))}),`);
}
lines.push("]");
lines.push("");

lines.push("let foldNameCases: [(input: String, want: String)] = [");
for (const name of NAME_INPUTS) {
  lines.push(`    (${swiftString(name)}, ${swiftString(normalizeName(name))}),`);
}
lines.push("]");
lines.push("");

lines.push(
  "let handleKeyCases: [(input: String, display: String, key: String)] = [",
);
for (const value of HANDLE_INPUTS) {
  lines.push(
    `    (${swiftString(value)}, ${swiftString(handleDisplayValue(value))}, ${swiftString(handleValueKey(value))}),`,
  );
}
lines.push("]");

console.log(lines.join("\n"));
