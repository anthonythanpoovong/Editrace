import { describe, expect, test, vi } from "vitest";
import { joinWaitlist, submitSignup, validateSignup, type WaitlistSignup } from "./waitlist";

const valid: WaitlistSignup = {
  firstName: "Ada",
  lastName: "Lovelace",
  email: "ada@example.com",
  role: "editor",
  source: "tiktok",
};
const config = { url: "https://example.supabase.co", anonKey: "anon" };

describe("validateSignup", () => {
  test("accepts a complete signup", () => {
    expect(validateSignup(valid)).toEqual({});
  });
  test("flags every empty or unknown field", () => {
    expect(Object.keys(validateSignup({ firstName: " ", lastName: "", email: "nope", role: "", source: "x" })).sort()).toEqual(
      ["email", "firstName", "lastName", "role", "source"],
    );
  });
  test("rejects a role or source that isn't in the list", () => {
    expect(validateSignup({ ...valid, role: "ceo" }).role).toBeDefined();
    expect(validateSignup({ ...valid, source: "billboard" }).source).toBeDefined();
  });
});

describe("joinWaitlist", () => {
  test("posts the trimmed signup to the RPC with the anon key", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const ok = await joinWaitlist(config, { ...valid, firstName: " Ada ", email: " ada@example.com " }, fetchImpl);
    expect(ok).toBe(true);
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://example.supabase.co/rest/v1/rpc/join_waitlist");
    expect(init.headers).toMatchObject({ apikey: "anon", Authorization: "Bearer anon" });
    expect(JSON.parse(init.body as string)).toEqual({
      p_first_name: "Ada",
      p_last_name: "Lovelace",
      p_email: "ada@example.com",
      p_role: "editor",
      p_source: "tiktok",
    });
  });
  test("returns false, without a request, when Supabase isn't configured", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    expect(await joinWaitlist(null, valid, fetchImpl)).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  test("returns false on an error response", async () => {
    expect(await joinWaitlist(config, valid, async () => new Response(null, { status: 400 }))).toBe(false);
  });
  test("returns false when the network fails", async () => {
    expect(
      await joinWaitlist(config, valid, async () => {
        throw new Error("offline");
      }),
    ).toBe(false);
  });
});

describe("submitSignup", () => {
  const ok = async () => new Response(null, { status: 204 });
  test("reports the invalid fields and makes no request", async () => {
    const fetchImpl = vi.fn(ok);
    const result = await submitSignup(config, { ...valid, email: "nope" }, "", fetchImpl);
    expect(result.errors.email).toBeDefined();
    expect(result.note.state).toBe("error");
    expect(result.reset).toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  test("thanks a bot without making a request", async () => {
    const fetchImpl = vi.fn(ok);
    const result = await submitSignup(config, valid, "spam", fetchImpl);
    expect(result.note.state).toBe("success");
    expect(result.reset).toBe(true);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  test("thanks a real signup and empties the form", async () => {
    const result = await submitSignup(config, valid, "", ok);
    expect(result).toMatchObject({ errors: {}, note: { state: "success" }, reset: true });
  });
  test("keeps the form filled in when the request fails", async () => {
    const result = await submitSignup(config, valid, "", async () => new Response(null, { status: 500 }));
    expect(result).toMatchObject({ note: { state: "error" }, reset: false });
  });
});
