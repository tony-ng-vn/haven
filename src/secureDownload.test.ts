import { describe, expect, test, vi } from "vitest";

import { requestSkyArchive } from "./secureDownload";

describe("the protected Sky download client", () => {
  test("sends the signed-in Convex token to the protected endpoint", async () => {
    const getToken = vi.fn(async () => "signed-token");
    const fetcher = vi.fn(async () =>
      new Response(new Blob(["zip"]), { status: 200 }),
    );

    const archive = await requestSkyArchive(getToken, fetcher);

    expect(getToken).toHaveBeenCalledWith({ template: "convex" });
    expect(fetcher).toHaveBeenCalledWith("/api/sky-download", {
      headers: { Authorization: "Bearer signed-token" },
    });
    expect(await archive.text()).toBe("zip");
  });

  test("fails closed when Clerk cannot provide a token", async () => {
    await expect(
      requestSkyArchive(async () => null, vi.fn()),
    ).rejects.toThrow("Sign in again");
  });

  test("does not expose a failed server response as a download", async () => {
    await expect(
      requestSkyArchive(
        async () => "signed-token",
        vi.fn(async () => new Response("Forbidden", { status: 403 })),
      ),
    ).rejects.toThrow("Preview access is required");
  });
});
