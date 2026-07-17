// Plain helpers for the two OpenAI endpoints Euno uses. Not registered
// Convex functions; call these only from actions (they do network IO).
// fetch is available in the default Convex runtime, so no "use node".

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

function apiKey(): string {
  const key = process.env.OPENAI_API_KEY;
  if (key === undefined || key === "") {
    throw new Error(
      "OPENAI_API_KEY is not set on the Convex deployment. Run: npx convex env set OPENAI_API_KEY <key>",
    );
  }
  return key;
}

async function callOpenAI(path: string, body: unknown): Promise<unknown> {
  const response = await fetch(`https://api.openai.com/v1/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey()}`,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`OpenAI ${path} failed (${response.status}): ${detail}`);
  }
  return await response.json();
}

export async function extractProfile(
  imageUrl: string,
): Promise<ExtractedProfile> {
  const result = (await callOpenAI("chat/completions", {
    model: "gpt-4o-mini",
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: EXTRACTION_PROMPT },
          { type: "image_url", image_url: { url: imageUrl, detail: "high" } },
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
    throw new Error(message?.refusal ?? "OpenAI returned no extraction");
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

export async function embedText(text: string): Promise<number[]> {
  const result = (await callOpenAI("embeddings", {
    model: "text-embedding-3-small",
    input: text,
  })) as { data?: Array<{ embedding?: number[] }> };

  const embedding = result.data?.[0]?.embedding;
  if (embedding === undefined) {
    throw new Error("OpenAI returned no embedding");
  }
  return embedding;
}
