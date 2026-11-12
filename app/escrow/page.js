import Link from "next/link";
import { q } from "@/lib/db";
import { requireUser } from "@/lib/auth";
import { money, when, Badge } from "@/lib/ui";

export const dynamic = "force-dynamic";

export default async function Escrow() {
  const me = await requireUser();
  // Students see only escrow they pay into or receive; admins see everything
  const rows = await q(`SELECT e.*, t.title, p.full_name payer, r.full_name payee FROM Escrow_Transactions e
    JOIN Tasks t ON t.task_id=e.task_id JOIN Users p ON p.user_id=e.payer_id JOIN Users r ON r.user_id=e.payee_id
    ${me.role === "admin" ? "" : "WHERE e.payer_id=? OR e.payee_id=?"} ORDER BY e.escrow_id DESC`,
    me.role === "admin" ? [] : [me.id, me.id], me);
  return (
    <>
      <h1>Escrow</h1>
      <div className="scroll"><table>
        <thead><tr><th>Task</th><th>Payer</th><th>Payee</th><th>Amount</th><th>Status</th><th>Held</th><th>Released</th></tr></thead>
        <tbody>{rows.map((e) => (
          <tr key={e.escrow_id}><td><Link href={`/tasks/${e.task_id}`}>{e.title}</Link></td><td>{e.payer}</td><td>{e.payee}</td>
            <td>{money(e.amount)}</td><td><Badge s={e.status} /></td><td>{when(e.held_at)}</td><td>{when(e.released_at)}</td></tr>))}
          {!rows.length && <tr><td colSpan={7}>No escrow transactions yet.</td></tr>}
        </tbody>
      </table></div>
    </>
  );
}
