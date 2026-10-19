import { signOut } from "../app/auth/actions";

export function SignOutButton() {
  return (
    <form action={signOut}>
      <button type="submit">Log out</button>
    </form>
  );
}
