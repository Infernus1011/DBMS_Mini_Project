import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { vSearch, hydrate, keywordSearch } from "@/lib/vector";

// GET /api/search?q=...&status=open  -> { semantic: [...], keyword: [...] }
export async function GET(req) {
  const me = await getSession();
  if (!me) return NextResponse.json({ error: "Not signed in" }, { status: 401 });
  const url = new URL(req.url);
  const text = (url.searchParams.get("q") || "").trim();
  const status = url.searchParams.get("status") || null;
  if (!text) return NextResponse.json({ semantic: [], keyword: [] });
  const [semantic, keyword] = await Promise.all([
    hydrate(await vSearch(text, 6, status), me),
    keywordSearch(text, me),
  ]);
  return NextResponse.json({ semantic, keyword });
}
