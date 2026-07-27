// The evaluation set for people:ask, shared on purpose: CI checks the
// contract against a mocked provider, and scripts/eval-ask.ts runs these same
// cases against the live model to report recall. Two copies of the cases
// would drift, and then neither number would mean anything.
//
// Each network is a prebuilt dossier block in the exact shape buildDossier
// produces, so a fixture needs no database.

export type AskFixture = {
  name: string;
  network: string;
  query: string;
  // Which refs the model should name, and how. An empty list means the right
  // answer is to name nobody.
  expected: Array<{ ref: number; kind: "direct" | "bridge" }>;
  // True when the honest answer is a question rather than a guess.
  expectClarification?: boolean;
  why: string;
};

const NETWORK = [
  `#1 Ada Lovelace | Compiler engineer at Analytical Engines | Sai Gon | x
Building symbolic math tools.
- 2026-05-02: met at the Founder Inc dinner
- 2026-05-04: works on an infinite-context-window database, says the index is the hard part`,
  `#2 Grace Hopper | Designer at Pixel Foundry | Ha Noi | instagram
- 2026-04-11: does brand identity work, mostly for restaurants`,
  `#3 Alan Turing | Analyst at Y Combinator | San Francisco | linkedin
- 2026-06-01: screens applications for the winter batch`,
  `#4 Katherine Johnson | Ha Noi | instagram
- 2026-03-20: chi ay lam ve du lieu ve khi hau, dang tim nguoi lam backend`,
].join("\n\n");

export const ASK_FIXTURES: AskFixture[] = [
  {
    name: "direct match on a memory line, not a card field",
    network: NETWORK,
    query: "do I know anyone with database experience",
    expected: [{ ref: 1, kind: "direct" }],
    why: "Nothing in Ada's card says 'database'. Only the note does, which is the whole point of the memory substrate.",
  },
  {
    name: "bridge when nobody fits directly",
    network: NETWORK,
    query: "I need to talk to a startup founder",
    expected: [{ ref: 3, kind: "bridge" }],
    why: "Nobody here is a founder. Alan screens YC applications, so he is a route to one -- and it must come back labelled bridge, not dressed up as a direct match.",
  },
  {
    name: "Vietnamese note answers an English query",
    network: NETWORK,
    query: "who works on climate data",
    expected: [{ ref: 4, kind: "direct" }],
    why: "The note is unaccented Vietnamese and the question is English. The user's network is mostly Vietnamese, so this is the common case, not an edge one.",
  },
  {
    name: "a vague ask gets a question, not a guess",
    network: NETWORK,
    query: "who should I talk to",
    expected: [],
    expectClarification: true,
    why: "There is no need stated. Guessing here is how the feature earns distrust.",
  },
  {
    name: "nobody matches and nobody is invented",
    network: NETWORK,
    query: "do I know a commercial airline pilot",
    expected: [],
    why: "Empty is the correct answer. A model that pads this with the nearest person is worse than one that says nothing.",
  },
];
