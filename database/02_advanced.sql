/*
  CAMPUS BID PLATFORM - ADVANCED SQL BATCH
  MySQL 8.0+

  Run AFTER campus_bid_platform_database_setup_fixed.sql, ONCE, as root.
  Run the whole script (Workbench: lightning bolt). It uses DELIMITER $$ for routines.

  Contents
    1. ALTER TABLE  (role column, completed_at, category hierarchy)
    2. Audit_Log table, a scratch table created and DROPped, seed data
    3. INDEXES (including FULLTEXT) and DROP INDEX
    4. FUNCTION   fn_user_reputation
    5. TRIGGERS   bids / ratings / tasks
    6. PROCEDURES (transactions): register, login, post/update/delete task,
                   place/withdraw/accept bid, complete task
    7. ACCESS CONTROL: MySQL users app_student and app_admin with GRANTs
  Demo queries (CTE, recursive CTE, transactions, tests) are in 03_queries_and_tests.sql
*/

USE campus_bid_platform;

/* ============================================================
   1. ALTER TABLE
   ============================================================ */

-- Two roles: admin and student
ALTER TABLE Users
    ADD COLUMN role ENUM('admin','student') NOT NULL DEFAULT 'student' AFTER password_hash;

-- When a task was completed
ALTER TABLE Tasks
    ADD COLUMN completed_at DATETIME NULL;

-- Category hierarchy (used by the recursive CTE)
ALTER TABLE Categories
    ADD COLUMN parent_category_id INT NULL,
    ADD CONSTRAINT fk_categories_parent
        FOREIGN KEY (parent_category_id) REFERENCES Categories(category_id)
        ON UPDATE CASCADE ON DELETE SET NULL;

/* ============================================================
   2. AUDIT TABLE, DROP DEMO, SEED DATA
   ============================================================ */

CREATE TABLE IF NOT EXISTS Audit_Log (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(40) NOT NULL,
    record_id INT NOT NULL,
    action VARCHAR(40) NOT NULL,
    old_value VARCHAR(100),
    new_value VARCHAR(100),
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_table_record (table_name, record_id)
) ENGINE=InnoDB;

-- DROP demo: create a scratch table and remove it
CREATE TABLE tmp_scratch (id INT PRIMARY KEY, note VARCHAR(50));
DROP TABLE tmp_scratch;

-- Sub-categories (parent -> child) for the recursive CTE
INSERT INTO Categories (category_id, category_name, description, parent_category_id) VALUES
(6, 'Poster Design',    'Posters and flyers',            1),
(7, 'Web Development',  'Websites and web apps',         3),
(8, 'React and Next.js','Modern frontend work',          7),
(9, 'Exam Revision',    'Last-minute exam help',         4);

-- Passwords: every demo account uses the password  campus123
-- (stored as scrypt$salt$hash, never in plain text)
UPDATE Users SET password_hash = 'scrypt$7a617f3a9bb84d8933d7ad7862d6cf62$1759b91da4b1318b09a4b9d64e06f061b8f5513e6edb6b959f451d2b557e8303a448afbdb076a5f0b8391bf279fa74464b4f747d812d2352ad96aadc00bcb73e' WHERE user_id = 1;
UPDATE Users SET password_hash = 'scrypt$0735ebba6f92b34f3f72c2b1e8781a2e$87b00ae4f445238be148ed642f0dc5a399536b15e624affa254181b25658f179cc48c801c5991dbaeb7edea24c17c8a1f57f28a042b5b1d5b00bc5f1af7c9fbe' WHERE user_id = 2;
UPDATE Users SET password_hash = 'scrypt$43df28ce1a3688467adc3fb244fb9553$3450bc9818fd234a5f41c6f344db77c1075fbed6a77015780f39d281dd2c1274987f039a755593ab5c06417540540b268b025aeadeb15b94670333469846251d' WHERE user_id = 3;
UPDATE Users SET password_hash = 'scrypt$d84dcb18d46e161d650e30bfe41023fe$c71177e1ccf4cc536a6b0918bda2571eeac9f1891dce6387533484366af6abd34dd2f400212c3b0f581a14122c7dd0260fdf3c8c9425bc87ce48608a7aa086eb' WHERE user_id = 4;
UPDATE Users SET password_hash = 'scrypt$c4a02ece09f2e25a7c3d8d56b3e6732d$0700ef4de851ee452009856eabca62c9f359a6793a893d08a45d69b5b348258f06a60104a20468ee12b93bce39b4755b0826ca19acb4a4ab7bd5459c3d81a416' WHERE user_id = 5;

