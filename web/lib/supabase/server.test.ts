import { beforeEach, expect, test, vi } from "vitest";

const store = { getAll: vi.fn(() => [{ name: "a", value: "1" }]), set: vi.fn() };
let handlers: { getAll: () => unknown; setAll: (l: { name: string; value: string; options?: object }[]) => void };
vi.mock("next/headers", () => ({ cookies: async () => store }));
vi.mock("@supabase/ssr", () => ({
  createServerClient: (_u: string, _k: string, opts: { cookies: typeof handlers }) => {
    handlers = opts.cookies;
    return {};
  },
}));

import { createClient } from "./server";

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://supabase.test");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon");
  store.set.mockReset();
});

test("reads the request's cookies", async () => {
  await createClient();
  expect(handlers.getAll()).toEqual([{ name: "a", value: "1" }]);
});
test("writes refreshed cookies", async () => {
  await createClient();
  handlers.setAll([{ name: "sb", value: "v", options: { path: "/" } }]);
  expect(store.set).toHaveBeenCalledWith("sb", "v", { path: "/" });
});
test("doesn't throw when called from a Server Component, which can't set cookies", async () => {
  store.set.mockImplementation(() => {
    throw new Error("Cookies can only be modified in a Server Action or Route Handler");
  });
  await createClient();
  expect(() => handlers.setAll([{ name: "sb", value: "v" }])).not.toThrow();
});
