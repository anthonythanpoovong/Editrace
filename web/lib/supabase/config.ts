// The two public Supabase values every client needs. Where they live per environment: docs/environments.md.
export type SupabaseConfig = { url: string; anonKey: string };

export function getSupabaseConfig(env: Record<string, string | undefined> = process.env): SupabaseConfig {
  const url = env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY must be set (see .env.example).");
  }
  return { url, anonKey };
}
