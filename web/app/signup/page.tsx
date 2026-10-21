import Link from "next/link";
import { AuthForm } from "../../components/auth-form";
import { GoogleButton } from "../../components/google-button";
import { signUp } from "../auth/actions";

export const metadata = { title: "Sign up · Editrace" };

export default function SignupPage() {
  return (
    <main>
      <h1>Create an account</h1>
      <AuthForm
        action={signUp}
        submit="Sign up"
        fields={[
          { name: "email", label: "Email", type: "email", autoComplete: "email" },
          { name: "password", label: "Password (8 or more characters)", type: "password", autoComplete: "new-password" },
        ]}
      />
      <GoogleButton />
      <p>
        Already have an account? <Link href="/login">Log in</Link>
      </p>
    </main>
  );
}
