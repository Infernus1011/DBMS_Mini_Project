import Link from "next/link";
import { q } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { vSearch, hydrate, keywordSearch, vectorUp } from "@/lib/vector";
import { money, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

const List = ({ rows, pct }) => (
  <ul className="plain">{rows.map((t) => (
    <li key={t.task_id}>
      <Link href={`/tasks/${t.task_id}`}>{t.title}</Link> <small>{t.category_name}, {money(t.budget)}</small>{" "}
      <Badge s={t.status} /> {pct && <small>{Math.round(t.score * 100)}% match</small>}
    </li>))}
    {!rows.length && <li>No results.</li>}
  </ul>
);

export default async function Search({ searchParams }) {
  const me = await requireUser();
  const { q: text = "", status = "" } = await searchParams;
  const up = await vectorUp();

  let semantic = [], keyword = [];
  if (text.trim()) {
    semantic = await hydrate(await vSearch(text, 6, status || null), me);
    keyword = (await keywordSearch(text, me)).filter((t) => !status || t.status === status);
  }

  // Recommendations: tasks similar to the ones this user has bid on
  const mine = await q(
    `SELECT t.title, t.description FROM Bids b JOIN Tasks t ON t.task_id=b.task_id
      WHERE b.bidder_id=? ORDER BY b.bid_id DESC LIMIT 3`, [me.id], me);
  const profile = mine.map((t) => `${t.title}. ${t.description}`).join(" ");
  let picks = [];
  if (!text.trim() && profile) {
    const bidOn = new Set((await q("SELECT task_id FROM Bids WHERE bidder_id=?", [me.id], me)).map((r) => r.task_id));
    picks = (await hydrate(await vSearch(profile, 8, "open"), me)).filter((t) => !bidOn.has(t.task_id)).slice(0, 4);
  }

  return (
    <>
      <h1>Search tasks</h1>
      {!up && <p className="err">The vector service is not running, so semantic search is unavailable. Keyword search still works.</p>}
      <form className="form" style={{ maxWidth: 640 }}>
        <label>Describe what you are looking for<input name="q" defaultValue={text} placeholder="e.g. someone to make branding for our club" /></label>
        <label>Status<select name="status" defaultValue={status}><option value="">any</option><option value="open">open</option><option value="in_progress">in progress</option><option value="completed">completed</option></select></label>
        <button>Search</button>
      </form>

      {text.trim() ? (
        <div className="grid" style={{ marginTop: 24 }}>
          <div><h2>Semantic (vector, meaning)</h2><List rows={semantic} pct /></div>
          <div><h2>Keyword (MySQL FULLTEXT)</h2><List rows={keyword} /></div>
        </div>
      ) : picks.length > 0 && (
        <><h2>Recommended for you</h2><p><small>Open tasks similar to ones you have bid on.</small></p><List rows={picks} pct /></>
      )}
    </>
  );
}
