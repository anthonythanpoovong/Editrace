import { NextResponse, type NextRequest } from "next/server";
import { isPublicPath, loginRedirect } from "./lib/auth/guard";
import { updateSession } from "./lib/supabase/session";

// Runs before every page. Refreshes the session cookie, and sends a signed-out visitor to /login. This is the first
// check only: pages and server actions that read private data must check the user again themselves.
export async function proxy(request: NextRequest) {
  const { response, user } = await updateSession(request);
  const { pathname, search } = request.nextUrl;
  if (user || isPublicPath(pathname)) return response;
  const redirect = NextResponse.redirect(new URL(loginRedirect(pathname, search), request.url));
  for (const cookie of response.cookies.getAll()) redirect.cookies.set(cookie);
  return redirect;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
