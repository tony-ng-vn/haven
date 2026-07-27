import { afterEach, expect, test, vi } from "vitest";
import { embedText, extractProfile } from "./openaiClient";

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
