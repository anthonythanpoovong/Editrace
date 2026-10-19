import { AuthForm } from "../../components/auth-form";
import { updatePassword } from "../auth/actions";

export const metadata = { title: "Choose a new password · Editrace" };

// Reached from the reset email via /auth/callback, which signs the user in first; proxy.ts sends anyone without a
// session to /login instead.
export default function ResetPasswordPage() {
  return (
    <main>
      <h1>Choose a new password</h1>
      <AuthForm
        action={updatePassword}
        submit="Update password"
        fields={[
          { name: "password", label: "New password (8 or more characters)", type: "password", autoComplete: "new-password" },
          { name: "confirm", label: "Confirm new password", type: "password", autoComplete: "new-password" },
        ]}
      />
    </main>
  );
}
