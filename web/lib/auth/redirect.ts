// `next` comes from the URL, so it's attacker-controlled. Only a path on this site is allowed; anything else
// (https://evil.example, //evil.example, /\evil.example) falls back, so login can't be used as an open redirect.
export function safeNext(next: unknown, fallback = "/"): string {
  if (typeof next !== "string" || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) {
    return fallback;
  }
  // The URL parser strips tabs and newlines, so "/\t/evil.example" becomes "//evil.example": compare origins, not prefixes.
  const resolved = new URL(next, "http://site.invalid");
  if (resolved.origin !== "http://site.invalid") return fallback;
  return resolved.pathname + resolved.search + resolved.hash;
}

// The site's own origin, for the links in auth emails. Supabase only accepts redirect URLs on its allow-list, so a
// spoofed Host header can't send a user anywhere else.
export function getOrigin(headers: Headers): string {
  const origin = headers.get("origin");
  if (origin) return origin;
  const host = headers.get("x-forwarded-host") ?? headers.get("host") ?? "localhost:3000";
  const proto = headers.get("x-forwarded-proto") ?? (host.startsWith("localhost") || host.startsWith("127.") ? "http" : "https");
  return `${proto}://${host}`;
}
