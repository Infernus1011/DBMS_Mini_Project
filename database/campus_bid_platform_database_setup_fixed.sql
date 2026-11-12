/*
  CAMPUS BID PLATFORM - DATABASE INITIALIZATION
  MySQL 8.0+

  Creates the database, six tables, relationships, and the initial sample data
  expected by PES2UG24CS462_PES2UG24CS450_G23.sql.

  IMPORTANT:
  1. Run this file FIRST, once, in MySQL Workbench.
  2. Then run the separate SQL QUERIES file.
  3. This script does NOT drop or erase an existing database.
*/

CREATE DATABASE IF NOT EXISTS campus_bid_platform;
USE campus_bid_platform;

/* ------------------------------------------------------------
   TABLES
   ------------------------------------------------------------ */

CREATE TABLE IF NOT EXISTS Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    department VARCHAR(80) NOT NULL,
    phone VARCHAR(20),
    reputation_score DECIMAL(3,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Categories (
    category_id INT AUTO_INCREMENT PRIMARY KEY,
    category_name VARCHAR(80) NOT NULL UNIQUE,
    description VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Tasks (
    task_id INT AUTO_INCREMENT PRIMARY KEY,
    poster_id INT NOT NULL,
    category_id INT NOT NULL,
    title VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    budget DECIMAL(10,2) NOT NULL,
    deadline DATETIME NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_tasks_budget CHECK (budget >= 0),
    CONSTRAINT chk_tasks_status CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled')),
    CONSTRAINT fk_tasks_poster
        FOREIGN KEY (poster_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_tasks_category
        FOREIGN KEY (category_id) REFERENCES Categories(category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_tasks_status (status),
    INDEX idx_tasks_poster (poster_id),
    INDEX idx_tasks_category (category_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Bids (
    bid_id INT AUTO_INCREMENT PRIMARY KEY,
    task_id INT NOT NULL,
    bidder_id INT NOT NULL,
    bid_amount DECIMAL(10,2) NOT NULL,
    proposal_message TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_bids_amount CHECK (bid_amount >= 0),
    CONSTRAINT chk_bids_status CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')),
    CONSTRAINT fk_bids_task
        FOREIGN KEY (task_id) REFERENCES Tasks(task_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bids_bidder
        FOREIGN KEY (bidder_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_bids_task (task_id),
    INDEX idx_bids_bidder (bidder_id),
    INDEX idx_bids_status (status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Escrow_Transactions (
    escrow_id INT AUTO_INCREMENT PRIMARY KEY,
    task_id INT NOT NULL,
    bid_id INT NOT NULL,
    payer_id INT NOT NULL,
    payee_id INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'held',
    held_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    released_at DATETIME NULL,
    CONSTRAINT chk_escrow_amount CHECK (amount >= 0),
    CONSTRAINT chk_escrow_status CHECK (status IN ('held', 'released', 'refunded')),
    CONSTRAINT fk_escrow_task
        FOREIGN KEY (task_id) REFERENCES Tasks(task_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_escrow_bid
        FOREIGN KEY (bid_id) REFERENCES Bids(bid_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_escrow_payer
        FOREIGN KEY (payer_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_escrow_payee
        FOREIGN KEY (payee_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    UNIQUE KEY uq_escrow_bid (bid_id),
    INDEX idx_escrow_task (task_id),
    INDEX idx_escrow_status (status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Ratings (
    rating_id INT AUTO_INCREMENT PRIMARY KEY,
    task_id INT NOT NULL,
    rater_id INT NOT NULL,
    rated_id INT NOT NULL,
    rating_value TINYINT NOT NULL,
    review_text TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_rating_value CHECK (rating_value BETWEEN 1 AND 5),
    /* The application should ensure rater_id <> rated_id. */
    CONSTRAINT fk_ratings_task
        FOREIGN KEY (task_id) REFERENCES Tasks(task_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_ratings_rater
        FOREIGN KEY (rater_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_ratings_rated
        FOREIGN KEY (rated_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    INDEX idx_ratings_rated (rated_id),
    INDEX idx_ratings_task (task_id)
) ENGINE=InnoDB;

/* ------------------------------------------------------------
   INITIAL SAMPLE DATA
   Expected starting counts:
   5 users, 5 categories, 4 tasks, 5 bids,
   2 escrow transactions, 2 ratings.
   ------------------------------------------------------------ */

INSERT INTO Users
(user_id, full_name, email, password_hash, department, phone, reputation_score)
VALUES
(1, 'Aarav Sharma', 'aarav.sharma@campus.edu', 'demo_hash_1', 'CSE', '9000000001', 4.50),
(2, 'Diya Nair', 'diya.nair@campus.edu', 'demo_hash_2', 'ISE', '9000000002', 4.00),
(3, 'Rohan Mehta', 'rohan.mehta@campus.edu', 'demo_hash_3', 'CSE', '9000000003', 4.75),
(4, 'Ananya Rao', 'ananya.rao@campus.edu', 'demo_hash_4', 'ECE', '9000000004', 0.00),
(5, 'Kabir Shah', 'kabir.shah@campus.edu', 'demo_hash_5', 'CSE', '9000000005', 0.00);

INSERT INTO Categories (category_id, category_name, description)
VALUES
(1, 'Design', 'Graphic design, posters and visual assets'),
(2, 'Writing', 'Proofreading, editing and content writing'),
(3, 'Programming', 'Software development and technical tasks'),
(4, 'Tutoring', 'Academic help and subject tutoring'),
(5, 'Photography', 'Event, portrait and campus photography');

INSERT INTO Tasks
(task_id, poster_id, category_id, title, description, budget, deadline, status)
VALUES
(1, 1, 1, 'Design a tech fest poster',
 'Create a promotional poster for the college technology festival.',
 500.00, '2026-12-15 18:00:00', 'in_progress'),
(2, 2, 3, 'Build a simple portfolio website',
 'Create a responsive personal portfolio website.',
 1200.00, '2026-12-20 18:00:00', 'in_progress'),
(3, 4, 4, 'Explain DBMS normalization',
 'Provide a short tutoring session covering 1NF, 2NF and 3NF.',
 300.00, '2026-12-10 17:00:00', 'open'),
(4, 5, 2, 'Prepare an event report',
 'Write a concise report about a recent campus event.',
 200.00, '2026-12-12 17:00:00', 'open');

INSERT INTO Bids
(bid_id, task_id, bidder_id, bid_amount, proposal_message, status)
VALUES
(1, 1, 3, 450.00, 'I have experience designing posters for student events.', 'accepted'),
(2, 2, 1, 1100.00, 'I can build the website using modern frontend tools.', 'accepted'),
(3, 2, 4, 1000.00, 'I can deliver a responsive portfolio website.', 'pending'),
(4, 3, 2, 280.00, 'I can explain normalization with clear examples.', 'pending'),
(5, 4, 3, 180.00, 'I can prepare and proofread the event report.', 'pending');

INSERT INTO Escrow_Transactions
(escrow_id, task_id, bid_id, payer_id, payee_id, amount, status, held_at, released_at)
VALUES
(1, 1, 1, 1, 3, 450.00, 'held', '2026-09-01 10:00:00', NULL),
(2, 2, 2, 2, 1, 1100.00, 'held', '2026-09-02 11:00:00', NULL);

INSERT INTO Ratings
(rating_id, task_id, rater_id, rated_id, rating_value, review_text)
VALUES
(1, 2, 2, 1, 4, 'Good communication and a clear proposal.'),
(2, 3, 4, 2, 5, 'Explained the topic clearly and patiently.');

/* ------------------------------------------------------------
   VERIFICATION
   Each count should match the expected starting counts above.
   ------------------------------------------------------------ */

SELECT 'Users' AS table_name, COUNT(*) AS row_count FROM Users
UNION ALL
SELECT 'Categories', COUNT(*) FROM Categories
UNION ALL
SELECT 'Tasks', COUNT(*) FROM Tasks
UNION ALL
SELECT 'Bids', COUNT(*) FROM Bids
UNION ALL
SELECT 'Escrow_Transactions', COUNT(*) FROM Escrow_Transactions
UNION ALL
SELECT 'Ratings', COUNT(*) FROM Ratings;

SHOW TABLES;
