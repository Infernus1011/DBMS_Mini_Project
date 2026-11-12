import { q } from "@/lib/db";

/*
  Client for the Chroma vector service (vector-service/main.py).
  Every call fails soft: if the service is down the rest of the app keeps working,
  and the task can be pushed to the vector store later with "Re-index all tasks" on /admin.
*/
const BASE = process.env.VECTOR_URL || "http://127.0.0.1:8000";

async function call(path, init = {}) {
  try {
    const res = await fetch(`${BASE}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json" },
      signal: AbortSignal.timeout(8000),
      cache: "no-store",
    });
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  }
}

export const vectorUp = async () => (await call("/health")) !== null;

/** Create / update the vector of one task. */
export const vIndex = (t) =>
  call("/index", {
    method: "POST",
    body: JSON.stringify({
      task_id: t.task_id, title: t.title, description: t.description || "", category: t.category || "",
      budget: Number(t.budget), status: t.status, poster_id: t.poster_id,
    }),
  });

/** Read: semantic search. */
export const vSearch = async (query, k = 6, status = null) =>
  (await call("/search", { method: "POST", body: JSON.stringify({ query, k, status }) }))?.results ?? [];

/** Read: tasks similar to an already indexed task. */
export const vSimilar = async (id, k = 4) => (await call(`/similar/${id}?k=${k}`))?.results ?? [];

/** Delete. */
export const vDelete = (id) => call(`/task/${id}`, { method: "DELETE" });

/** Re-read a task from MySQL and push it to the vector store (used after create/edit/status change). */
export async function syncTask(me, id) {
  const [t] = await q(
    `SELECT t.task_id, t.title, t.description, t.budget, t.status, t.poster_id, c.category_name AS category
       FROM Tasks t JOIN Categories c ON c.category_id=t.category_id WHERE t.task_id=?`, [id], me);
  if (t) await vIndex(t);
}

/** Turn vector hits into task rows (from MySQL), keeping the vector ranking and score. */
export async function hydrate(hits, me) {
  if (!hits.length) return [];
  const rows = await q(
    `SELECT t.task_id, t.title, t.budget, t.status, t.deadline, c.category_name
       FROM Tasks t JOIN Categories c ON c.category_id=t.category_id WHERE t.task_id IN (?)`,
    [hits.map((h) => h.task_id)], me);
  const byId = new Map(rows.map((r) => [r.task_id, r]));
  return hits.filter((h) => byId.has(h.task_id)).map((h) => ({ ...byId.get(h.task_id), score: h.score }));
}

/** Keyword search with the MySQL FULLTEXT index, for comparison with semantic search. */
export const keywordSearch = (text, me, limit = 6) =>
  q(`SELECT t.task_id, t.title, t.budget, t.status, t.deadline, c.category_name,
            MATCH(t.title, t.description) AGAINST (? IN NATURAL LANGUAGE MODE) AS score
       FROM Tasks t JOIN Categories c ON c.category_id=t.category_id
      WHERE MATCH(t.title, t.description) AGAINST (? IN NATURAL LANGUAGE MODE)
      ORDER BY score DESC LIMIT ?`, [text, text, limit], me);
