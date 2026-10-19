import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";

const getUser = vi.fn();
vi.mock("../lib/supabase/server", () => ({ createClient: async () => ({ auth: { getUser } }) }));
vi.mock("next/headers", () => ({ headers: async () => new Headers() }));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));

import AccountPage from "./account/page";
import ForgotPasswordPage from "./forgot-password/page";
import LoginPage from "./login/page";
import ResetPasswordPage from "./reset-password/page";
import SignupPage from "./signup/page";

const html = (node: unknown) => renderToStaticMarkup(node as React.ReactElement);

describe("login page", () => {
  test("has the email and password fields, Google, and the links", async () => {
    const out = html(await LoginPage({ searchParams: Promise.resolve({}) }));
    expect(out).toContain('name="email"');
    expect(out).toContain('name="password"');
    expect(out).toContain("Continue with Google");
    expect(out).toContain('href="/forgot-password"');
    expect(out).toContain('href="/signup"');
  });
  test("carries a site path through as the hidden next field", async () => {
    const out = html(await LoginPage({ searchParams: Promise.resolve({ next: "/upload" }) }));
    expect(out).toContain('name="next" value="/upload"');
  });
  test("drops an off-site next", async () => {
    const out = html(await LoginPage({ searchParams: Promise.resolve({ next: "https://evil.example" }) }));
    expect(out).not.toContain("evil.example");
    expect(out).toContain('name="next" value="/account"');
  });
  test("shows an error after a failed callback", async () => {
    expect(html(await LoginPage({ searchParams: Promise.resolve({ error: "callback" }) }))).toContain('role="alert"');
  });
});

test("signup page asks for email and a new password", () => {
  const out = html(SignupPage());
  expect(out).toContain('autoComplete="new-password"');
  expect(out).toContain("Continue with Google");
});
test("forgot-password page asks for an email only", () => {
  const out = html(ForgotPasswordPage());
  expect(out).toContain('name="email"');
  expect(out).not.toContain('name="password"');
});
test("reset-password page asks for the new password twice", () => {
  const out = html(ResetPasswordPage());
  expect(out).toContain('name="password"');
  expect(out).toContain('name="confirm"');
});
test("account page shows who is signed in, with a log-out button", async () => {
  getUser.mockResolvedValue({ data: { user: { email: "ana@example.com" } } });
  const out = html(await AccountPage());
  expect(out).toContain("ana@example.com");
  expect(out).toContain("Log out");
});
