import { z } from "zod";

// 72 is bcrypt's limit: a longer password would be silently cut, so it's refused up front.
const email = z.string().trim().toLowerCase().pipe(z.email("Enter a valid email address."));
const password = z
  .string()
  .min(8, "Use at least 8 characters.")
  .max(72, "Use at most 72 characters.");

export const credentialsSchema = z.object({ email, password });
export const emailSchema = z.object({ email });
export const newPasswordSchema = z
  .object({ password, confirm: z.string() })
  .refine((v) => v.password === v.confirm, { message: "The passwords don't match.", path: ["confirm"] });

export type Parsed<T> = { ok: true; data: T } | { ok: false; error: string };

// Reads a form and returns the first problem as a message fit to show the user.
export function parseForm<T>(schema: z.ZodType<T>, form: FormData): Parsed<T> {
  const result = schema.safeParse(Object.fromEntries(form));
  return result.success ? { ok: true, data: result.data } : { ok: false, error: result.error.issues[0].message };
}
