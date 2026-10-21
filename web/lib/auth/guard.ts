import { safeNext } from "./redirect";

// Pages anyone can open. Everything else needs a session. /reset-password is deliberately not here: the reset link
// signs the user in first (via /auth/callback), and the page then changes the password of that session.
const PUBLIC_PATHS = new Set(["/", "/login", "/signup", "/forgot-password"]);

export function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.has(pathname) || pathname.startsWith("/auth/");
}

// Where to send a signed-out visitor, keeping the page they wanted so login can bring them back.
export function loginRedirect(pathname: string, search: string): string {
  return `/login?next=${encodeURIComponent(safeNext(pathname + search))}`;
}
