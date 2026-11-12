"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { call, q } from "@/lib/db";
import { requireUser, requireAdmin } from "@/lib/auth";
import { syncTask, vDelete, vIndex } from "@/lib/vector";

// "2026-12-01T10:30" (datetime-local) -> "2026-12-01 10:30:00"
const dt = (s) => {
  const v = String(s || "").replace("T", " ");
  return v.length === 16 ? `${v}:00` : v;
};

/** Run a database action. On failure go back to `back` with the DB's message in ?error= */
async function run(back, fn) {
  try {
    const out = await fn();
    revalidatePath("/", "layout");
    return out;
  } catch (e) {
    redirect(`${back}?error=${encodeURIComponent(e.sqlMessage || e.message || "Something went wrong")}`);
  }
}

export async function postTask(fd) {
  const me = await requireUser();
  const [row] = await run("/tasks", () =>
    call(me, "sp_post_task", [me.id, fd.get("category_id"), fd.get("title"), fd.get("description"), fd.get("budget"), dt(fd.get("deadline"))])
  );
  await syncTask(me, row.task_id); // vector store: create
  redirect("/tasks");
}

export async function updateTask(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () =>
    call(me, "sp_update_task", [id, me.id, fd.get("title"), fd.get("description"), fd.get("budget"), dt(fd.get("deadline"))])
  );
  await syncTask(me, id); // vector store: update (re-embed the edited text)
  redirect(`/tasks/${id}`);
}

export async function deleteTask(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () => call(me, "sp_delete_task", [id, me.id]));
  await vDelete(id); // vector store: delete
  redirect("/tasks");
}

export async function placeBid(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () => call(me, "sp_place_bid", [id, me.id, fd.get("bid_amount"), fd.get("proposal_message")]));
  redirect(`/tasks/${id}`);
}

export async function withdrawBid(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () => call(me, "sp_withdraw_bid", [fd.get("bid_id"), me.id]));
  redirect(`/tasks/${id}`);
}

// Accept bid: one transaction inside the sp_accept_bid procedure
export async function acceptBid(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () => call(me, "sp_accept_bid", [fd.get("bid_id"), me.id]));
  await syncTask(me, id); // status metadata -> in_progress
  redirect(`/tasks/${id}`);
}

// Complete task: release escrow + rating (reputation refreshed by a trigger)
export async function completeTask(fd) {
  const me = await requireUser();
  const id = fd.get("task_id");
  await run(`/tasks/${id}`, () =>
    call(me, "sp_complete_task", [id, me.id, fd.get("rating_value"), fd.get("review_text") || null])
  );
  await syncTask(me, id); // status metadata -> completed
  redirect(`/tasks/${id}`);
}

/* ---------- admin only (runs on the app_admin MySQL account) ---------- */

export async function addCategory(fd) {
  const me = await requireAdmin();
  await run("/admin", () =>
    q("INSERT INTO Categories (category_name, description, parent_category_id) VALUES (?,?,?)",
      [fd.get("category_name"), fd.get("description") || null, fd.get("parent_category_id") || null], me)
  );
  redirect("/admin");
}

export async function deleteCategory(fd) {
  const me = await requireAdmin();
  await run("/admin", () => q("DELETE FROM Categories WHERE category_id=?", [fd.get("category_id")], me));
  redirect("/admin");
}

export async function setRole(fd) {
  const me = await requireAdmin();
  const uid = Number(fd.get("user_id"));
  if (uid === me.id) redirect("/admin?error=" + encodeURIComponent("You cannot change your own role."));
  await run("/admin", () => q("UPDATE Users SET role=? WHERE user_id=?", [fd.get("role") === "admin" ? "admin" : "student", uid], me));
  redirect("/admin");
}

// Push every task in MySQL into the vector store (first-time load, or after the service was down)
export async function reindexAll() {
  const me = await requireAdmin();
  const tasks = await q(
    `SELECT t.task_id, t.title, t.description, t.budget, t.status, t.poster_id, c.category_name AS category
       FROM Tasks t JOIN Categories c ON c.category_id=t.category_id`, [], me);
  let ok = 0;
  for (const t of tasks) if (await vIndex(t)) ok++;
  redirect(`/admin?msg=${encodeURIComponent(`Indexed ${ok} of ${tasks.length} tasks in the vector store.`)}`);
}
