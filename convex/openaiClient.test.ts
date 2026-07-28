import { afterEach, expect, test, vi } from "vitest";
import { askNetwork, embedText, extractProfile } from "./openaiClient";

type SeenRequest = { url: string; auth: string | undefined; model: string };

// Records every outbound request instead of routing by host: these tests are
// about WHERE each call goes and WHICH credentials ride along.
function stubProviders(): SeenRequest[] {
  const seen: SeenRequest[] = [];
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      const headers = (init?.headers ?? {}) as Record<string, string>;
      const body = JSON.parse(String(init?.body)) as { model: string };
      seen.push({ url, auth: headers.Authorization, model: body.model });
      if (url.includes("/chat/completions")) {
        // Both chat callers read choices[0].message.content, and each parses
        // only the fields its own schema declares, so one reply serves both.
        return Response.json({
          choices: [
            {
              message: {
                content: JSON.stringify({
                  is_profile: true,
                  platform: "x",
                  name: "Ada Lovelace",
                  handle: null,
                  headline: null,
                  bio: null,
                  matches: [],
                  clarifying_question: null,
                }),
              },
            },
          ],
        });
      }
      return Response.json({ data: [{ embedding: [0.1] }] });
    },
  );
  return seen;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

test("extraction and embeddings default to OpenAI", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  const seen = stubProviders();

  await extractProfile("https://img.example/shot.png");
  await embedText("ada");

  expect(seen).toEqual([
    {
      url: "https://api.openai.com/v1/chat/completions",
      auth: "Bearer sk-openai",
      model: "gpt-4o-mini",
    },
    {
      url: "https://api.openai.com/v1/embeddings",
      auth: "Bearer sk-openai",
      model: "text-embedding-3-small",
    },
  ]);
});

// Measured against Interfaze on 2026-07-27 with four real profile
// screenshots: "high" sent the model into a long reasoning pass (up to 17k
// completion tokens for a six-field answer, ~$0.07 a capture) and "low"
// returned the same fields for roughly half that. Handle accuracy was
// identical on the two screenshots that carried one, decoy handles in the
// bio included. Pinned here because the saving is invisible in the response
// and a future edit could restore it without anything failing.
test("extraction asks for the cheap image detail", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  let detail: string | undefined;
  vi.stubGlobal("fetch", async (_input: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body)) as {
      messages: Array<{ content: Array<{ image_url?: { detail?: string } }> }>;
    };
    detail = body.messages[0].content.find((part) => part.image_url !== undefined)
      ?.image_url?.detail;
    return Response.json({
      choices: [{ message: { content: JSON.stringify({
        is_profile: true, platform: "x", name: "Ada Lovelace",
        handle: null, headline: null, bio: null,
      }) } }],
    });
  });

  await extractProfile("https://img.example/shot.png");

  expect(detail).toBe("low");
});

test("EXTRACTION_* env moves extraction while embeddings stay on OpenAI", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  vi.stubEnv("EXTRACTION_BASE_URL", "https://api.interfaze.ai");
  vi.stubEnv("EXTRACTION_API_KEY", "ifz-key");
  vi.stubEnv("EXTRACTION_MODEL", "interfaze-beta");
  const seen = stubProviders();

  await extractProfile("https://img.example/shot.png");
  await embedText("ada");

  expect(seen).toEqual([
    {
      url: "https://api.interfaze.ai/v1/chat/completions",
      auth: "Bearer ifz-key",
      model: "interfaze-beta",
    },
    // The vector index stores 1536-dim text-embedding-3-small vectors, so
    // embeddings must not follow the extraction provider.
    {
      url: "https://api.openai.com/v1/embeddings",
      auth: "Bearer sk-openai",
      model: "text-embedding-3-small",
    },
  ]);
});

