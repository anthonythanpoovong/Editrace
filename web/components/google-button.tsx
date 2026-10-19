import { signInWithGoogle } from "../app/auth/actions";

export function GoogleButton({ next }: { next?: string }) {
  return (
    <form action={signInWithGoogle}>
      {next && <input type="hidden" name="next" value={next} />}
      <button type="submit">Continue with Google</button>
    </form>
  );
}
