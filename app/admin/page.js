import { q } from "@/lib/db";
import { requireAdmin } from "@/lib/auth";
import { addCategory, deleteCategory, setRole, reindexAll } from "../actions";
import { vectorUp } from "@/lib/vector";
import { money, when } from "@/lib/ui";

export const dynamic = "force-dynamic";

export default async function Admin({ searchParams }) {
  const me = await requireAdmin();
  const { error, msg } = await searchParams;
  const vecUp = await vectorUp();

  const cats = await q(`SELECT c.category_id, c.category_name, p.category_name parent, COUNT(t.task_id) tasks
    FROM Categories c LEFT JOIN Categories p ON p.category_id=c.parent_category_id
    LEFT JOIN Tasks t ON t.category_id=c.category_id
    GROUP BY c.category_id, c.category_name, p.category_name ORDER BY c.category_id`, [], me);
  const users = await q("SELECT user_id, full_name, email, role FROM Users ORDER BY user_id", [], me);
  const accept = await q(`SELECT c.category_name, COUNT(DISTINCT t.task_id) tasks, COUNT(b.bid_id) bids,
      COALESCE(SUM(b.status='accepted'),0) accepted,
      ROUND(100*SUM(b.status='accepted')/NULLIF(COUNT(b.bid_id),0),1) rate
    FROM Categories c LEFT JOIN Tasks t ON t.category_id=c.category_id LEFT JOIN Bids b ON b.task_id=t.task_id
    GROUP BY c.category_id, c.category_name HAVING bids > 0 ORDER BY rate DESC`, [], me);
  const flow = await q("SELECT status, COUNT(*) n, COALESCE(SUM(amount),0) total FROM Escrow_Transactions GROUP BY status", [], me);
  const audit = await q("SELECT * FROM Audit_Log ORDER BY log_id DESC LIMIT 10", [], me);

  return (
    <>
      <h1>Admin dashboard</h1>
      {error && <p className="err">{error}</p>}
      {msg && <p><b>{msg}</b></p>}

      <h2>Vector search</h2>
      <p>Service: <b>{vecUp ? "running" : "not reachable (start vector-service)"}</b></p>
      <form action={reindexAll}><button disabled={!vecUp}>Re-index all tasks</button></form>

      <h2>Bid acceptance by category</h2>
      <div className="scroll"><table>
        <thead><tr><th>Category</th><th>Tasks</th><th>Bids</th><th>Accepted</th><th>Rate</th></tr></thead>
        <tbody>{accept.map((r) => <tr key={r.category_name}><td>{r.category_name}</td><td>{r.tasks}</td><td>{r.bids}</td><td>{r.accepted}</td><td>{r.rate}%</td></tr>)}</tbody>
      </table></div>

      <h2>Money flow</h2>
      <div className="stats">{flow.map((f) => <div key={f.status}><b>{money(f.total)}</b><span>{f.status} ({f.n})</span></div>)}</div>

      <h2>Categories</h2>
      <div className="scroll"><table>
        <thead><tr><th>Name</th><th>Parent</th><th>Tasks</th><th></th></tr></thead>
        <tbody>{cats.map((c) => (
          <tr key={c.category_id}><td>{c.category_name}</td><td>{c.parent || "-"}</td><td>{c.tasks}</td>
            <td><form action={deleteCategory}><input type="hidden" name="category_id" value={c.category_id} /><button className="ghost">Delete</button></form></td></tr>))}</tbody>
      </table></div>
      <form action={addCategory} className="form">
        <h3>Add category</h3>
        <label>Name<input name="category_name" maxLength={80} required /></label>
        <label>Description<input name="description" maxLength={255} /></label>
        <label>Parent<select name="parent_category_id"><option value="">None (top level)</option>{cats.map((c) => <option key={c.category_id} value={c.category_id}>{c.category_name}</option>)}</select></label>
        <button>Add</button>
      </form>

      <h2>User roles</h2>
      <div className="scroll"><table>
        <thead><tr><th>User</th><th>Email</th><th>Role</th><th></th></tr></thead>
        <tbody>{users.map((u) => (
          <tr key={u.user_id}><td>{u.full_name}</td><td>{u.email}</td><td>{u.role}</td>
            <td>{u.user_id !== me.id && (
              <form action={setRole}><input type="hidden" name="user_id" value={u.user_id} />
                <input type="hidden" name="role" value={u.role === "admin" ? "student" : "admin"} />
                <button className="ghost">Make {u.role === "admin" ? "student" : "admin"}</button></form>)}</td></tr>))}</tbody>
      </table></div>

      <h2>Recent audit log</h2>
      <ul className="plain">{audit.map((a) => <li key={a.log_id}>{when(a.changed_at)}: {a.table_name} #{a.record_id} {a.action} {a.old_value} → {a.new_value}</li>)}
        {!audit.length && <li>No changes recorded yet.</li>}</ul>
    </>
  );
}
