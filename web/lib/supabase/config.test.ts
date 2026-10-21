import { expect, test } from "vitest";
import { getSupabaseConfig } from "./config";

test("returns the url and anon key", () => {
  expect(getSupabaseConfig({ NEXT_PUBLIC_SUPABASE_URL: "http://x", NEXT_PUBLIC_SUPABASE_ANON_KEY: "k" })).toEqual({ url: "http://x", anonKey: "k" });
});
test.each([{}, { NEXT_PUBLIC_SUPABASE_URL: "http://x" }, { NEXT_PUBLIC_SUPABASE_ANON_KEY: "k" }])("throws when a value is missing: %j", (env) => {
  expect(() => getSupabaseConfig(env)).toThrow(/must be set/);
});
