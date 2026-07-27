// The folding rules behind handle identity, in one importable module because
// every write path that touches contactHandles or personHandles has to fold
// alike or the same account lands on two people. Deliberately free of Convex
// imports: this is pure string work, so people, profiles and captures can all
// depend on it without dragging a function registration along.

// The display shape of a shared handle: what renders on the card. In
// lockstep with handleValueKey below, so handles that dedup alike always
// render alike.
export function handleDisplayValue(value: string): string {
  return value.trim().replace(/^@+/, "");
}

// The identity key behind a handle: the same account shared as "@Mai.Makes"
// and as "mai.makes" has to resolve to one person. Deliberately naive in v1;
// per-platform rules can grow here later.
export function handleValueKey(value: string): string {
  return handleDisplayValue(value).toLowerCase();
}

// The personHandles shape for one contactHandles entry. Legacy rows can hold
// an unnormalized platform, so the index row folds it the same way
// validateContactHandles does rather than trusting what is stored.
export function handleIndexKeys(handle: {
  platform: string;
  value: string;
}): {
  platform: string;
  valueKey: string;
} {
  return {
    platform: handle.platform.trim().toLowerCase(),
    valueKey: handleValueKey(handle.value),
  };
}
