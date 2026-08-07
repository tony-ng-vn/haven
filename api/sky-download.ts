import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { ConvexHttpClient } from "convex/browser";
import { api } from "../convex/_generated/api";

type DownloadDependencies = {
  hasPreviewAccess: (token: string) => Promise<boolean>;
  readArchive: () => Promise<Uint8Array>;
};

function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  if (authorization === null) return null;
  const match = authorization.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1] ?? null;
}

async function queryPreviewAccess(token: string): Promise<boolean> {
  const convexUrl = process.env.VITE_CONVEX_URL;
  if (convexUrl === undefined || convexUrl.trim() === "") {
    throw new Error("Missing VITE_CONVEX_URL");
  }
  const client = new ConvexHttpClient(convexUrl);
  client.setAuth(token);
  return await client.query(api.previewAccess.hasAccess, {});
}

async function readSkyArchive(): Promise<Uint8Array> {
  return await readFile(resolve(process.cwd(), "private", "YourSky.zip"));
}

const defaultDependencies: DownloadDependencies = {
  hasPreviewAccess: queryPreviewAccess,
  readArchive: readSkyArchive,
};

function privateError(
  message: string,
  status: number,
  headers?: HeadersInit,
): Response {
  return new Response(message, {
    status,
    headers: {
      "Cache-Control": "private, no-store",
      ...headers,
    },
  });
}

export async function skyDownloadResponse(
  request: Request,
  dependencies: DownloadDependencies = defaultDependencies,
): Promise<Response> {
  if (request.method !== "GET") {
    return privateError("Method not allowed", 405, { Allow: "GET" });
  }

  const token = bearerToken(request);
  if (token === null) {
    return privateError("Sign in required", 401);
  }

  let allowed: boolean;
  try {
    allowed = await dependencies.hasPreviewAccess(token);
  } catch {
    return privateError("Unable to verify preview access", 401);
  }
  if (!allowed) {
    return privateError("Preview access required", 403);
  }

  let archive: Uint8Array;
  try {
    archive = await dependencies.readArchive();
  } catch {
    return privateError("Download unavailable", 503);
  }

  const body = new ArrayBuffer(archive.byteLength);
  new Uint8Array(body).set(archive);
  return new Response(body, {
    status: 200,
    headers: {
      "Cache-Control": "private, no-store",
      "Content-Disposition": 'attachment; filename="YourSky.zip"',
      "Content-Type": "application/zip",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function GET(request: Request) {
  return skyDownloadResponse(request);
}
