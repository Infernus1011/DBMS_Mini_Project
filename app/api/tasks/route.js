import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { q, BOARD } from "@/lib/db";

// GET /api/tasks?status=open -> the task board as JSON
export async function GET(req) {
  const me = await getSession();
  if (!me) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const status = new URL(req.url).searchParams.get("status");
  const rows = await q(`SELECT * FROM (${BOARD}) x ${status ? "WHERE status=?" : ""} ORDER BY deadline`, status ? [status] : [], me);
  return NextResponse.json(rows);
}
