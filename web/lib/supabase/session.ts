import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseConfig } from "./config";

// Refreshes the session cookie on every request and says who is signed in. `getUser()` asks Supabase to verify the
// token, so a forged cookie doesn't count; `getSession()` would only read it.
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  let config;
  try {
    config = getSupabaseConfig();
  } catch (error) {
    // Previews have no Supabase variables (docs/environments.md), and they must still serve the public pages.
    // Treated as signed out, so private pages redirect to /login. Loud, so a missing variable in prod isn't silent.
    console.error("Supabase isn't configured; treating the visitor as signed out.", error);
    return { response, user: null };
  }
  const { url, anonKey } = config;
  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(list) {
        for (const { name, value } of list) request.cookies.set(name, value);
        response = NextResponse.next({ request });
        for (const { name, value, options } of list) response.cookies.set(name, value, options);
      },
    },
  });
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { response, user };
}
