import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabaseConfig } from "./config";

// Supabase client for Server Components, server actions and route handlers. It runs as the signed-in user (the anon
// key plus their session cookie), so row-level security applies. Never use the service-role key for a user's request.
export async function createClient() {
  const store = await cookies();
  const { url, anonKey } = getSupabaseConfig();
  return createServerClient(url, anonKey, {
    cookies: {
      getAll: () => store.getAll(),
      setAll(list) {
        try {
          for (const { name, value, options } of list) store.set(name, value, options);
        } catch {
          // Called from a Server Component, which can't set cookies. proxy.ts refreshes the session on every request.
        }
      },
    },
  });
}
