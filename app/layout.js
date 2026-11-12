import "./globals.css";
import Link from "next/link";
import { getSession } from "@/lib/auth";
import { logout } from "./auth-actions";

export const metadata = { title: "Campus Bid", description: "Micro-task bidding for campus" };

export default async function RootLayout({ children }) {
  const me = await getSession();
  return (
    <html lang="en">
      <body>
        <header className="top">
          <Link href="/" className="brand">Campus Bid</Link>
          {me ? (
            <nav>
              <Link href="/">Overview</Link>
              <Link href="/tasks">Tasks</Link>
              <Link href="/search">Search</Link>
              <Link href="/escrow">Escrow</Link>
              <Link href="/users">People</Link>
              {me.role === "admin" && <Link href="/admin">Admin</Link>}
              <span className="who">
                <Link href={`/users/${me.id}`}>{me.name}</Link> <small>({me.role})</small>
              </span>
              <form action={logout}><button className="ghost">Log out</button></form>
            </nav>
          ) : (
            <nav>
              <Link href="/login">Log in</Link>
              <Link href="/register">Register</Link>
            </nav>
          )}
        </header>
        <main>{children}</main>
      </body>
    </html>
  );
}