-- One administrator account
INSERT INTO Users (user_id, full_name, email, password_hash, role, department, phone)
VALUES (6, 'Campus Admin', 'admin@campus.edu',
 'scrypt$7e58ddf498dff0d280cfd96f0bcec8eb$568e25cd02e61922ac4e4ee467321c044aadaf0a064cf9929f380a5346c17e0e273a9c3be643ded2a9f4b8592dc0d71c42bbb51ed4dee2fbaab8a0ad3524e758',
 'admin', 'Administration', '9000000006');

/* ============================================================
   3. INDEXES
   ============================================================ */

-- (Bids.task_id, Tasks.status etc. are already indexed in the base schema.)
CREATE INDEX idx_tasks_deadline        ON Tasks (deadline);
CREATE INDEX idx_tasks_status_deadline ON Tasks (status, deadline);   -- board query: filter by status, sort by deadline
CREATE FULLTEXT INDEX ft_tasks_title_desc ON Tasks (title, description);  -- keyword search

-- DROP INDEX demo
CREATE INDEX idx_bids_amount ON Bids (bid_amount);
DROP INDEX idx_bids_amount ON Bids;

/* ============================================================
   4. FUNCTION
   ============================================================ */

DELIMITER $$

DROP FUNCTION IF EXISTS fn_user_reputation$$
CREATE FUNCTION fn_user_reputation(p_user_id INT)
RETURNS DECIMAL(3,2)
READS SQL DATA
BEGIN
    DECLARE v_avg DECIMAL(3,2);
    SELECT COALESCE(ROUND(AVG(rating_value), 2), 0.00)
      INTO v_avg
      FROM Ratings
     WHERE rated_id = p_user_id;
    RETURN v_avg;
END$$

/* ============================================================
   5. TRIGGERS
   ============================================================ */

-- A poster cannot bid on their own task; bids only on open tasks; one active bid per user per task
DROP TRIGGER IF EXISTS trg_bids_before_insert$$
CREATE TRIGGER trg_bids_before_insert
BEFORE INSERT ON Bids
FOR EACH ROW
BEGIN
    DECLARE v_poster INT;
    DECLARE v_status VARCHAR(20);

    SELECT poster_id, status INTO v_poster, v_status
      FROM Tasks WHERE task_id = NEW.task_id;

    IF v_poster = NEW.bidder_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You cannot bid on your own task';
    END IF;
    IF v_status <> 'open' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'This task is no longer open for bids';
    END IF;
    IF EXISTS (SELECT 1 FROM Bids
                WHERE task_id = NEW.task_id AND bidder_id = NEW.bidder_id
                  AND status <> 'withdrawn') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You already have an active bid on this task';
    END IF;
END$$

-- Nobody can rate themselves
DROP TRIGGER IF EXISTS trg_ratings_before_insert$$
CREATE TRIGGER trg_ratings_before_insert
BEFORE INSERT ON Ratings
FOR EACH ROW
BEGIN
    IF NEW.rater_id = NEW.rated_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You cannot rate yourself';
    END IF;
END$$

-- Keep Users.reputation_score in step with Ratings
DROP TRIGGER IF EXISTS trg_ratings_after_insert$$
CREATE TRIGGER trg_ratings_after_insert
AFTER INSERT ON Ratings
FOR EACH ROW
BEGIN
    UPDATE Users SET reputation_score = fn_user_reputation(NEW.rated_id)
     WHERE user_id = NEW.rated_id;
END$$

DROP TRIGGER IF EXISTS trg_ratings_after_delete$$
CREATE TRIGGER trg_ratings_after_delete
AFTER DELETE ON Ratings
FOR EACH ROW
BEGIN
    UPDATE Users SET reputation_score = fn_user_reputation(OLD.rated_id)
     WHERE user_id = OLD.rated_id;
END$$

-- Audit every task status change
DROP TRIGGER IF EXISTS trg_tasks_after_update$$
CREATE TRIGGER trg_tasks_after_update
AFTER UPDATE ON Tasks
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO Audit_Log (table_name, record_id, action, old_value, new_value)
        VALUES ('Tasks', NEW.task_id, 'status_change', OLD.status, NEW.status);
    END IF;
END$$

/* ============================================================
   6. STORED PROCEDURES (each write is one transaction)
   The app calls only these, so business rules live in the database.
   ============================================================ */

-- Register a student (role is always 'student'; admins are created by the DBA)
DROP PROCEDURE IF EXISTS sp_register_user$$
CREATE PROCEDURE sp_register_user(
    IN p_name VARCHAR(100), IN p_email VARCHAR(150), IN p_hash VARCHAR(255),
    IN p_department VARCHAR(80), IN p_phone VARCHAR(20))
BEGIN
    INSERT INTO Users (full_name, email, password_hash, role, department, phone)
    VALUES (p_name, p_email, p_hash, 'student', p_department, p_phone);
    SELECT LAST_INSERT_ID() AS user_id;
END$$

