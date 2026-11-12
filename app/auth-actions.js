"use server";
import { redirect } from "next/navigation";
import { call } from "@/lib/db";
import { hashPassword, verifyPassword, createSession, destroySession } from "@/lib/auth";

const go = (path, error) => redirect(`${path}?error=${encodeURIComponent(error)}`);

export async function login(fd) {
  const email = String(fd.get("email") || "").trim().toLowerCase();
  const password = String(fd.get("password") || "");
  let user = null;
  try {
    [user] = await call(null, "sp_get_login", [email]);
  } catch {
    go("/login", "Could not reach the database.");
  }
  if (!user || !verifyPassword(password, user.password_hash)) go("/login", "Invalid email or password.");
  await createSession(user);
  redirect("/");
}

export async function register(fd) {
  const name = String(fd.get("full_name") || "").trim();
  const email = String(fd.get("email") || "").trim().toLowerCase();
  const password = String(fd.get("password") || "");
  const dept = String(fd.get("department") || "").trim();
  const phone = String(fd.get("phone") || "").trim() || null;
  if (!name || !email || !dept) go("/register", "Name, email and department are required.");
  if (password.length < 8) go("/register", "Password must be at least 8 characters.");

  let row;
  try {
    [row] = await call(null, "sp_register_user", [name, email, hashPassword(password), dept, phone]);
  } catch (e) {
    go("/register", e.code === "ER_DUP_ENTRY" ? "That email is already registered." : e.sqlMessage || "Could not register.");
  }
  await createSession({ user_id: row.user_id, full_name: name, role: "student" });
  redirect("/");
}

export async function logout() {
  await destroySession();
  redirect("/login");
}
