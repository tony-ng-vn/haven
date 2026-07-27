// Plain helpers for the two model endpoints Haven uses (OpenAI-compatible;
// extraction can run on another provider, see extractionConfig). Not
// registered Convex functions; call these only from actions (they do network
// IO). fetch is available in the default Convex runtime, so no "use node".

export type ExtractedProfile = {
  platform: string;
  name: string;
  handle?: string;
  headline?: string;
  bio?: string;
};

const PLATFORMS = [
  "linkedin",
  "x",
  "instagram",
  "tiktok",
  "github",
  "facebook",
  "threads",
  "bluesky",
  "other",
] as const;

// Strict structured-output schema: every property listed in required,
// optionality expressed as nullable types, per OpenAI strict mode rules.
const EXTRACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["is_profile", "platform", "name", "handle", "headline", "bio"],
  properties: {
    is_profile: {
      type: "boolean",
      description:
        "True only if the screenshot shows a single person's social or professional profile.",
    },
    platform: { type: "string", enum: [...PLATFORMS] },
    name: {
      type: ["string", "null"],
      description: "The person's display name as shown.",
    },
    handle: {
      type: ["string", "null"],
      description: "The username or @handle if visible, without the URL.",
    },
    headline: {
      type: ["string", "null"],
      description: "Their title, tagline, or one-line bio header if visible.",
    },
    bio: {
      type: ["string", "null"],
      description: "A short summary of any visible bio or about text.",
    },
  },
} as const;

const EXTRACTION_PROMPT = [
  "This is a screenshot the user took of someone's social or professional profile.",
  "Identify which platform it is from (branding, layout, UI chrome) and extract",
  "the person's visible details. Only report what is actually visible; never",
  "guess a handle or invent text. If the image is not a person's profile,",
  "set is_profile to false.",
].join(" ");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(
      `${name} is not set on the Convex deployment. Run: npx convex env set ${name} <value>`,
    );
  }
  return value;
}

type Provider = { label: string; baseUrl: string; key: string };

function openaiProvider(): Provider {
  return {
    label: "OpenAI",
    baseUrl: process.env.OPENAI_BASE_URL ?? "https://api.openai.com",
    key: requireEnv("OPENAI_API_KEY"),
  };
}

// The two chat-completions callers are provider-swappable via
// <PREFIX>_BASE_URL / _API_KEY / _MODEL (any OpenAI-compatible API; we point
// extraction at interfaze.ai to spend credit there). Embeddings deliberately
// are not: the vector index stores 1536-dim text-embedding-3-small vectors,
// so moving them is a re-embed migration, not an env change.
function chatConfig(
  prefix: string,
  label: string,
  defaultModel: string,
): { provider: Provider; model: string } {
  const baseUrl = process.env[`${prefix}_BASE_URL`];
  const model = process.env[`${prefix}_MODEL`];
  if (baseUrl === undefined || baseUrl === "") {
    return {
      provider: openaiProvider(),
      model: model === undefined || model === "" ? defaultModel : model,
    };
  }
  // A custom base URL must bring its own key and model: falling back would
  // hand the OpenAI bearer to a third-party host, or send that host a model
  // name it does not serve.
  return {
    provider: { baseUrl, label, key: requireEnv(`${prefix}_API_KEY`) },
    model: requireEnv(`${prefix}_MODEL`),
  };
}

function extractionConfig() {
  return chatConfig("EXTRACTION", "Extraction provider", "gpt-4o-mini");
}

// Separate from extraction on purpose: reading one screenshot and reasoning
// over a whole network are different jobs, and the cheap vision model that
// suits the first is not automatically the right one for the second.
function askConfig() {
  return chatConfig("ASK", "Ask provider", "gpt-4o-mini");
}

