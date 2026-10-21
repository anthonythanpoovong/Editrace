import { SignOutButton } from "../../components/sign-out-button";
import { createClient } from "../../lib/supabase/server";

export const metadata = { title: "Account · Editrace" };

// The signed-in landing page for now. proxy.ts keeps signed-out visitors out; the check here is the real one.
export default async function AccountPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return (
    <main>
      <h1>Account</h1>
      <p>Signed in as {user?.email}</p>
      <SignOutButton />
    </main>
  );
}
