import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { vSimilar, hydrate } from "@/lib/vector";

// GET /api/tasks/:id/similar -> tasks whose embeddings are closest to this task
export async function GET(_req, { params }) {
  const me = await getSession();
  if (!me) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const { id } = await params;
  return NextResponse.json(await hydrate(await vSimilar(id, 4), me));
}
