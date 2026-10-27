import type { SupabaseConfig } from "./supabase/config";

export const ROLES = [
  { value: "creator", label: "Creator" },
  { value: "editor", label: "Editor" },
  { value: "hobbyist", label: "Hobbyist" },
  { value: "agency", label: "Agency" },
] as const;

export const SOURCES = [
  { value: "instagram", label: "Instagram" },
  { value: "tiktok", label: "TikTok" },
  { value: "facebook", label: "Facebook" },
  { value: "linkedin", label: "LinkedIn" },
  { value: "word-of-mouth", label: "Word of mouth" },
  { value: "other", label: "Other" },
] as const;

export type WaitlistSignup = {
  firstName: string;
  lastName: string;
  email: string;
  role: string;
  source: string;
};

export type WaitlistField = keyof WaitlistSignup;

const FIELD_ERRORS: Record<WaitlistField, string> = {
  firstName: "Enter your first name.",
  lastName: "Enter your last name.",
  role: "Select your role.",
  email: "Enter a valid email, like you@example.com.",
  source: "Select how you heard about us.",
};

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// One message per invalid field. The database caps lengths and normalises the email; this is the friendly first pass.
export function validateSignup(signup: WaitlistSignup): Partial<Record<WaitlistField, string>> {
  const errors: Partial<Record<WaitlistField, string>> = {};
  if (!signup.firstName.trim()) errors.firstName = FIELD_ERRORS.firstName;
  if (!signup.lastName.trim()) errors.lastName = FIELD_ERRORS.lastName;
  if (!ROLES.some((r) => r.value === signup.role)) errors.role = FIELD_ERRORS.role;
  if (!EMAIL.test(signup.email.trim())) errors.email = FIELD_ERRORS.email;
  if (!SOURCES.some((s) => s.value === signup.source)) errors.source = FIELD_ERRORS.source;
  return errors;
}

// The SQLSTATE enforce_waitlist_rate_limit() raises when an address is over the 5-per-10-minutes cap
// (supabase/migrations/20261023050442_create_waitlist_signups.sql). PostgREST passes it through
// as the RPC error body's `code` field, which is more stable to match on than the message text.
const RATE_LIMITED_CODE = "EDR01";

export type JoinOutcome = "ok" | "rate_limited" | "failed";

// Posts to our own /api/waitlist route (#153 review, blocker 3), not straight to Supabase's join_waitlist RPC: that
// route holds the service-role key server-side (join_waitlist no longer grants execute to anon) and reads the
// visitor's real IP via Vercel's own trusted ipAddress() helper, instead of a client-suppliable header. config is
// still checked here first, purely as a cheap "is Supabase configured at all" signal (see below).
export async function joinWaitlist(
  config: SupabaseConfig | null,
  signup: WaitlistSignup,
  fetchImpl: typeof fetch = fetch,
): Promise<JoinOutcome> {
  // Previews have no Supabase variables (docs/environments.md): the form still shows, and sending fails politely.
  if (!config) return "failed";
  try {
    const response = await fetchImpl("/api/waitlist", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        firstName: signup.firstName.trim(),
        lastName: signup.lastName.trim(),
        email: signup.email.trim(),
        role: signup.role,
        source: signup.source,
      }),
    });
    if (response.ok) return "ok";
    const body: unknown = await response.json().catch(() => null);
    const code = body && typeof body === "object" && "code" in body ? (body as { code: unknown }).code : null;
    return code === RATE_LIMITED_CODE ? "rate_limited" : "failed";
  } catch {
    return "failed";
  }
}

// "We'll make sure you hear from us" would promise an email that nothing sends yet (#153 review): say only what's true.
const THANKS = "You're on the list.";
const RATE_LIMITED = "You've tried this a few times. Wait a few minutes, then try again.";
const FAILED = "Something went wrong. Please try again in a moment.";

export type SubmitResult = {
  errors: Partial<Record<WaitlistField, string>>;
  note: { state: "" | "error" | "success"; text: string };
  // True when the form should be emptied: after a signup, or after a bot tripped the hidden field.
  reset: boolean;
};

// Everything the form does on submit, apart from the DOM: validate, quietly drop a bot, otherwise call the RPC.
export async function submitSignup(
  config: SupabaseConfig | null,
  signup: WaitlistSignup,
  honeypot: string,
  fetchImpl: typeof fetch = fetch,
): Promise<SubmitResult> {
  const errors = validateSignup(signup);
  if (Object.keys(errors).length > 0) {
    return { errors, note: { state: "error", text: "Error: fix the highlighted fields below." }, reset: false };
  }
  // A bot filled the hidden field: say thanks without making a request.
  if (honeypot) return { errors: {}, note: { state: "success", text: THANKS }, reset: true };
  const outcome = await joinWaitlist(config, signup, fetchImpl);
  if (outcome === "ok") return { errors: {}, note: { state: "success", text: THANKS }, reset: true };
  const text = outcome === "rate_limited" ? RATE_LIMITED : FAILED;
  return { errors: {}, note: { state: "error", text }, reset: false };
}
