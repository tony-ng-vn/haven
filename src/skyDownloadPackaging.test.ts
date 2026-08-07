import { existsSync, readdirSync, readFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { describe, expect, test } from "vitest";
import { createServer } from "vite";

const vercel = JSON.parse(readFileSync("vercel.json", "utf8")) as {
  functions?: Record<string, { includeFiles?: string }>;
};
const endpointSource = readFileSync("api/sky-download.ts", "utf8");

describe("the private Sky archive package", () => {
  test("keeps the archive outside the public site", () => {
    expect(existsSync("private/YourSky.zip")).toBe(true);
    expect(existsSync("public/downloads/YourSky.zip")).toBe(false);
  });

  test("includes the archive only in the protected function bundle", () => {
    expect(vercel.functions?.["api/sky-download.ts"]?.includeFiles).toBe(
      "private/YourSky.zip",
    );
  });

  test("does not turn endpoint tests into public functions", () => {
    expect(readdirSync("api").filter((name) => name.includes(".test."))).toEqual(
      [],
    );
  });

  test("does not depend on generated files outside the function bundle", () => {
    expect(endpointSource).toContain("makeFunctionReference");
    expect(endpointSource).not.toContain("../convex/_generated/api");
  });

  test("the development server refuses direct archive requests", async () => {
    const server = await createServer({
      configFile: "vite.config.ts",
      logLevel: "silent",
      server: { host: "127.0.0.1", port: 0 },
    });

    try {
      await server.listen();
      const address = server.httpServer?.address() as AddressInfo;
      const response = await fetch(
        `http://127.0.0.1:${address.port}/private/YourSky.zip`,
      );

      expect(response.status).toBe(403);
      expect(response.headers.get("content-type") ?? "").not.toContain(
        "application/zip",
      );
    } finally {
      await server.close();
    }
  });
});
