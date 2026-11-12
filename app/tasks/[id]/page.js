import { notFound } from "next/navigation";
import Link from "next/link";
import { q } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { placeBid, acceptBid, completeTask, withdrawBid, updateTask, deleteTask } from "../../actions";
import { vSimilar, hydrate } from "@/lib/vector";
import { money, when, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

const local = (d) => { // Date -> value for <input type="datetime-local">
  const x = new Date(d); const p = (n) => String(n).padStart(2, "0");
  return `${x.getFullYear()}-${p(x.getMonth() + 1)}-${p(x.getDate())}T${p(x.getHours())}:${p(x.getMinutes())}`;
};

export default async function TaskPage({ params, searchParams }) {
  const me = await requireUser();
  const { id } = await params;
  const { error } = await searchParams;
  const [task] = await q(
    `SELECT t.*, c.category_name, u.full_name poster FROM Tasks t
     JOIN Categories c ON c.category_id=t.category_id JOIN Users u ON u.user_id=t.poster_id WHERE t.task_id=?`, [id], me);
  if (!task) notFound();
  const bids = await q(
    `SELECT b.*, u.full_name bidder, u.reputation_score FROM Bids b JOIN Users u ON u.user_id=b.bidder_id
     WHERE b.task_id=? ORDER BY b.bid_amount`, [id], me);
  const [esc] = await q("SELECT * FROM Escrow_Transactions WHERE task_id=?", [id], me);

  const similar = await hydrate(await vSimilar(id, 4), me);
  const isAdmin = me.role === "admin";
  const isPoster = task.poster_id === me.id;
  const canManage = isPoster || isAdmin;
  const open = task.status === "open";
  const hasActiveBid = bids.some((b) => b.bidder_id === me.id && b.status !== "withdrawn");
  const hidden = (b) => (<><input type="hidden" name="bid_id" value={b.bid_id} /><input type="hidden" name="task_id" value={id} /></>);

  return (
    <>
      <h1>{task.title}</h1>
      <p><Badge s={task.status} /> {task.category_name}, posted by <Link href={`/users/${task.poster_id}`}>{task.poster}</Link>, budget <b>{money(task.budget)}</b>, due {when(task.deadline)}</p>
      <p>{task.description}</p>
      {error && <p className="err">{error}</p>}

      {canManage && open && (
        <details className="form">
          <summary>Edit or delete this task</summary>
          <form action={updateTask} className="inner">
            <input type="hidden" name="task_id" value={id} />
            <label>Title<input name="title" maxLength={150} defaultValue={task.title} required /></label>
            <label>Description<textarea name="description" rows={3} defaultValue={task.description} required /></label>
            <label>Budget (₹)<input name="budget" type="number" min="1" step="0.01" defaultValue={task.budget} required /></label>
            <label>Deadline<input name="deadline" type="datetime-local" defaultValue={local(task.deadline)} required /></label>
            <button>Save changes</button>
          </form>
          <form action={deleteTask}><input type="hidden" name="task_id" value={id} /><button className="ghost">Delete task</button></form>
        </details>
      )}

      <h2>Bids</h2>
      <div className="scroll"><table>
        <thead><tr><th>Bidder</th><th>Amount</th><th>Proposal</th><th>Status</th><th></th></tr></thead>
        <tbody>{bids.map((b) => (
          <tr key={b.bid_id}>
            <td><Link href={`/users/${b.bidder_id}`}>{b.bidder}</Link> <small>({Number(b.reputation_score).toFixed(1)}★)</small></td>
            <td>{money(b.bid_amount)}</td><td>{b.proposal_message}</td><td><Badge s={b.status} /></td>
            <td className="acts">
              {open && b.status === "pending" && canManage && (
                <form action={acceptBid}>{hidden(b)}<button>Accept and fund escrow</button></form>)}
              {open && b.status === "pending" && b.bidder_id === me.id && (
                <form action={withdrawBid}>{hidden(b)}<button className="ghost">Withdraw</button></form>)}
            </td>
          </tr>))}
          {!bids.length && <tr><td colSpan={5}>No bids yet.</td></tr>}
        </tbody>
      </table></div>

      {esc && <>
        <h2>Escrow</h2>
        <p><Badge s={esc.status} /> {money(esc.amount)} held {when(esc.held_at)}{esc.released_at && <>, released {when(esc.released_at)}</>}</p>
      </>}

      {esc?.status === "held" && canManage && (
        <form action={completeTask} className="form">
          <h3>Mark complete, release payment and rate the worker</h3>
          <input type="hidden" name="task_id" value={id} />
          <label>Rating<select name="rating_value" defaultValue="5">{[5, 4, 3, 2, 1].map((n) => <option key={n}>{n}</option>)}</select></label>
          <label>Review<textarea name="review_text" rows={2} /></label>
          <button>Release {money(esc.amount)}</button>
        </form>)}

      {open && !isPoster && !hasActiveBid && (
        <form action={placeBid} className="form">
          <h3>Place a bid as {me.name}</h3>
          <input type="hidden" name="task_id" value={id} />
          <label>Amount (₹)<input name="bid_amount" type="number" min="1" step="0.01" required /></label>
          <label>Proposal<textarea name="proposal_message" rows={2} /></label>
          <button>Submit bid</button>
        </form>)}
    
      {similar.length > 0 && <>
        <h2>Similar tasks</h2>
        <ul className="plain">{similar.map((t) => (
          <li key={t.task_id}><Link href={`/tasks/${t.task_id}`}>{t.title}</Link> <small>{Math.round(t.score * 100)}% match</small> <Badge s={t.status} /></li>))}</ul>
      </>}
    </>
  );
}
