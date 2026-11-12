import { notFound } from "next/navigation";
import Link from "next/link";
import { q } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { money, when, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

export default async function Profile({ params }) {
  const me = await requireUser();
  const { id } = await params;
  const [u] = await q("SELECT user_id, full_name, department, role, reputation_score, created_at FROM Users WHERE user_id=?", [id], me);
  if (!u) notFound();
  const [money_] = await q(`SELECT
      COALESCE((SELECT SUM(amount) FROM Escrow_Transactions WHERE payee_id=? AND status='released'),0) earned,
      COALESCE((SELECT SUM(amount) FROM Escrow_Transactions WHERE payer_id=? AND status='released'),0) spent`, [id, id], me);
  const reviews = await q(`SELECT r.*, rater.full_name rater, t.title FROM Ratings r
    JOIN Users rater ON rater.user_id=r.rater_id JOIN Tasks t ON t.task_id=r.task_id
    WHERE r.rated_id=? ORDER BY r.rating_id DESC`, [id], me);
  const posted = await q("SELECT task_id, title, status, budget FROM Tasks WHERE poster_id=? ORDER BY task_id DESC", [id], me);
  const bids = await q(`SELECT b.bid_id, b.bid_amount, b.status, t.task_id, t.title FROM Bids b JOIN Tasks t ON t.task_id=b.task_id
    WHERE b.bidder_id=? ORDER BY b.bid_id DESC`, [id], me);

  return (
    <>
      <h1>{u.full_name}</h1>
      <p>{u.department}, member since {when(u.created_at)} {u.role === "admin" && <Badge s="admin" />}</p>
      <div className="stats">
        <div><b>{Number(u.reputation_score).toFixed(2)}★</b><span>reputation</span></div>
        <div><b>{reviews.length}</b><span>reviews received</span></div>
        <div><b>{money(money_.earned)}</b><span>earned</span></div>
        <div><b>{money(money_.spent)}</b><span>spent</span></div>
      </div>

      <h2>Reviews</h2>
      <ul className="plain">{reviews.map((r) => (
        <li key={r.rating_id}><b>{r.rating_value}★</b> from {r.rater} for “{r.title}”{r.review_text && <>: {r.review_text}</>}</li>))}
        {!reviews.length && <li>No reviews yet.</li>}</ul>

      <h2>Tasks posted</h2>
      <ul className="plain">{posted.map((t) => (
        <li key={t.task_id}><Link href={`/tasks/${t.task_id}`}>{t.title}</Link> {money(t.budget)} <Badge s={t.status} /></li>))}
        {!posted.length && <li>None.</li>}</ul>

      <h2>Bids placed</h2>
      <ul className="plain">{bids.map((b) => (
        <li key={b.bid_id}><Link href={`/tasks/${b.task_id}`}>{b.title}</Link> {money(b.bid_amount)} <Badge s={b.status} /></li>))}
        {!bids.length && <li>None.</li>}</ul>
    </>
  );
}
