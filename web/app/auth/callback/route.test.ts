import { beforeEach, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

const exchangeCodeForSession = vi.fn();
vi.mock("../../../lib/supabase/server", () => ({ createClient: async () => ({ auth: { exchangeCodeForSession } }) }));
vi.mock("next/headers", () => ({ headers: async () => new Headers({ origin: "http://localhost:3000" }) }));

import { GET } from "./route";

const call = (qs: string) => GET(new NextRequest(`http://localhost:3000/auth/callback${qs}`));
beforeEach(() => vi.resetAllMocks());

test("swaps the code for a session and goes to next", async () => {
  exchangeCodeForSession.mockResolvedValue({ error: null });
  const res = await call("?code=abc&next=%2Freset-password");
  expect(exchangeCodeForSession).toHaveBeenCalledWith("abc");
  expect(res.headers.get("location")).toBe("http://localhost:3000/reset-password");
});
test("an off-site next lands on the account page", async () => {
  exchangeCodeForSession.mockResolvedValue({ error: null });
  const res = await call("?code=abc&next=https%3A%2F%2Fevil.example");
  expect(res.headers.get("location")).toBe("http://localhost:3000/account");
});
test("a bad code goes back to login with an error", async () => {
  exchangeCodeForSession.mockResolvedValue({ error: { message: "expired" } });
  expect((await call("?code=bad")).headers.get("location")).toBe("http://localhost:3000/login?error=callback");
});
test("no code goes back to login with an error", async () => {
  expect((await call("")).headers.get("location")).toBe("http://localhost:3000/login?error=callback");
  expect(exchangeCodeForSession).not.toHaveBeenCalled();
});
