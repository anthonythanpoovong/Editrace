import Link from "next/link";
import { AuthForm } from "../../components/auth-form";
import { GoogleButton } from "../../components/google-button";
import { safeNext } from "../../lib/auth/redirect";
import { signIn } from "../auth/actions";

export const metadata = { title: "Log in · Editrace" };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string; error?: string }> }) {
  const { next, error } = await searchParams;
  const target = safeNext(next, "/account");
  return (
    <main>
      <h1>Log in</h1>
      {error && <p role="alert">Sign-in didn&apos;t work. Try again.</p>}
      <AuthForm
        action={signIn}
        submit="Log in"
        hidden={{ next: target }}
        fields={[
          { name: "email", label: "Email", type: "email", autoComplete: "email" },
          { name: "password", label: "Password", type: "password", autoComplete: "current-password" },
        ]}
      />
      <GoogleButton next={target} />
      <p>
        <Link href="/forgot-password">Forgot your password?</Link> · <Link href="/signup">Create an account</Link>
      </p>
    </main>
  );
}
