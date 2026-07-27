// Live recall for people:ask, run by hand rather than in CI: model output is
// not deterministic enough to gate a merge on, but "did the last prompt edit
// make this better or worse" is unanswerable without a number.
//
//   OPENAI_API_KEY=sk-... node scripts/eval-ask.ts
//   ASK_BASE_URL=https://api.interfaze.ai ASK_API_KEY=... ASK_MODEL=interfaze-beta \
//     node scripts/eval-ask.ts
//
// Node 24+ strips the types, so there is nothing to install. It talks to the
// provider directly and never touches a Convex deployment, because the
// fixtures carry their own prebuilt networks.

import { ASK_FIXTURES, type AskFixture } from "../src/askFixtures.ts";
import { askNetwork, type AskAnswer } from "../convex/openaiClient.ts";

// Each fixture runs this many times. One sample cannot tell a prompt that is
// reliably right from one that got lucky, and that difference is the only
// reason to measure at all.
const RUNS_PER_FIXTURE = Number(process.env.EVAL_RUNS ?? "3");

type Outcome = {
  fixture: AskFixture;
  run: number;
  hit: boolean;
  detail: string;
};

function grade(fixture: AskFixture, answer: AskAnswer): {
  hit: boolean;
  detail: string;
} {
  const got = answer.matches.map((match) => `#${match.ref} ${match.kind}`);
  if (fixture.expectClarification === true) {
    const asked = answer.clarifyingQuestion !== undefined;
    return {
      hit: asked && answer.matches.length === 0,
      detail: asked ? `asked: ${answer.clarifyingQuestion}` : `guessed: ${got.join(", ")}`,
    };
  }
  if (fixture.expected.length === 0) {
    return {
      hit: answer.matches.length === 0,
      detail: answer.matches.length === 0 ? "named nobody" : `named ${got.join(", ")}`,
    };
  }
  // Kind matters as much as identity: a bridge returned as a direct match is
  // the specific failure this feature is most likely to be trusted through.
  const missing = fixture.expected.filter(
    (want) =>
      !answer.matches.some(
        (match) => match.ref === want.ref && match.kind === want.kind,
      ),
  );
  return {
    hit: missing.length === 0,
    detail:
      missing.length === 0
        ? `found ${got.join(", ")}`
        : `missing ${missing.map((m) => `#${m.ref} ${m.kind}`).join(", ")}; got ${got.join(", ") || "nothing"}`,
  };
}

const outcomes: Outcome[] = [];
for (const fixture of ASK_FIXTURES) {
  for (let run = 1; run <= RUNS_PER_FIXTURE; run++) {
    try {
      const answer = await askNetwork(fixture.query, fixture.network, []);
      const { hit, detail } = grade(fixture, answer);
      outcomes.push({ fixture, run, hit, detail });
    } catch (error) {
      // A provider failure is a failed run, not a crashed eval: the other
      // cases still carry information.
      outcomes.push({
        fixture,
        run,
        hit: false,
        detail: `error: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  }
}

let passed = 0;
for (const fixture of ASK_FIXTURES) {
  const runs = outcomes.filter((outcome) => outcome.fixture === fixture);
  const hits = runs.filter((outcome) => outcome.hit).length;
  passed += hits;
  console.log(`\n${hits}/${runs.length}  ${fixture.name}`);
  console.log(`         query: ${fixture.query}`);
  console.log(`         why it matters: ${fixture.why}`);
  for (const run of runs) {
    console.log(`         run ${run.run}: ${run.hit ? "ok" : "MISS"} -- ${run.detail}`);
  }
}

const total = outcomes.length;
console.log(
  `\nrecall ${passed}/${total} (${Math.round((passed / total) * 100)}%) over ${ASK_FIXTURES.length} cases x ${RUNS_PER_FIXTURE} runs`,
);
// Non-zero on any miss, so this can gate a prompt change without anyone
// having to read the output.
process.exit(passed === total ? 0 : 1);
