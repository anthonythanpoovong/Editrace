import { beforeEach, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const getUser = vi.fn();
let handlers: { getAll: () => unknown; setAll: (l: { name: string; value: string; options?: object }[]) => void };
vi.mock("@supabase/ssr", () => ({
  createServerClient: (_url: string, _key: string, opts: { cookies: typeof handlers }) => {
    handlers = opts.cookies;
    return { auth: { getUser } };
  },
}));

import { updateSession } from "./session";

const request = () => new NextRequest("http://localhost:3000/account", { headers: { cookie: "a=1" } });
beforeEach(() => {
  vi.resetAllMocks();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "http://supabase.test");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon");
});

test("returns the verified user", async () => {
  getUser.mockResolvedValue({ data: { user: { id: "u1" } } });
  const { user } = await updateSession(request());
  expect(user).toEqual({ id: "u1" });
});
test("returns no user when signed out", async () => {
  getUser.mockResolvedValue({ data: { user: null } });
  expect((await updateSession(request())).user).toBeNull();
});
test("reads the request's cookies", async () => {
  getUser.mockResolvedValue({ data: { user: null } });
  await updateSession(request());
  expect(handlers.getAll()).toEqual([{ name: "a", value: "1" }]);
});
test("a refreshed session is written to the response", async () => {
  getUser.mockImplementation(async () => {
    handlers.setAll([{ name: "sb-token", value: "new", options: { path: "/" } }]);
    return { data: { user: { id: "u1" } } };
  });
  const { response } = await updateSession(request());
  expect(response.cookies.get("sb-token")?.value).toBe("new");
});
test("treats the visitor as signed out, loudly, when Supabase isn't configured", async () => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
  const error = vi.spyOn(console, "error").mockImplementation(() => {});
  const { user } = await updateSession(request());
  expect(user).toBeNull();
  expect(error).toHaveBeenCalled();
  expect(getUser).not.toHaveBeenCalled();
});
