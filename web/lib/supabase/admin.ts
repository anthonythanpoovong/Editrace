import { createClient } from "@supabase/supabase-js";
import { getSupabaseConfig } from "./config";

// Server-only Supabase client using the service-role key, which bypasses RLS entirely (#153 review,
// blocker 3 -- see web/app/api/waitlist/route.ts, its only caller so far). Never import this into a
// Client Component or anything else that ships to the browser.
export function createAdminClient(env: Record<string, string | undefined> = process.env) {
  const { url } = getSupabaseConfig(env);
  const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY must be set (see .env.example).");
  }
  return createClient(url, serviceRoleKey, { auth: { persistSession: false } });
}
