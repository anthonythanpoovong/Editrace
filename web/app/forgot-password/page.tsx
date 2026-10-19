import Link from "next/link";
import { AuthForm } from "../../components/auth-form";
import { requestPasswordReset } from "../auth/actions";

export const metadata = { title: "Reset your password · Editrace" };

export default function ForgotPasswordPage() {
  return (
    <main>
      <h1>Reset your password</h1>
      <AuthForm
        action={requestPasswordReset}
        submit="Send reset link"
        fields={[{ name: "email", label: "Email", type: "email", autoComplete: "email" }]}
      />
      <p>
        <Link href="/login">Back to log in</Link>
      </p>
    </main>
  );
}
