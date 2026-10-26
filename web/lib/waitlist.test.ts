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
  test("posts the trimmed signup to our own /api/waitlist route, not Supabase directly", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    const outcome = await joinWaitlist(config, { ...valid, firstName: " Ada ", email: " ada@example.com " }, fetchImpl);
    expect(outcome).toBe("ok");
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("/api/waitlist");
    expect(init.headers).toMatchObject({ "Content-Type": "application/json" });
    expect(JSON.parse(init.body as string)).toEqual({
      firstName: "Ada",
      lastName: "Lovelace",
      email: "ada@example.com",
      role: "editor",
      source: "tiktok",
    });
  });
  test("returns failed, without a request, when Supabase isn't configured", async () => {
    const fetchImpl = vi.fn(async () => new Response(null, { status: 204 }));
    expect(await joinWaitlist(null, valid, fetchImpl)).toBe("failed");
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  test("returns rate_limited when the rate-limit trigger's error code comes back", async () => {
    const body = JSON.stringify({ code: "EDR01", message: "Too many signups from this address. Try again later." });
    expect(await joinWaitlist(config, valid, async () => new Response(body, { status: 400 }))).toBe("rate_limited");
  });
  test("returns failed on an error response with a different code", async () => {
    const body = JSON.stringify({ code: "23514", message: "some other constraint" });
    expect(await joinWaitlist(config, valid, async () => new Response(body, { status: 400 }))).toBe("failed");
  });
  test("returns failed on an error response with no JSON body", async () => {
    expect(await joinWaitlist(config, valid, async () => new Response(null, { status: 500 }))).toBe("failed");
  });
  test("returns failed when the network fails", async () => {
    expect(
      await joinWaitlist(config, valid, async () => {
        throw new Error("offline");
      }),
    ).toBe("failed");
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
  test("tells a rate-limited visitor apart from a generic failure", async () => {
    const body = JSON.stringify({ code: "EDR01", message: "Too many signups from this address. Try again later." });
    const limited = await submitSignup(config, valid, "", async () => new Response(body, { status: 400 }));
    const failed = await submitSignup(config, valid, "", async () => new Response(null, { status: 500 }));
    expect(limited.note.text).not.toBe(failed.note.text);
    expect(limited).toMatchObject({ note: { state: "error" }, reset: false });
  });
});
