import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { login } from "../auth-actions";

export const dynamic = "force-dynamic";

export default async function Login({ searchParams }) {
  if (await getSession()) redirect("/");
  const { error } = await searchParams;
  return (
    <form action={login} className="form auth">
      <h1>Log in</h1>
      {error && <p className="err">{error}</p>}
      <label>Email<input name="email" type="email" required autoComplete="username" /></label>
      <label>Password<input name="password" type="password" required autoComplete="current-password" /></label>
      <button>Log in</button>
      <small>No account? <Link href="/register">Register</Link></small>
    </form>
  );
}
