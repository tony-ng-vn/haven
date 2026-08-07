import { existsSync, readdirSync, readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";

const vercel = JSON.parse(readFileSync("vercel.json", "utf8")) as {
  functions?: Record<string, { includeFiles?: string }>;
};

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
});
