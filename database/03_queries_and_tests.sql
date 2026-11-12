/*
  CAMPUS BID PLATFORM - ADVANCED QUERIES AND TESTS
  Run 02_advanced.sql first.

  HOW TO USE: run ONE numbered block at a time (select it, Ctrl+Enter in Workbench)
  and screenshot the result for the report.
  Blocks marked "EXPECTED ERROR" are meant to fail: the error message is the evidence.
*/

USE campus_bid_platform;

/* ---------- A. COMMON TABLE EXPRESSION (non-recursive) ----------
   How much each poster saves against budget using the lowest live bid. */
WITH bid_stats AS (
    SELECT task_id, COUNT(*) AS bids, MIN(bid_amount) AS lowest, ROUND(AVG(bid_amount), 2) AS average
      FROM Bids
     WHERE status <> 'withdrawn'
     GROUP BY task_id
)
SELECT t.task_id, t.title, t.budget, bs.bids, bs.lowest, bs.average,
       ROUND(t.budget - bs.lowest, 2) AS saving_vs_budget
  FROM Tasks t
  JOIN bid_stats bs ON bs.task_id = t.task_id
 ORDER BY saving_vs_budget DESC;

/* ---------- B. RECURSIVE CTE 1: category tree ---------- */
WITH RECURSIVE category_tree AS (
    SELECT category_id, category_name, parent_category_id,
           0 AS depth,
           CAST(category_name AS CHAR(300)) AS path
      FROM Categories
     WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, c.category_name, c.parent_category_id,
           ct.depth + 1,
           CONCAT(ct.path, ' > ', c.category_name)
      FROM Categories c
      JOIN category_tree ct ON c.parent_category_id = ct.category_id
)
SELECT CONCAT(REPEAT('    ', depth), category_name) AS category, depth, path
  FROM category_tree
 ORDER BY path;

/* ---------- C. RECURSIVE CTE 2: tasks per top-level category, including sub-categories ---------- */
WITH RECURSIVE cat_roots AS (
    SELECT category_id, category_id AS root_id, category_name AS root_name
      FROM Categories WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, r.root_id, r.root_name
      FROM Categories c JOIN cat_roots r ON c.parent_category_id = r.category_id
)
SELECT r.root_name AS top_category, COUNT(t.task_id) AS tasks, COALESCE(SUM(t.budget), 0) AS total_budget
  FROM cat_roots r
  LEFT JOIN Tasks t ON t.category_id = r.category_id
 GROUP BY r.root_id, r.root_name
 ORDER BY tasks DESC;

/* ---------- D. RECURSIVE CTE 3: day-by-day countdown to each open task's deadline ---------- */
WITH RECURSIVE countdown AS (
    SELECT task_id, title, CURDATE() AS day, DATE(deadline) AS due
      FROM Tasks
     WHERE status = 'open' AND deadline >= CURDATE()
    UNION ALL
    SELECT task_id, title, day + INTERVAL 1 DAY, due
      FROM countdown
     WHERE day < due
)
SELECT task_id, title, MIN(day) AS from_day, MAX(day) AS due_day, COUNT(*) - 1 AS days_left
  FROM countdown
 GROUP BY task_id, title;

/* ---------- E. FUNCTION ---------- */
SELECT user_id, full_name, reputation_score AS stored, fn_user_reputation(user_id) AS computed
  FROM Users;

/* ---------- F. TRANSACTION with SAVEPOINT (manual) ---------- */
START TRANSACTION;
UPDATE Users SET phone = '9999999999' WHERE user_id = 5;
SAVEPOINT after_phone;
UPDATE Users SET department = 'TEMP' WHERE user_id = 5;
ROLLBACK TO SAVEPOINT after_phone;
SELECT user_id, phone, department FROM Users WHERE user_id = 5;   -- phone changed, department not
ROLLBACK;
SELECT user_id, phone, department FROM Users WHERE user_id = 5;   -- both back to original

/* ---------- G. TRIGGER TESTS ---------- */
-- G1 EXPECTED ERROR: task 3 is posted by user 4, so user 4 cannot bid on it
CALL sp_place_bid(3, 4, 250.00, 'Bidding on my own task');

-- G2 EXPECTED ERROR: user 2 already has an active bid on task 3
CALL sp_place_bid(3, 2, 260.00, 'Second bid');

-- G3 EXPECTED ERROR: task 1 is in_progress, so it is closed for bids
CALL sp_place_bid(1, 5, 400.00, 'Too late');

-- G4 EXPECTED ERROR: cannot rate yourself
INSERT INTO Ratings (task_id, rater_id, rated_id, rating_value) VALUES (1, 1, 1, 5);

-- G5 works: user 5 bids on task 3
CALL sp_place_bid(3, 5, 250.00, 'I can cover this topic well.');

/* ---------- H. ACCEPT A BID (procedure + transaction) ---------- */
-- H1 EXPECTED ERROR: user 5 is not the poster of task 3 (poster is user 4)
SET @new_bid = (SELECT MAX(bid_id) FROM Bids);
CALL sp_accept_bid(@new_bid, 5);

-- H2 works: user 4 accepts
CALL sp_accept_bid(@new_bid, 4);
SELECT bid_id, task_id, bidder_id, status FROM Bids WHERE task_id = 3;
SELECT task_id, status FROM Tasks WHERE task_id = 3;
SELECT escrow_id, task_id, payer_id, payee_id, amount, status FROM Escrow_Transactions WHERE task_id = 3;

/* ---------- I. COMPLETE TASK (release escrow, rating, trigger updates reputation) ---------- */
SELECT user_id, full_name, reputation_score FROM Users WHERE user_id = 5;          -- before
CALL sp_complete_task(3, 4, 5, 'Clear and quick.');
SELECT user_id, full_name, reputation_score FROM Users WHERE user_id = 5;          -- after: 5.00
SELECT escrow_id, status, released_at FROM Escrow_Transactions WHERE task_id = 3;
SELECT * FROM Audit_Log ORDER BY log_id;                                           -- trigger-written audit trail

/* ---------- J. INDEX USE ---------- */
EXPLAIN SELECT task_id, title FROM Tasks WHERE status = 'open' ORDER BY deadline;
SELECT task_id, title, MATCH(title, description) AGAINST ('website portfolio' IN NATURAL LANGUAGE MODE) AS score
  FROM Tasks
 WHERE MATCH(title, description) AGAINST ('website portfolio' IN NATURAL LANGUAGE MODE);

/* ---------- K. ACCESS CONTROL ----------
   Connect as app_student (Workbench: new connection, user app_student, password Student@123)
   and run these. Then repeat L as app_admin. */

-- K1 works: students can read data
SELECT task_id, title, status FROM Tasks;

-- K2 EXPECTED ERROR (as app_student): no direct writes
UPDATE Tasks SET budget = 1 WHERE task_id = 4;

-- K3 EXPECTED ERROR (as app_student): password hashes are hidden
SELECT email, password_hash FROM Users;

-- K4 EXPECTED ERROR (as app_student): cannot touch categories
DELETE FROM Categories WHERE category_id = 9;

/* ---------- L. ADMIN (connect as app_admin / Admin@123) ---------- */
-- L1 works: admins manage categories
INSERT INTO Categories (category_name, description) VALUES ('Video Editing', 'Short videos and reels');
-- L2 EXPECTED ERROR (as app_admin): admin cannot edit bids directly either
UPDATE Bids SET bid_amount = 1 WHERE bid_id = 1;
