// @vitest-environment node
import { describe, expect, test, vi } from "vitest";

import { skyDownloadResponse } from "../api/sky-download";

const request = (authorization?: string, method = "GET") =>
  new Request("https://inhavens.com/api/sky-download", {
    method,
    headers:
      authorization === undefined ? undefined : { Authorization: authorization },
  });

const granted = () => ({
  hasPreviewAccess: vi.fn(async () => true),
  readArchive: vi.fn(async () => new Uint8Array([80, 75, 3, 4])),
});

describe("the protected Sky download endpoint", () => {
  test("requires a correctly formed bearer token", async () => {
    for (const authorization of [undefined, "", "Basic abc", "Bearer"] as const) {
      const dependencies = granted();
      const response = await skyDownloadResponse(
        request(authorization),
        dependencies,
      );

      expect(response.status).toBe(401);
      expect(response.headers.get("cache-control")).toBe("private, no-store");
      expect(dependencies.hasPreviewAccess).not.toHaveBeenCalled();
      expect(dependencies.readArchive).not.toHaveBeenCalled();
    }
  });

  test("does not read the archive for an account without preview access", async () => {
    const dependencies = {
      hasPreviewAccess: vi.fn(async () => false),
      readArchive: vi.fn(async () => new Uint8Array([80, 75, 3, 4])),
    };

    const response = await skyDownloadResponse(
      request("Bearer signed-token"),
      dependencies,
    );

    expect(response.status).toBe(403);
    expect(dependencies.hasPreviewAccess).toHaveBeenCalledWith("signed-token");
    expect(dependencies.readArchive).not.toHaveBeenCalled();
  });

  test("returns the private archive only after the grant check", async () => {
    const dependencies = granted();

    const response = await skyDownloadResponse(
      request("Bearer signed-token"),
      dependencies,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/zip");
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("content-disposition")).toContain("YourSky.zip");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(
      new Uint8Array([80, 75, 3, 4]),
    );
  });

  test("rejects methods other than GET", async () => {
    const response = await skyDownloadResponse(
      request("Bearer signed-token", "POST"),
      granted(),
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET");
  });
});
