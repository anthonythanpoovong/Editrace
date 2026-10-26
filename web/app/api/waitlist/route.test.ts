import { beforeEach, expect, test, vi } from "vitest";
import { NextRequest } from "next/server";

type RpcError = { code: string; message: string } | null;
const { rpc, ipAddress } = vi.hoisted(() => ({
  rpc: vi.fn<(...args: unknown[]) => Promise<{ error: RpcError }>>(async () => ({ error: null })),
  ipAddress: vi.fn<(request: NextRequest) => string | undefined>(),
}));
vi.mock("../../../lib/supabase/admin", () => ({ createAdminClient: () => ({ rpc }) }));
vi.mock("@vercel/functions", () => ({ ipAddress }));

import { POST } from "./route";

const valid = { firstName: "Ada", lastName: "Lovelace", email: "ada@example.com", role: "editor", source: "tiktok" };
const post = (body: unknown) => POST(new NextRequest("http://localhost:3000/api/waitlist", { method: "POST", body: JSON.stringify(body) }));

beforeEach(() => {
  rpc.mockClear();
  rpc.mockResolvedValue({ error: null });
  ipAddress.mockReset();
  ipAddress.mockReturnValue("203.0.113.5");
});

test("calls join_waitlist with the trimmed fields and the IP from ipAddress()", async () => {
  const res = await post({ ...valid, firstName: " Ada ", email: " ada@example.com " });
  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ ok: true });
  expect(rpc).toHaveBeenCalledWith("join_waitlist", {
    p_first_name: "Ada",
    p_last_name: "Lovelace",
    p_email: "ada@example.com",
    p_role: "editor",
    p_source: "tiktok",
    p_ip_address: "203.0.113.5",
  });
});
test("passes null, not 'unknown', when ipAddress() finds nothing (local next dev)", async () => {
  ipAddress.mockReturnValue(undefined);
  await post(valid);
  expect(rpc).toHaveBeenCalledWith("join_waitlist", expect.objectContaining({ p_ip_address: null }));
});
test("rejects an invalid signup without calling the RPC", async () => {
  const res = await post({ ...valid, email: "not-an-email" });
  expect(res.status).toBe(400);
  expect(rpc).not.toHaveBeenCalled();
});
test("rejects a non-JSON-object body without calling the RPC", async () => {
  const res = await POST(new NextRequest("http://localhost:3000/api/waitlist", { method: "POST", body: "null" }));
  expect(res.status).toBe(400);
  expect(rpc).not.toHaveBeenCalled();
});
test("returns 429 with the EDR01 code when the rate limiter trips", async () => {
  rpc.mockResolvedValue({ error: { code: "EDR01", message: "Too many signups from this address. Try again later." } });
  const res = await post(valid);
  expect(res.status).toBe(429);
  expect(await res.json()).toMatchObject({ code: "EDR01" });
});
test("returns 500 on any other RPC error", async () => {
  rpc.mockResolvedValue({ error: { code: "23514", message: "some other constraint" } });
  const res = await post(valid);
  expect(res.status).toBe(500);
  expect(await res.json()).toMatchObject({ code: "23514" });
});
