import Link from "next/link";
import { q } from "@/lib/db";
import { requireUser } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function Users() {
  const me = await requireUser();
  const users = await q(`SELECT u.user_id, u.full_name, u.department, u.role, u.reputation_score,
      COUNT(b.bid_id) total_bids, COALESCE(SUM(b.status='accepted'),0) won
    FROM Users u LEFT JOIN Bids b ON b.bidder_id=u.user_id
    GROUP BY u.user_id, u.full_name, u.department, u.role, u.reputation_score ORDER BY u.reputation_score DESC`, [], me);
  return (
    <>
      <h1>People</h1>
      <div className="scroll"><table>
        <thead><tr><th>Name</th><th>Dept</th><th>Reputation</th><th>Bids won</th></tr></thead>
        <tbody>{users.map((u) => (
          <tr key={u.user_id}><td><Link href={`/users/${u.user_id}`}>{u.full_name}</Link></td><td>{u.department}</td>
            <td>{Number(u.reputation_score).toFixed(2)}★</td><td>{u.won} / {u.total_bids}</td></tr>))}</tbody>
      </table></div>
    </>
  );
}
