import { ipAddress } from "@vercel/functions";
import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "../../../lib/supabase/admin";
import { validateSignup, type WaitlistSignup } from "../../../lib/waitlist";

export const runtime = "nodejs";

// The waitlist join endpoint (#153 review, blocker 3). The browser posts here instead of calling
// Supabase's join_waitlist RPC directly with the anon key: that let anyone holding the public key skip
// this route entirely and supply whatever IP they liked to the rate limiter. Only this server can call
// join_waitlist now (see the migration: execute is service_role only), and the IP it passes comes from
// Vercel's ipAddress() helper, not a client-suppliable header -- Vercel's edge sets x-forwarded-for
// itself on every request a Function sees, overwriting whatever the client sent.
export async function POST(request: NextRequest) {
  const body: unknown = await request.json().catch(() => null);
  if (!body || typeof body !== "object") {
    return NextResponse.json({ code: "bad_request" }, { status: 400 });
  }

  const field = (name: string): string => {
    const value = (body as Record<string, unknown>)[name];
    return typeof value === "string" ? value : "";
  };
  const signup: WaitlistSignup = {
    firstName: field("firstName"),
    lastName: field("lastName"),
    email: field("email"),
    role: field("role"),
    source: field("source"),
  };
  if (Object.keys(validateSignup(signup)).length > 0) {
    return NextResponse.json({ code: "invalid" }, { status: 400 });
  }

  // Local `next dev` isn't running on Vercel, so this is null there and every local signup shares the
  // rate limiter's 'unknown' bucket -- documented as a known, local-only limitation in the migration.
  const ip = ipAddress(request) ?? null;

  const { error } = await createAdminClient().rpc("join_waitlist", {
    p_first_name: signup.firstName.trim(),
    p_last_name: signup.lastName.trim(),
    p_email: signup.email.trim(),
    p_role: signup.role,
    p_source: signup.source,
    p_ip_address: ip,
  });

  if (!error) return NextResponse.json({ ok: true });
  const rateLimited = error.code === "EDR01";
  return NextResponse.json({ code: error.code, message: error.message }, { status: rateLimited ? 429 : 500 });
}
