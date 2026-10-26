import { beforeEach, expect, test, vi } from "vitest";

const { createClient } = vi.hoisted(() => ({ createClient: vi.fn(() => ({})) }));
vi.mock("@supabase/supabase-js", () => ({ createClient }));

import { createAdminClient } from "./admin";

const env = { NEXT_PUBLIC_SUPABASE_URL: "http://supabase.test", NEXT_PUBLIC_SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: "service-role" };

beforeEach(() => createClient.mockClear());

test("creates a client with the service-role key, not the anon key", () => {
  createAdminClient(env);
  expect(createClient).toHaveBeenCalledWith("http://supabase.test", "service-role", { auth: { persistSession: false } });
});
test("throws when the service-role key isn't set", () => {
  expect(() => createAdminClient({ ...env, SUPABASE_SERVICE_ROLE_KEY: undefined })).toThrow(/SUPABASE_SERVICE_ROLE_KEY/);
  expect(createClient).not.toHaveBeenCalled();
});
test("throws when the public config isn't set either", () => {
  expect(() => createAdminClient({})).toThrow(/must be set/);
});
