// The folding rules behind handle identity, in one importable module because
// every write path that touches contactHandles or personHandles has to fold
// alike or the same account lands on two people. Free of Convex imports
// (libphonenumber-js aside): this is pure string work, so people, profiles
// and captures can all depend on it without dragging a function registration
// along.

import { parsePhoneNumberFromString } from "libphonenumber-js";

// The display shape of a shared handle: what renders on the card. In
// lockstep with handleValueKey below, so handles that dedup alike always
// render alike.
export function handleDisplayValue(value: string): string {
  return value.trim().replace(/^@+/, "");
}

const PHONE_PLATFORMS = new Set(["phone", "whatsapp"]);

// Whether a platform string names a number rather than a handle. Exported so
// every write gate that cares about phone-shaped values (the digit
// requirement below, reach.ts's client mirror) asks the one place that knows
// which platforms these are, rather than re-listing "phone"/"whatsapp".
export function isPhoneNumberPlatform(platform: string): boolean {
  return PHONE_PLATFORMS.has(platform.trim().toLowerCase());
}

// A phone/whatsapp value with no digit at all -- "unknown", "ask mai", a
// screenshot's OCR miss -- folds through phoneValueKey's own fallback to a
// plain lowercase string (see its comment above), which two DIFFERENT
// unreadable values ("Unknown" from one capture, "unknown" from another) can
// still collide on and silently merge two strangers. The fold itself stays
// total, because legacy rows already written this way still have to resolve
// to something -- this is for a write gate to refuse a NEW digitless value
// before it is ever folded, not for the fold to start throwing.
export function hasPhoneDigit(value: string): boolean {
  return /[0-9]/.test(value);
}

// The fallback fold for a number with no country-code evidence: digits
// alone, formatting stripped. graph/ hardcodes a US default region for its
// one-person personal import (JOURNAL.md); Convex serves every user's data
// from one process, so a server-side default region is a guess this app has
// no basis for, and an under-specified value folds to what it unambiguously
// is instead -- never a guessed +1.
function digitsOnlyKey(value: string): string {
  return value.replace(/[^0-9]/g, "");
}

// The phone/whatsapp fold: parsePhoneNumberFromString with no default region
// only resolves a number when the string itself carries the country code (a
// leading "+"), so this can never guess one -- a bare local number falls
// through to digitsOnlyKey instead. A value with no digits at all -- "call
// me", a screenshot's OCR miss -- is not a number Haven can fold this way;
// digitsOnlyKey would flatten it to "", and every unreadable entry for one
// user's phone platform would then collide on that one empty key. Falling
// back to the plain fold for those keeps the pre-existing behavior: two
// unreadable pastes stay two identities.
function phoneValueKey(value: string): string {
  const parsed = parsePhoneNumberFromString(value);
  if (parsed !== undefined && parsed.isValid()) {
    return parsed.number;
  }
  const digits = digitsOnlyKey(value);
  return digits === "" ? value.toLowerCase() : digits;
}

// The identity key behind a handle: the same account shared as "@Mai.Makes"
// and as "mai.makes" has to resolve to one person. Platform-aware only for
// phone and whatsapp: a number carrying a country code is stored as E.164,
// while a plain national number has formatting stripped but is never given a
// guessed region. Every other platform keeps the plain trim/strip-@/lowercase
// fold.
export function handleValueKey(value: string, platform?: string): string {
  const display = handleDisplayValue(value);
  if (platform !== undefined && PHONE_PLATFORMS.has(platform)) {
    return phoneValueKey(display);
  }
  return display.toLowerCase();
}

// The personHandles shape for one contactHandles entry. Legacy rows can hold
// an unnormalized platform, so the index row folds it the same way
// validateContactHandles does rather than trusting what is stored.
// platformId is opaque -- a platform's own id, not a display value -- so it
// passes through unfolded, the same way source and addedAt pass through
// validateContactHandles rather than being derived here.
export function handleIndexKeys(handle: {
  platform: string;
  value: string;
  platformId?: string;
}): {
  platform: string;
  valueKey: string;
  platformId?: string;
} {
  const platform = handle.platform.trim().toLowerCase();
  return {
    platform,
    valueKey: handleValueKey(handle.value, platform),
    platformId: handle.platformId,
  };
}
