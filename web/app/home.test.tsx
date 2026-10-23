import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { isPublicPath } from "../lib/auth/guard";
import Home from "./page";

const html = (node: unknown) => renderToStaticMarkup(node as React.ReactElement);

describe("coming-soon home page", () => {
  beforeEach(() => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon");
  });
  afterEach(() => vi.unstubAllEnvs());

  test("says what Editrace is and that it is coming soon", () => {
    const out = html(<Home />);
    expect(out).toContain("Rebuild the edit in minutes");
    expect(out).toContain("Coming soon");
    expect(out).toContain("Premiere Pro, DaVinci Resolve, Final Cut Pro and CapCut");
  });
  test("offers the waitlist button, with the form closed until it is pressed", () => {
    const out = html(<Home />);
    expect(out).toContain("Get notified");
    expect(out).not.toContain('name="email"');
  });
  test("still renders when Supabase isn't configured, as on a preview", () => {
    vi.unstubAllEnvs();
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(html(<Home />)).toContain("Get notified");
    expect(error).toHaveBeenCalled();
    error.mockRestore();
  });
  test("is open to signed-out visitors", () => {
    expect(isPublicPath("/")).toBe(true);
  });
});
