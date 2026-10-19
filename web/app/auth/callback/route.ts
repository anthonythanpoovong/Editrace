import { headers } from "next/headers";
import { NextResponse, type NextRequest } from "next/server";
import { getOrigin, safeNext } from "../../../lib/auth/redirect";
import { createClient } from "../../../lib/supabase/server";

// Where Supabase sends the user back to after Google sign-in, email confirmation and password-reset links. It swaps the
// one-time `code` for a session cookie, then goes to `next` (a path on this site only).
export async function GET(request: NextRequest) {
  const origin = getOrigin(await headers());
  const code = request.nextUrl.searchParams.get("code");
  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${safeNext(request.nextUrl.searchParams.get("next"), "/account")}`);
  }
  return NextResponse.redirect(`${origin}/login?error=callback`);
}
