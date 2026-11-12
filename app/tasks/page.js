import Link from "next/link";
import { q, BOARD } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { postTask } from "../actions";
import { money, when, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

export default async function Tasks({ searchParams }) {
  const me = await requireUser();
  const { status = "", error } = await searchParams;
  const tasks = await q(
    `SELECT * FROM (${BOARD}) x ${status ? "WHERE status=?" : ""} ORDER BY deadline`, status ? [status] : [], me);
  const cats = await q("SELECT category_id, category_name FROM Categories ORDER BY category_name", [], me);

  return (
    <>
      <h1>Tasks</h1>
      {error && <p className="err">{error}</p>}
      <p className="filters">
        {["", "open", "in_progress", "completed"].map((s) => (
          <Link key={s} href={s ? `/tasks?status=${s}` : "/tasks"} className={status === s ? "on" : ""}>{s ? s.replace("_", " ") : "all"}</Link>))}
      </p>
      <div className="grid">{tasks.map((t) => (
        <Link key={t.task_id} href={`/tasks/${t.task_id}`} className="card">
          <div className="row"><b>{t.title}</b><Badge s={t.status} /></div>
          <small>{t.category_name}, posted by {t.poster_name}</small>
          <div className="row"><span>{money(t.budget)}</span><small>{t.bid_count} bid{t.bid_count == 1 ? "" : "s"}, due {when(t.deadline)}</small></div>
        </Link>))}
        {!tasks.length && <p>No tasks match this filter.</p>}
      </div>

      <h2>Post a task</h2>
      <form action={postTask} className="form">
        <label>Category<select name="category_id" required>{cats.map((c) => <option key={c.category_id} value={c.category_id}>{c.category_name}</option>)}</select></label>
        <label>Title<input name="title" maxLength={150} required /></label>
        <label>Description<textarea name="description" rows={3} required /></label>
        <label>Budget (₹)<input name="budget" type="number" min="1" step="0.01" required /></label>
        <label>Deadline<input name="deadline" type="datetime-local" required /></label>
        <button>Post task as {me.name}</button>
      </form>
    </>
  );
}