async function callProvider(
  provider: Provider,
  path: string,
  body: unknown,
): Promise<unknown> {
  const response = await fetch(`${provider.baseUrl}/v1/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${provider.key}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `${provider.label} ${path} failed (${response.status}): ${detail}`,
    );
  }
  return await response.json();
}

export async function extractProfile(
  imageUrl: string,
): Promise<ExtractedProfile> {
  const { provider, model } = extractionConfig();
  const result = (await callProvider(provider, "chat/completions", {
    model,
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: EXTRACTION_PROMPT },
          // "low", not "high": measured against four real profile
          // screenshots, high detail bought no extra accuracy -- same name,
          // same handle, decoy handles in the bio rejected either way -- and
          // cost about twice as much, because it sends the model into a long
          // reasoning pass rather than because the image costs more to read.
          { type: "image_url", image_url: { url: imageUrl, detail: "low" } },
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "profile_extraction",
        strict: true,
        schema: EXTRACTION_SCHEMA,
      },
    },
  })) as {
    choices?: Array<{ message?: { content?: string; refusal?: string } }>;
  };

  const message = result.choices?.[0]?.message;
  if (message === undefined || typeof message.content !== "string") {
    throw new Error(message?.refusal ?? `${provider.label} returned no extraction`);
  }
  const parsed = JSON.parse(message.content) as {
    is_profile: boolean;
    platform: string;
    name: string | null;
    handle: string | null;
    headline: string | null;
    bio: string | null;
  };

  const name = parsed.name?.trim() ?? "";
  if (!parsed.is_profile || name === "") {
    throw new Error("Could not read a profile in this screenshot");
  }
  const clean = (value: string | null): string | undefined => {
    const trimmed = value?.trim() ?? "";
    return trimmed === "" ? undefined : trimmed;
  };
  return {
    platform: parsed.platform,
    name,
    handle: clean(parsed.handle),
    headline: clean(parsed.headline),
    bio: clean(parsed.bio),
  };
}

// ------------------------------------------------------------------- ask

export type AskTurn = { role: "user" | "assistant"; text: string };

export type AskAnswer = {
  matches: Array<{ ref: number; kind: "direct" | "bridge"; why: string }>;
  clarifyingQuestion?: string;
};

const ASK_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["matches", "clarifying_question"],
  properties: {
    matches: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["ref", "kind", "why"],
        properties: {
          ref: {
            type: "integer",
            description: "The #number of the person from the network listing.",
          },
          kind: {
            type: "string",
            enum: ["direct", "bridge"],
            description:
              "direct if this person matches the need themselves; bridge if they are a likely route to someone who does.",
          },
          why: {
            type: "string",
            description:
              "One sentence, in the user's own terms, citing what is written about this person.",
          },
        },
      },
    },
    clarifying_question: {
      type: ["string", "null"],
      description:
        "One question to ask instead of guessing, or null when the network can be answered as asked.",
    },
  },
} as const;

const ASK_PROMPT = [
  "You are searching one person's private notes about people they know.",
  "Each entry below is one person: a #number, their details, and dated lines the user wrote about them.",
  "Answer only from these entries. Never invent a person, a fact, or a #number.",
  "",
  "Return a match as 'direct' when the person themselves fits the need.",
  "Return 'bridge' when nobody fits directly but this person is a plausible route to someone who does",
  "(for example: they work at a startup accelerator, so they likely know founders).",
  "A bridge must never be dressed up as a direct match, and its 'why' must say what the route is.",
  "",
  "If the request is too vague to answer without guessing, return no matches and ask exactly one",
  "clarifying question. Otherwise leave clarifying_question null.",
  "Order matches best first, and leave matches empty rather than padding it with weak ones.",
].join("\n");

// The whole network in one call, which is what keeps this cheap: a personal
// network is hundreds of people, so there is no retrieval infrastructure to
// build, only a prompt to fit.
export async function askNetwork(
  query: string,
  dossiers: string,
  history: AskTurn[],
): Promise<AskAnswer> {
  const { provider, model } = askConfig();
  const result = (await callProvider(provider, "chat/completions", {
    model,
    messages: [
      { role: "system", content: ASK_PROMPT },
      { role: "user", content: `The network:\n\n${dossiers}` },
      ...history.map((turn) => ({ role: turn.role, content: turn.text })),
      { role: "user", content: query },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: "network_answer", strict: true, schema: ASK_SCHEMA },
    },
  })) as {
    choices?: Array<{ message?: { content?: string; refusal?: string } }>;
  };

  const message = result.choices?.[0]?.message;
  if (message === undefined || typeof message.content !== "string") {
    throw new Error(message?.refusal ?? `${provider.label} returned no answer`);
  }
  const parsed = JSON.parse(message.content) as {
    matches: Array<{ ref: number; kind: "direct" | "bridge"; why: string }>;
    clarifying_question: string | null;
  };
  const clarifying = parsed.clarifying_question?.trim() ?? "";
  return {
    matches: parsed.matches ?? [],
    clarifyingQuestion: clarifying === "" ? undefined : clarifying,
  };
}

export async function embedText(text: string): Promise<number[]> {
  const result = (await callProvider(openaiProvider(), "embeddings", {
    model: "text-embedding-3-small",
    input: text,
  })) as { data?: Array<{ embedding?: number[] }> };

  const embedding = result.data?.[0]?.embedding;
  if (embedding === undefined) {
    throw new Error("OpenAI returned no embedding");
  }
  return embedding;
}