test("a custom extraction base URL brings its own key and model", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  vi.stubEnv("EXTRACTION_BASE_URL", "https://api.interfaze.ai");
  vi.stubEnv("EXTRACTION_MODEL", "interfaze-beta");
  const seen = stubProviders();

  // The OpenAI bearer must never be handed to a third-party host.
  await expect(extractProfile("https://img.example/shot.png")).rejects.toThrow(
    "EXTRACTION_API_KEY",
  );
  expect(seen).toEqual([]);

  vi.stubEnv("EXTRACTION_API_KEY", "ifz-key");
  vi.stubEnv("EXTRACTION_MODEL", "");
  // A provider swap without a model would send it a model it may not serve.
  await expect(extractProfile("https://img.example/shot.png")).rejects.toThrow(
    "EXTRACTION_MODEL",
  );
  expect(seen).toEqual([]);
});

test("EXTRACTION_MODEL alone swaps the model but stays on OpenAI", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  vi.stubEnv("EXTRACTION_MODEL", "gpt-5-mini");
  const seen = stubProviders();

  await extractProfile("https://img.example/shot.png");

  expect(seen).toEqual([
    {
      url: "https://api.openai.com/v1/chat/completions",
      auth: "Bearer sk-openai",
      model: "gpt-5-mini",
    },
  ]);
});

// ------------------------------------------------------------------- ask

test("ask defaults to OpenAI and moves independently of extraction", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  vi.stubEnv("EXTRACTION_BASE_URL", "https://api.interfaze.ai");
  vi.stubEnv("EXTRACTION_API_KEY", "ifz-key");
  vi.stubEnv("EXTRACTION_MODEL", "interfaze-beta");
  const seen = stubProviders();

  await askNetwork("who knows databases", "#1 Ada Lovelace", []);

  // Reading a screenshot and reasoning over a network are different jobs, so
  // pointing extraction at another host must not drag ask along with it.
  expect(seen).toEqual([
    {
      url: "https://api.openai.com/v1/chat/completions",
      auth: "Bearer sk-openai",
      model: "gpt-4o-mini",
    },
  ]);
});

test("ASK_* env moves ask and brings its own key and model", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  vi.stubEnv("ASK_BASE_URL", "https://api.interfaze.ai");
  const seen = stubProviders();

  // The OpenAI bearer must never be handed to a third-party host.
  await expect(askNetwork("q", "#1 Ada", [])).rejects.toThrow("ASK_API_KEY");
  vi.stubEnv("ASK_API_KEY", "ifz-key");
  // A provider swap without a model would send it a model it may not serve.
  await expect(askNetwork("q", "#1 Ada", [])).rejects.toThrow("ASK_MODEL");
  expect(seen).toEqual([]);

  vi.stubEnv("ASK_MODEL", "interfaze-beta");
  await askNetwork("q", "#1 Ada", []);

  expect(seen).toEqual([
    {
      url: "https://api.interfaze.ai/v1/chat/completions",
      auth: "Bearer ifz-key",
      model: "interfaze-beta",
    },
  ]);
});

// A model with no definition of "headline" fills it with whatever sits under
// the name, which on Instagram is the bio's linked account (PR 104's noted
// concern). headline is not an identity field, so nothing breaks -- but it is
// in the keyword haystack and in the embedding, so the wrong text there makes
// a person findable by somebody else's account name.
test("extraction says what a headline is on a platform that has none", async () => {
  vi.stubEnv("OPENAI_API_KEY", "sk-openai");
  const bodies: string[] = [];
  vi.stubGlobal("fetch", async (_input: RequestInfo | URL, init?: RequestInit) => {
    bodies.push(String(init?.body));
    return Response.json({
      choices: [
        {
          message: {
            content: JSON.stringify({
              is_profile: true,
              platform: "instagram",
              name: "Ada Lovelace",
              handle: null,
              headline: null,
              bio: null,
            }),
          },
        },
      ],
    });
  });

  await extractProfile("https://img.example/shot.png");

  const sent = JSON.parse(bodies[0]) as {
    response_format: {
      json_schema: {
        schema: { properties: { headline: { description: string } } };
      };
    };
  };
  const headline = sent.response_format.json_schema.schema.properties.headline;
  // The instruction has to reach the model, not just the source file.
  expect(headline.description).toMatch(/Instagram/);
  expect(headline.description).toMatch(/null/);
  expect(headline.description).toMatch(/bio/);
});
