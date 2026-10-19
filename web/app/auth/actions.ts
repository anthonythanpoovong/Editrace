"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getOrigin, safeNext } from "../../lib/auth/redirect";
import { credentialsSchema, emailSchema, newPasswordSchema, parseForm } from "../../lib/auth/validation";
import { createClient } from "../../lib/supabase/server";

// What each form shows back. Messages never say whether an email has an account, so the forms can't be used to find out.
export type FormState = { error?: string; message?: string };

const callback = async (next?: string) => {
  const origin = getOrigin(await headers());
  return `${origin}/auth/callback${next ? `?next=${encodeURIComponent(next)}` : ""}`;
};

export async function signUp(_: FormState, form: FormData): Promise<FormState> {
  const parsed = parseForm(credentialsSchema, form);
  if (!parsed.ok) return { error: parsed.error };
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    ...parsed.data,
    options: { emailRedirectTo: await callback() },
  });
  if (error) {
    return { error: error.code === "weak_password" ? error.message : "Couldn't create the account. Try again, or log in if you already have one." };
  }
  if (data.session) redirect("/account");
  return { message: "Check your email to confirm your account." };
}

export async function signIn(_: FormState, form: FormData): Promise<FormState> {
  const parsed = parseForm(credentialsSchema, form);
  if (!parsed.ok) return { error: parsed.error };
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) {
    return { error: error.code === "email_not_confirmed" ? "Confirm your email first. The link is in your inbox." : "Wrong email or password." };
  }
  redirect(safeNext(form.get("next"), "/account"));
}

export async function signOut(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function requestPasswordReset(_: FormState, form: FormData): Promise<FormState> {
  const parsed = parseForm(emailSchema, form);
  if (!parsed.ok) return { error: parsed.error };
  const supabase = await createClient();
  // The result is ignored on purpose: the answer is the same whether or not the email has an account.
  await supabase.auth.resetPasswordForEmail(parsed.data.email, { redirectTo: await callback("/reset-password") });
  return { message: "If that email has an account, a reset link is on its way." };
}

export async function updatePassword(_: FormState, form: FormData): Promise<FormState> {
  const parsed = parseForm(newPasswordSchema, form);
  if (!parsed.ok) return { error: parsed.error };
  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { error: error.code === "same_password" ? error.message : "Couldn't update the password. Open the reset link again." };
  redirect("/account");
}

export async function signInWithGoogle(form: FormData): Promise<void> {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: await callback(safeNext(form.get("next"), "/account")) },
  });
  if (error || !data.url) redirect("/login?error=oauth");
  redirect(data.url);
}
