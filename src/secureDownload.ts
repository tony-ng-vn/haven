export type ConvexTokenGetter = (options: {
  template: "convex";
}) => Promise<string | null>;

type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export async function requestSkyArchive(
  getToken: ConvexTokenGetter,
  fetcher: Fetcher = fetch,
): Promise<Blob> {
  const token = await getToken({ template: "convex" });
  if (token === null) {
    throw new Error("Sign in again to download Your Sky.");
  }

  const response = await fetcher("/api/sky-download", {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 401) {
    throw new Error("Sign in again to download Your Sky.");
  }
  if (response.status === 403) {
    throw new Error("Preview access is required to download Your Sky.");
  }
  if (!response.ok) {
    throw new Error("Your Sky could not be downloaded. Please try again.");
  }
  return await response.blob();
}

export function saveSkyArchive(archive: Blob): void {
  const url = URL.createObjectURL(archive);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = "YourSky.zip";
  anchor.click();
  URL.revokeObjectURL(url);
}
