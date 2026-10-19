import { beforeEach, describe, expect, test, vi } from "vitest";

// A fake Supabase client: each test sets what the auth call returns and reads what it was called with.
const auth = {
  signUp: vi.fn(),
  signInWithPassword: vi.fn(),
  signOut: vi.fn(),
  resetPasswordForEmail: vi.fn(),
  updateUser: vi.fn(),
  signInWithOAuth: vi.fn(),
};
vi.mock("../../lib/supabase/server", () => ({ createClient: async () => ({ auth }) }));
vi.mock("next/headers", () => ({ headers: async () => new Headers({ origin: "http://localhost:3000" }) }));
vi.mock("next/navigation", () => ({
  redirect: (url: string) => {
    throw new Error(`REDIRECT ${url}`);
  },
}));

import { requestPasswordReset, signIn, signInWithGoogle, signOut, signUp, updatePassword } from "./actions";

const form = (o: Record<string, string>) => Object.entries(o).reduce((f, [k, v]) => (f.set(k, v), f), new FormData());
const creds = { email: "ana@example.com", password: "longenough" };

beforeEach(() => vi.resetAllMocks());

describe("signUp", () => {
  test("rejects bad input without calling Supabase", async () => {
    expect(await signUp({}, form({ email: "x", password: "longenough" }))).toEqual({ error: "Enter a valid email address." });
    expect(auth.signUp).not.toHaveBeenCalled();
  });
  test("asks the user to confirm their email when there's no session yet", async () => {
    auth.signUp.mockResolvedValue({ data: { session: null }, error: null });
    expect(await signUp({}, form(creds))).toEqual({ message: "Check your email to confirm your account." });
    expect(auth.signUp).toHaveBeenCalledWith({ ...creds, options: { emailRedirectTo: "http://localhost:3000/auth/callback" } });
  });
  test("signs straight in when confirmations are off", async () => {
    auth.signUp.mockResolvedValue({ data: { session: {} }, error: null });
    await expect(signUp({}, form(creds))).rejects.toThrow("REDIRECT /account");
  });
  test("shows a weak-password message", async () => {
    auth.signUp.mockResolvedValue({ data: {}, error: { code: "weak_password", message: "Password is too common." } });
    expect(await signUp({}, form(creds))).toEqual({ error: "Password is too common." });
  });
  test("doesn't reveal that an email is already registered", async () => {
    auth.signUp.mockResolvedValue({ data: {}, error: { code: "user_already_exists", message: "User already registered" } });
    const result = await signUp({}, form(creds));
    expect(result.error).not.toMatch(/already registered/i);
  });
});

describe("signIn", () => {
  test("rejects bad input", async () => {
    expect(await signIn({}, form({ email: "ana@example.com", password: "x" }))).toEqual({ error: "Use at least 8 characters." });
  });
  test("goes to the page the user wanted", async () => {
    auth.signInWithPassword.mockResolvedValue({ error: null });
    await expect(signIn({}, form({ ...creds, next: "/upload" }))).rejects.toThrow("REDIRECT /upload");
  });
  test("ignores an off-site next and lands on the account page", async () => {
    auth.signInWithPassword.mockResolvedValue({ error: null });
    await expect(signIn({}, form({ ...creds, next: "https://evil.example" }))).rejects.toThrow("REDIRECT /account");
  });
  test("gives one message for a wrong email or password", async () => {
    auth.signInWithPassword.mockResolvedValue({ error: { code: "invalid_credentials" } });
    expect(await signIn({}, form(creds))).toEqual({ error: "Wrong email or password." });
  });
  test("tells an unconfirmed user to confirm", async () => {
    auth.signInWithPassword.mockResolvedValue({ error: { code: "email_not_confirmed" } });
    expect((await signIn({}, form(creds))).error).toMatch(/Confirm your email/);
  });
});

test("signOut clears the session and goes to /login", async () => {
  auth.signOut.mockResolvedValue({});
  await expect(signOut()).rejects.toThrow("REDIRECT /login");
  expect(auth.signOut).toHaveBeenCalled();
});

describe("requestPasswordReset", () => {
  test("rejects a bad email", async () => {
    expect(await requestPasswordReset({}, form({ email: "x" }))).toEqual({ error: "Enter a valid email address." });
  });
  test("sends the link and answers the same whether or not the account exists", async () => {
    auth.resetPasswordForEmail.mockResolvedValue({ error: { code: "user_not_found" } });
    const result = await requestPasswordReset({}, form({ email: "ana@example.com" }));
    expect(result).toEqual({ message: "If that email has an account, a reset link is on its way." });
    expect(auth.resetPasswordForEmail).toHaveBeenCalledWith("ana@example.com", {
      redirectTo: "http://localhost:3000/auth/callback?next=%2Freset-password",
    });
  });
});

describe("updatePassword", () => {
  const pw = { password: "longenough", confirm: "longenough" };
  test("rejects mismatched passwords", async () => {
    expect(await updatePassword({}, form({ password: "longenough", confirm: "other12345" }))).toEqual({ error: "The passwords don't match." });
  });
  test("updates and goes to the account page", async () => {
    auth.updateUser.mockResolvedValue({ error: null });
    await expect(updatePassword({}, form(pw))).rejects.toThrow("REDIRECT /account");
    expect(auth.updateUser).toHaveBeenCalledWith({ password: "longenough" });
  });
  test("passes on the same-password message", async () => {
    auth.updateUser.mockResolvedValue({ error: { code: "same_password", message: "New password must be different." } });
    expect(await updatePassword({}, form(pw))).toEqual({ error: "New password must be different." });
  });
  test("asks for a fresh link when there's no session", async () => {
    auth.updateUser.mockResolvedValue({ error: { code: "session_not_found", message: "x" } });
    expect((await updatePassword({}, form(pw))).error).toMatch(/Open the reset link again/);
  });
});

describe("signInWithGoogle", () => {
  test("sends the user to Google and brings them back through the callback", async () => {
    auth.signInWithOAuth.mockResolvedValue({ data: { url: "https://accounts.google.com/x" }, error: null });
    await expect(signInWithGoogle(form({ next: "/upload" }))).rejects.toThrow("REDIRECT https://accounts.google.com/x");
    expect(auth.signInWithOAuth).toHaveBeenCalledWith({
      provider: "google",
      options: { redirectTo: "http://localhost:3000/auth/callback?next=%2Fupload" },
    });
  });
  test("falls back to the login page when Supabase gives no URL", async () => {
    auth.signInWithOAuth.mockResolvedValue({ data: {}, error: { message: "Provider is not enabled" } });
    await expect(signInWithGoogle(form({}))).rejects.toThrow("REDIRECT /login?error=oauth");
  });
});