-- Login lookup (the only way the student account can see a password hash)
DROP PROCEDURE IF EXISTS sp_get_login$$
CREATE PROCEDURE sp_get_login(IN p_email VARCHAR(150))
BEGIN
    SELECT user_id, full_name, role, password_hash
      FROM Users WHERE email = p_email;
END$$

DROP PROCEDURE IF EXISTS sp_post_task$$
CREATE PROCEDURE sp_post_task(
    IN p_poster INT, IN p_category INT, IN p_title VARCHAR(150),
    IN p_description TEXT, IN p_budget DECIMAL(10,2), IN p_deadline DATETIME)
BEGIN
    IF p_budget <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Budget must be greater than zero';
    END IF;
    IF p_deadline <= NOW() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deadline must be in the future';
    END IF;
    INSERT INTO Tasks (poster_id, category_id, title, description, budget, deadline)
    VALUES (p_poster, p_category, p_title, p_description, p_budget, p_deadline);
    SELECT LAST_INSERT_ID() AS task_id;
END$$

DROP PROCEDURE IF EXISTS sp_update_task$$
CREATE PROCEDURE sp_update_task(
    IN p_task INT, IN p_actor INT, IN p_title VARCHAR(150),
    IN p_description TEXT, IN p_budget DECIMAL(10,2), IN p_deadline DATETIME)
BEGIN
    DECLARE v_poster INT;
    DECLARE v_status VARCHAR(20);
    DECLARE v_role VARCHAR(10);

    SELECT poster_id, status INTO v_poster, v_status FROM Tasks WHERE task_id = p_task;
    SELECT role INTO v_role FROM Users WHERE user_id = p_actor;

    IF v_poster IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Task not found';
    END IF;
    IF v_role <> 'admin' AND v_poster <> p_actor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only the poster can edit this task';
    END IF;
    IF v_status <> 'open' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only open tasks can be edited';
    END IF;
    IF p_budget <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Budget must be greater than zero';
    END IF;

    UPDATE Tasks
       SET title = p_title, description = p_description,
           budget = p_budget, deadline = p_deadline
     WHERE task_id = p_task;
END$$

DROP PROCEDURE IF EXISTS sp_delete_task$$
CREATE PROCEDURE sp_delete_task(IN p_task INT, IN p_actor INT)
BEGIN
    DECLARE v_poster INT;
    DECLARE v_status VARCHAR(20);
    DECLARE v_role VARCHAR(10);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT poster_id, status INTO v_poster, v_status FROM Tasks WHERE task_id = p_task FOR UPDATE;
    SELECT role INTO v_role FROM Users WHERE user_id = p_actor;

    IF v_poster IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Task not found';
    END IF;
    IF v_role <> 'admin' AND v_poster <> p_actor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only the poster or an admin can delete this task';
    END IF;
    IF v_status IN ('in_progress', 'completed') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tasks that are in progress or completed cannot be deleted';
    END IF;

    DELETE FROM Bids  WHERE task_id = p_task;
    DELETE FROM Tasks WHERE task_id = p_task;
    COMMIT;
END$$

DROP PROCEDURE IF EXISTS sp_place_bid$$
CREATE PROCEDURE sp_place_bid(
    IN p_task INT, IN p_bidder INT, IN p_amount DECIMAL(10,2), IN p_message TEXT)
BEGIN
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bid amount must be greater than zero';
    END IF;
    -- trg_bids_before_insert enforces: not own task, task open, one active bid
    INSERT INTO Bids (task_id, bidder_id, bid_amount, proposal_message)
    VALUES (p_task, p_bidder, p_amount, p_message);
    SELECT LAST_INSERT_ID() AS bid_id;
END$$

DROP PROCEDURE IF EXISTS sp_withdraw_bid$$
CREATE PROCEDURE sp_withdraw_bid(IN p_bid INT, IN p_actor INT)
BEGIN
    DECLARE v_bidder INT;
    DECLARE v_status VARCHAR(20);

    SELECT bidder_id, status INTO v_bidder, v_status FROM Bids WHERE bid_id = p_bid;
    IF v_bidder IS NULL OR v_bidder <> p_actor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You can only withdraw your own bid';
    END IF;
    IF v_status <> 'pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only pending bids can be withdrawn';
    END IF;
    UPDATE Bids SET status = 'withdrawn' WHERE bid_id = p_bid;
END$$

