"use client";

import { useRef, useState, type FormEvent } from "react";
import styles from "../app/landing.module.css";
import type { SupabaseConfig } from "../lib/supabase/config";
import { ROLES, SOURCES, submitSignup, type SubmitResult, type WaitlistField, type WaitlistSignup } from "../lib/waitlist";

type Note = SubmitResult["note"];

// The "Get notified" button and the waitlist form it opens (#149). The form posts from the browser on purpose: see
// joinWaitlist for why it can't be a server action.
export function WaitlistSignup({ config }: { config: SupabaseConfig | null }) {
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [errors, setErrors] = useState<Partial<Record<WaitlistField, string>>>({});
  const [note, setNote] = useState<Note>({ state: "", text: "" });
  const form = useRef<HTMLFormElement>(null);

  function close() {
    form.current?.reset();
    setErrors({});
    setNote({ state: "", text: "" });
    setOpen(false);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const value = (name: string) => String(data.get(name) ?? "");
    const signup: WaitlistSignup = {
      firstName: value("firstName"),
      lastName: value("lastName"),
      email: value("email"),
      role: value("role"),
      source: value("source"),
    };
    setPending(true);
    setNote({ state: "", text: "Submitting…" });
    const result = await submitSignup(config, signup, value("hpField"));
    setPending(false);
    setErrors(result.errors);
    setNote(result.note);
    if (result.reset) form.current?.reset();
  }

  const field = (name: WaitlistField) => ({
    id: name,
    name,
    "aria-invalid": errors[name] ? true : undefined,
    "aria-describedby": `${name}-error`,
  });
  const error = (name: WaitlistField) =>
    errors[name] && (
      <p className={styles.fieldError} id={`${name}-error`}>
        {errors[name]}
      </p>
    );

  return (
    <>
      <div className={styles.signupBlock}>
        <button
          type="button"
          className={`${styles.signupTrigger} ${styles.btn} ${styles.btnSecondary}`}
          aria-expanded={open}
          aria-controls="signup-panel"
          onClick={() => setOpen(true)}
        >
          Get notified
        </button>
      </div>
      {open && (
        <div className={styles.signupPanel} id="signup-panel">
          <form ref={form} className={styles.signup} onSubmit={submit} noValidate>
            <div>
              <label className={styles.fieldLabel} htmlFor="firstName">First name</label>
              <input {...field("firstName")} type="text" autoComplete="given-name" autoFocus required />
              {error("firstName")}
            </div>
            <div>
              <label className={styles.fieldLabel} htmlFor="lastName">Last name</label>
              <input {...field("lastName")} type="text" autoComplete="family-name" required />
              {error("lastName")}
            </div>
            <div className={styles.fieldFull}>
              <label className={styles.fieldLabel} htmlFor="role">Role</label>
              <select {...field("role")} defaultValue="" required>
                <option value="" disabled>Select one</option>
                {ROLES.map((r) => (
                  <option key={r.value} value={r.value}>{r.label}</option>
                ))}
              </select>
              {error("role")}
            </div>
            <div className={styles.fieldFull}>
              <label className={styles.fieldLabel} htmlFor="email">Email address</label>
              <input {...field("email")} type="email" autoComplete="email" placeholder="you@example.com" required />
              {error("email")}
            </div>
            <div className={styles.fieldFull}>
              <label className={styles.fieldLabel} htmlFor="source">How did you hear about us?</label>
              <select {...field("source")} defaultValue="" required>
                <option value="" disabled>Select one</option>
                {SOURCES.map((s) => (
                  <option key={s.value} value={s.value}>{s.label}</option>
                ))}
              </select>
              {error("source")}
            </div>
            <div className={`${styles.fieldFull} ${styles.honeypot}`} aria-hidden="true">
              <label htmlFor="hpField">Leave this field blank</label>
              <input id="hpField" name="hpField" type="text" tabIndex={-1} autoComplete="off" />
            </div>
            <div className={`${styles.fieldFull} ${styles.signupActions}`}>
              <button type="submit" className={`${styles.btn} ${styles.btnPrimary}`} disabled={pending}>
                Notify me at launch
              </button>
              <button type="button" className={styles.signupCancel} onClick={close}>Cancel</button>
            </div>
          </form>
          <p className={styles.signupNote} data-state={note.state} role="status" aria-live="polite">{note.text}</p>
        </div>
      )}
    </>
  );
}
