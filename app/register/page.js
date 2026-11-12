import Link from "next/link";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { register } from "../auth-actions";

export const dynamic = "force-dynamic";

export default async function Register({ searchParams }) {
  if (await getSession()) redirect("/");
  const { error } = await searchParams;
  return (
    <form action={register} className="form auth">
      <h1>Create an account</h1>
      {error && <p className="err">{error}</p>}
      <label>Full name<input name="full_name" maxLength={100} required /></label>
      <label>Email<input name="email" type="email" maxLength={150} required autoComplete="username" /></label>
      <label>Department<input name="department" maxLength={80} required /></label>
      <label>Phone (optional)<input name="phone" maxLength={20} /></label>
      <label>Password (8+ characters)<input name="password" type="password" minLength={8} required autoComplete="new-password" /></label>
      <button>Register</button>
      <small>Already registered? <Link href="/login">Log in</Link></small>
    </form>
  );
}
