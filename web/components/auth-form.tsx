"use client";

import { useActionState, type ReactNode } from "react";
import type { FormState } from "../app/auth/actions";

type Field = { name: string; label: string; type: "email" | "password"; autoComplete: string };

// One form for every auth page: the fields, the server action and the button label change; the rest doesn't.
export function AuthForm({
  action,
  fields,
  submit,
  hidden = {},
  children,
}: {
  action: (state: FormState, form: FormData) => Promise<FormState>;
  fields: Field[];
  submit: string;
  hidden?: Record<string, string>;
  children?: ReactNode;
}) {
  const [state, formAction, pending] = useActionState(action, {});
  return (
    <form action={formAction}>
      {Object.entries(hidden).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {fields.map((f) => (
        <p key={f.name}>
          <label>
            {f.label}
            <br />
            <input name={f.name} type={f.type} autoComplete={f.autoComplete} required />
          </label>
        </p>
      ))}
      {state.error && <p role="alert">{state.error}</p>}
      {state.message && <p role="status">{state.message}</p>}
      <button type="submit" disabled={pending}>
        {submit}
      </button>
      {children}
    </form>
  );
}
