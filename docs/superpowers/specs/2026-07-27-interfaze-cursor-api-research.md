# Interfaze and Cursor as extraction providers for Haven

Date: 2026-07-27.
Status: research findings, no code changed.

## Scope and method

Haven's Convex backend calls one OpenAI-compatible client in `convex/openaiClient.ts`.
It sends `POST {baseUrl}/v1/chat/completions` with model `gpt-4o-mini`, an `image_url` content part (`detail: "high"`), and a strict `json_schema` response_format for profile extraction.
It sends `POST {baseUrl}/v1/embeddings` with model `text-embedding-3-small`, whose 1536-dim vectors are stored in the `by_embedding` vector index (`dimensions: 1536`) in `convex/schema.ts`.
Both requests share a single `baseUrl` read from `OPENAI_BASE_URL` (default `https://api.openai.com`) and a single `OPENAI_API_KEY`.
This doc answers two questions from primary sources only: can interfaze.ai take over the extraction call, and does Cursor expose any backend-callable inference API.
Claims marked "verified by direct API probe" were confirmed against the live `api.interfaze.ai` service on 2026-07-27.

## Question 1: interfaze.ai

### (a) Base URL and auth header

The official docs initialize the stock OpenAI SDK with `baseURL: "https://api.interfaze.ai/v1"` and `apiKey: process.env.INTERFAZE_API_KEY` (https://interfaze.ai/docs).
The OpenAI SDK transmits `apiKey` as an `Authorization: Bearer <key>` header, so the auth shape is identical to OpenAI's.
Verified by direct API probe: `POST https://api.interfaze.ai/v1/chat/completions` without auth returns 401 `{"error":{"message":"No valid API key provided",...}}`, and with a bogus `Authorization: Bearer` header returns 401 `{"error":{"message":"The API key provided is not valid",...}}`, proving the service reads that header.
Note for Haven's client: `openaiClient.ts` appends `/v1/<path>` itself, so the env value must be `https://api.interfaze.ai` (no `/v1` suffix), mirroring how the OpenAI default omits it.

### (b) OpenAI compatibility for chat completions with vision

The docs' quickstart uses `interfaze.chat.completions.create()` through the unmodified OpenAI SDK (https://interfaze.ai/docs).
The OCR guide shows OpenAI-style multimodal content parts, e.g. `{ type: "image_url", image_url: { url: "https://..." } }` alongside a `{ type: "text", ... }` part (https://interfaze.ai/docs/vision/ocr).
Supported input modalities are text, images, audio, files, and video, with a 1M-token context window and 32k-token max output (https://interfaze.ai/, https://interfaze.ai/docs/limits).
The `detail` field inside `image_url` is not shown in any Interfaze example (https://interfaze.ai/docs/vision/ocr).
Sending it is standard OpenAI request shape, but its effect on Interfaze is undocumented, so verify one live call and drop the field if the API rejects it.

### (c) Model names and the gpt-4o-mini replacement

The only model identifier documented for the API is `interfaze-beta`, used in every quickstart and guide example (https://interfaze.ai/docs, https://interfaze.ai/docs/vision/ocr).
The pages under https://interfaze.ai/models are a "top trending AI models, updated daily" directory with capability comparisons, not a list of models served by the API (https://interfaze.ai/models).
Verified by direct API probe: `GET https://api.interfaze.ai/v1/models` exists (returns a JSON 401 without a key), so the definitive served-model list can be fetched with the account's key.
Interfaze positions `interfaze-beta` specifically at OCR and structured data extraction from images, which is exactly Haven's screenshot-to-fields task (https://interfaze.ai/).
Recommendation: replace `gpt-4o-mini` with `interfaze-beta` for the extraction call.

### (d) Embeddings - FLAG: not available

Interfaze does not serve an embeddings endpoint.
The word "embeddings" appears nowhere in the docs or navigation (https://interfaze.ai/docs), and the pricing page lists no embedding models (https://interfaze.ai/pricing).
Verified by direct API probe: `POST https://api.interfaze.ai/v1/embeddings` returns an HTML 404 page ("404: This page could not be found"), while `/v1/chat/completions` and `/v1/models` on the same host return proper JSON API errors.
FLAG: because Interfaze cannot produce `text-embedding-3-small`-compatible 1536-dim vectors, pointing the shared `baseUrl` at Interfaze would break `embedText` outright.
Any alternative embedding model would also change vector space and dimensions, forcing a re-embed migration of every stored person and a `dimensions` change to the `by_embedding` vector index, which Convex fixes at schema definition time in the 2 to 4096 range (https://docs.convex.dev/search/vector-search).
OpenAI's `text-embedding-3-small` default vector length is 1536 (https://developers.openai.com/api/docs/guides/embeddings) at $0.02 per 1M tokens (https://developers.openai.com/api/docs/models/text-embedding-3-small).
Safe recommendation: extraction moves to Interfaze, embeddings stay on OpenAI, which requires splitting the single shared `baseUrl` in `openaiClient.ts` (see Recommendation).

### (e) Rate limits and credit consumption

Rate limit: "You can make 50 requests per second. If you need more, please contact us" (https://interfaze.ai/docs/faqs, https://interfaze.ai/docs/limits).
Requests can run at most 5 minutes; direct file uploads are capped at 20 MB and URL-referenced files at 80 MB (https://interfaze.ai/docs/limits).
Billing is token-based: $1.50 per 1M input tokens and $3.50 per 1M output tokens, "Pay only for the tokens you use" (https://interfaze.ai/pricing).
Images and other media "are converted to binary data and are counted as input tokens", so each screenshot draws down credit as input tokens (https://interfaze.ai/docs/faqs).
Cached tokens are free: "if a specific token is cached, it won't be counted towards your usage" (https://interfaze.ai/docs/faqs).
Usage is tracked on the account dashboard (https://interfaze.ai/docs/faqs).

### (f) Structured output / json_schema

Structured outputs are supported: the OCR guide's TypeScript example passes `response_format: zodResponseFormat(IDSchema, "id_schema")` and the Python example uses the `json_schema` response_format type (https://interfaze.ai/docs/vision/ocr).
The `zodResponseFormat` helper from the official openai-node SDK serializes to `{ type: "json_schema", json_schema: { strict: true, schema: ... } }`, the exact shape `extractProfile` already sends (https://github.com/openai/openai-node/blob/master/helpers.md).
Haven's schema uses OpenAI strict-mode conventions (all properties required, optionality via `["string", "null"]` type arrays), and Interfaze does not document its strict-mode validation semantics, so run one screenshot through `extractProfile` against Interfaze before flipping production traffic.

## Question 2: Cursor

Cursor does not expose any server-side general-purpose inference API, so the answer is no.
Cursor's official APIs Overview enumerates its entire HTTP surface: Admin API, Analytics API, AI Code Tracking API, Bugbot API, Cloud Agents API, and the TypeScript/Python SDKs, and none of them is a chat-completions-style endpoint (https://cursor.com/docs/api.md).
The only AI-invoking API, the Cloud Agents API, "lets you programmatically launch and manage cloud agents that work on your repositories"; a request creates a durable agent plus an asynchronous run on a Cursor-hosted VM, oriented around repos, branches, and PRs, and even the no-repo variant returns an agent run rather than a model completion (https://cursor.com/docs/cloud-agent/api/endpoints.md).
Cloud Agents are billed "at API pricing for the selected model" against the Cursor account, but that spend only buys coding-agent executions, not arbitrary inference over HTTP (https://cursor.com/docs/cloud-agent.md).
Cursor's "bring your own API key" feature is the reverse direction: the user supplies OpenAI/Anthropic/Google keys for the IDE to spend, and it applies only to chat models inside Cursor (https://cursor.com/help/models-and-usage/api-keys.md).
Conclusion: Cursor credit cannot pay for Haven's extraction or embedding calls.

## Recommendation

Move extraction to Interfaze, keep embeddings on OpenAI, and split the provider config per endpoint.

Env vars on the Convex deployment:

```
npx convex env set EXTRACTION_BASE_URL https://api.interfaze.ai
npx convex env set EXTRACTION_API_KEY <interfaze key>
npx convex env set EXTRACTION_MODEL interfaze-beta
```

Leave `OPENAI_API_KEY` as-is and leave `OPENAI_BASE_URL` unset, so `embedText` keeps hitting `https://api.openai.com/v1/embeddings` with `text-embedding-3-small` and no re-embed migration or `dimensions` change is needed.

Minimal change to `convex/openaiClient.ts`:

1. Parameterize `callOpenAI` with a provider `{ baseUrl, apiKey }` instead of reading the module-level constants.
2. Define an embeddings provider from `OPENAI_BASE_URL`/`OPENAI_API_KEY` exactly as today.
3. Define an extraction provider from `EXTRACTION_BASE_URL`/`EXTRACTION_API_KEY`, falling back to the embeddings provider when unset, so a deployment without the new vars behaves exactly as before.
4. In `extractProfile`, read the model from `EXTRACTION_MODEL` with the current `"gpt-4o-mini"` as the fallback, and call through the extraction provider.
5. `embedText` and `convex/captures.ts` need no changes; the rate limiting, error laundering in `failExtract`, and retry flow are provider-agnostic.

Rollout check before flipping production: run one real screenshot through `extractProfile` against Interfaze to confirm strict `json_schema` acceptance and the undocumented `image_url.detail` field, and drop `detail` if rejected.
