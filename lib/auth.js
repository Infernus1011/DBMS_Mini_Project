import crypto from "node:crypto";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

/*
  Passwords: scrypt (memory-hard, salted) from Node's built-in crypto, stored as
  "scrypt$<salt hex>$<hash hex>" in Users.password_hash.
  Sessions: an HMAC-signed, httpOnly cookie holding {id, name, role, exp}.
*/
const COOKIE = "cb_session";
const MAX_AGE = 8 * 60 * 60; // seconds

const secret = () => process.env.SESSION_SECRET || "dev-only-secret-change-me";
const sign = (payload) => crypto.createHmac("sha256", secret()).update(payload).digest("base64url");

export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 64);
  return `scrypt$${salt.toString("hex")}$${hash.toString("hex")}`;
}

export function verifyPassword(password, stored) {
  const [alg, saltHex, hashHex] = String(stored || "").split("$");
  if (alg !== "scrypt" || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, "hex");
  const actual = crypto.scryptSync(password, Buffer.from(saltHex, "hex"), expected.length);
  return crypto.timingSafeEqual(actual, expected);
}

export async function createSession(user) {
  const payload = Buffer.from(
    JSON.stringify({ id: Number(user.user_id), name: user.full_name, role: user.role, exp: Date.now() + MAX_AGE * 1000 })
  ).toString("base64url");
  (await cookies()).set(COOKIE, `${payload}.${sign(payload)}`, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: MAX_AGE,
    secure: process.env.NODE_ENV === "production",
  });
}

export async function destroySession() {
  (await cookies()).delete(COOKIE);
}

export async function getSession() {
  const value = (await cookies()).get(COOKIE)?.value;
  if (!value) return null;
  const [payload, sig] = value.split(".");
  if (!payload || !sig) return null;
  const a = Buffer.from(sig);
  const b = Buffer.from(sign(payload));
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, "base64url").toString());
    return data.exp > Date.now() ? data : null;
  } catch {
    return null;
  }
}

export async function requireUser() {
  const me = await getSession();
  if (!me) redirect("/login");
  return me;
}

export async function requireAdmin() {
  const me = await requireUser();
  if (me.role !== "admin") redirect("/");
  return me;
}