-- Accept a bid: accept it, reject the rest, task -> in_progress, hold the money in escrow
DROP PROCEDURE IF EXISTS sp_accept_bid$$
CREATE PROCEDURE sp_accept_bid(IN p_bid INT, IN p_actor INT)
BEGIN
    DECLARE v_task INT;
    DECLARE v_bidder INT;
    DECLARE v_amount DECIMAL(10,2);
    DECLARE v_bid_status VARCHAR(20);
    DECLARE v_poster INT;
    DECLARE v_task_status VARCHAR(20);
    DECLARE v_role VARCHAR(10);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT task_id, bidder_id, bid_amount, status
      INTO v_task, v_bidder, v_amount, v_bid_status
      FROM Bids WHERE bid_id = p_bid FOR UPDATE;
    IF v_task IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bid not found';
    END IF;

    SELECT poster_id, status INTO v_poster, v_task_status
      FROM Tasks WHERE task_id = v_task FOR UPDATE;
    SELECT role INTO v_role FROM Users WHERE user_id = p_actor;

    IF v_role <> 'admin' AND v_poster <> p_actor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only the task poster can accept a bid';
    END IF;
    IF v_task_status <> 'open' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Task is not open for acceptance';
    END IF;
    IF v_bid_status <> 'pending' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a pending bid can be accepted';
    END IF;

    UPDATE Bids  SET status = 'accepted' WHERE bid_id = p_bid;
    UPDATE Bids  SET status = 'rejected' WHERE task_id = v_task AND bid_id <> p_bid AND status = 'pending';
    UPDATE Tasks SET status = 'in_progress' WHERE task_id = v_task;
    INSERT INTO Escrow_Transactions (task_id, bid_id, payer_id, payee_id, amount, status)
    VALUES (v_task, p_bid, v_poster, v_bidder, v_amount, 'held');

    COMMIT;
    SELECT LAST_INSERT_ID() AS escrow_id;
END$$

-- Complete a task: release escrow, record the rating (trigger refreshes reputation)
DROP PROCEDURE IF EXISTS sp_complete_task$$
CREATE PROCEDURE sp_complete_task(
    IN p_task INT, IN p_actor INT, IN p_rating TINYINT, IN p_review TEXT)
BEGIN
    DECLARE v_escrow INT;
    DECLARE v_payer INT;
    DECLARE v_payee INT;
    DECLARE v_role VARCHAR(10);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT escrow_id, payer_id, payee_id INTO v_escrow, v_payer, v_payee
      FROM Escrow_Transactions
     WHERE task_id = p_task AND status = 'held' FOR UPDATE;
    SELECT role INTO v_role FROM Users WHERE user_id = p_actor;

    IF v_escrow IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No held escrow for this task';
    END IF;
    IF v_role <> 'admin' AND v_payer <> p_actor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only the task poster can complete it';
    END IF;

    UPDATE Tasks SET status = 'completed', completed_at = NOW() WHERE task_id = p_task;
    UPDATE Escrow_Transactions SET status = 'released', released_at = NOW() WHERE escrow_id = v_escrow;
    INSERT INTO Ratings (task_id, rater_id, rated_id, rating_value, review_text)
    VALUES (p_task, v_payer, v_payee, p_rating, p_review);

    COMMIT;
END$$

DELIMITER ;

/* ============================================================
   7. DATABASE-LEVEL ACCESS CONTROL
   Change the passwords below and put the same ones in .env.local
   ============================================================ */

CREATE USER IF NOT EXISTS 'app_student'@'localhost' IDENTIFIED BY 'Student@123';
CREATE USER IF NOT EXISTS 'app_admin'@'localhost'   IDENTIFIED BY 'Admin@123';

-- STUDENT: read-only on data tables, no access to password hashes,
-- every write goes through a stored procedure.
GRANT SELECT ON campus_bid_platform.Tasks               TO 'app_student'@'localhost';
GRANT SELECT ON campus_bid_platform.Bids                TO 'app_student'@'localhost';
GRANT SELECT ON campus_bid_platform.Categories          TO 'app_student'@'localhost';
GRANT SELECT ON campus_bid_platform.Escrow_Transactions TO 'app_student'@'localhost';
GRANT SELECT ON campus_bid_platform.Ratings             TO 'app_student'@'localhost';
GRANT SELECT (user_id, full_name, email, role, department, phone, reputation_score, created_at)
    ON campus_bid_platform.Users TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_register_user TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_get_login     TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_post_task     TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_update_task   TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_delete_task   TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_place_bid     TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_withdraw_bid  TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_accept_bid    TO 'app_student'@'localhost';
GRANT EXECUTE ON PROCEDURE campus_bid_platform.sp_complete_task TO 'app_student'@'localhost';
GRANT EXECUTE ON FUNCTION  campus_bid_platform.fn_user_reputation TO 'app_student'@'localhost';

-- ADMIN: read everything, run all procedures, manage categories, change user roles.
GRANT SELECT, EXECUTE ON campus_bid_platform.* TO 'app_admin'@'localhost';
GRANT INSERT, UPDATE, DELETE ON campus_bid_platform.Categories TO 'app_admin'@'localhost';
GRANT UPDATE (role) ON campus_bid_platform.Users TO 'app_admin'@'localhost';

FLUSH PRIVILEGES;

SHOW GRANTS FOR 'app_student'@'localhost';
SHOW GRANTS FOR 'app_admin'@'localhost';
