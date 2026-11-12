import Link from "next/link";
import { q, BOARD } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { money, when, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

export default async function Home() {
  const me = await requireUser();
  const [s] = await q(`SELECT
      (SELECT COUNT(*) FROM Tasks WHERE status='open') AS open_tasks,
      (SELECT COUNT(*) FROM Bids WHERE status='pending') AS pending_bids,
      (SELECT COALESCE(SUM(amount),0) FROM Escrow_Transactions WHERE status='held') AS held,
      (SELECT COALESCE(SUM(amount),0) FROM Escrow_Transactions WHERE status='released') AS released`, [], me);
  const board = await q(`SELECT * FROM (${BOARD}) x ORDER BY task_id DESC`, [], me);
  const top = await q(`SELECT u.user_id, u.full_name, COUNT(r.rating_id) n, ROUND(AVG(r.rating_value),2) avg
      FROM Users u JOIN Ratings r ON u.user_id=r.rated_id GROUP BY u.user_id, u.full_name ORDER BY avg DESC, n DESC LIMIT 5`, [], me);

  return (
    <>
      <h1>What’s happening on campus</h1>
      <div className="stats">
        <div><b>{s.open_tasks}</b><span>open tasks</span></div>
        <div><b>{s.pending_bids}</b><span>bids waiting</span></div>
        <div><b>{money(s.held)}</b><span>held in escrow</span></div>
        <div><b>{money(s.released)}</b><span>paid out</span></div>
      </div>

      <h2>Task board</h2>
      <div className="scroll"><table>
        <thead><tr><th>Task</th><th>Category</th><th>Poster</th><th>Budget</th><th>Bids</th><th>Lowest bid</th><th>Deadline</th><th>Status</th></tr></thead>
        <tbody>{board.map((t) => (
          <tr key={t.task_id}>
            <td><Link href={`/tasks/${t.task_id}`}>{t.title}</Link></td>
            <td>{t.category_name}</td><td>{t.poster_name}</td><td>{money(t.budget)}</td>
            <td>{t.bid_count}</td><td>{t.lowest_bid ? money(t.lowest_bid) : "-"}</td>
            <td>{when(t.deadline)}</td><td><Badge s={t.status} /></td>
          </tr>))}</tbody>
      </table></div>

      <h2>Top rated</h2>
      <ol className="plain">{top.map((u) => <li key={u.user_id}><Link href={`/users/${u.user_id}`}><b>{u.full_name}</b></Link> {u.avg} / 5 from {u.n} rating{u.n > 1 ? "s" : ""}</li>)}</ol>
    </>
  );
}
