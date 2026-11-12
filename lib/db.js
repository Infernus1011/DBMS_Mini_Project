import mysql from "mysql2/promise";

/*
  Two connection pools, one per MySQL account:
    app_student  - SELECT on data tables + EXECUTE on stored procedures
    app_admin    - the above plus category management and role changes
  Which pool a request uses depends on the role in the signed-in user's session,
  so database-level GRANTs back up the checks made in the app.
*/
const g = globalThis;
const make = (user, password) =>
  mysql.createPool({
    host: process.env.DB_HOST || "localhost",
    port: Number(process.env.DB_PORT || 3306),
    user,
    password,
    database: process.env.DB_NAME || "campus_bid_platform",
    connectionLimit: 6,
  });

const pools =
  g._pools ||
  (g._pools = {
    student: make(process.env.DB_STUDENT_USER || "app_student", process.env.DB_STUDENT_PASSWORD || ""),
    admin: make(process.env.DB_ADMIN_USER || "app_admin", process.env.DB_ADMIN_PASSWORD || ""),
  });

export const poolFor = (me) => (me?.role === "admin" ? pools.admin : pools.student);

export const BOARD = `SELECT t.task_id, t.title, c.category_name, u.full_name AS poster_name,
  t.budget, t.deadline, t.status, COUNT(b.bid_id) AS bid_count, MIN(b.bid_amount) AS lowest_bid
  FROM Tasks t JOIN Categories c ON t.category_id=c.category_id JOIN Users u ON t.poster_id=u.user_id
  LEFT JOIN Bids b ON t.task_id=b.task_id AND b.status<>'withdrawn'
  GROUP BY t.task_id, t.title, c.category_name, u.full_name, t.budget, t.deadline, t.status`;

/** Run a SELECT/DML as the right MySQL account for this user (null = student account). */
export async function q(sql, params = [], me = null) {
  const [rows] = await poolFor(me).query(sql, params);
  return rows;
}

/** CALL a stored procedure; returns the first result set (or []). */
export async function call(me, name, args = []) {
  const marks = args.map(() => "?").join(",");
  const [res] = await poolFor(me).query(`CALL ${name}(${marks})`, args);
  return Array.isArray(res) && Array.isArray(res[0]) ? res[0] : [];
}
