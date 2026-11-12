/*
  Extra open tasks with varied wording, so semantic (vector) search can be compared
  with keyword (FULLTEXT) search. Run after 02_advanced.sql, then press
  "Re-index all tasks" on the Admin page.
  Try searching:  "branding for our club"   "help me pass my exam"   "someone to film our fest"
*/
USE campus_bid_platform;

INSERT INTO Tasks (poster_id, category_id, title, description, budget, deadline) VALUES
(2, 1, 'Logo for the robotics club',
 'We need a clean, modern emblem and colour palette that represents our robotics society on t-shirts and banners.', 800.00, '2026-12-28 18:00:00'),
(3, 6, 'Flyer for the hackathon',
 'Eye-catching A4 flyer announcing the 24-hour coding hackathon with sponsor logos and a QR code.', 400.00, '2026-12-18 18:00:00'),
(5, 4, 'Last-minute help before the OS exam',
 'I am struggling with process scheduling and deadlocks. Looking for a patient senior to walk me through past papers.', 350.00, '2026-12-09 17:00:00'),
(1, 9, 'Revise calculus before finals',
 'Two sessions on integration techniques and series, with practice problems.', 450.00, '2026-12-14 17:00:00'),
(4, 5, 'Photographer for the cultural fest',
 'Capture performances, crowd moments and stage shots over two evenings; edited photos delivered within a week.', 1500.00, '2027-01-05 20:00:00'),
(2, 5, 'Short highlight video of sports day',
 'Film and edit a 2-minute recap reel with music for the college social media page.', 1200.00, '2026-12-22 18:00:00'),
(6, 7, 'Landing page for the placement cell',
 'Responsive one-page website announcing campus recruitment drives, built with React.', 2500.00, '2027-01-10 18:00:00'),
(3, 3, 'Python script to clean attendance data',
 'Merge several messy CSV sheets of attendance into one tidy report and flag students below 75 percent.', 600.00, '2026-12-16 18:00:00'),
(5, 2, 'Proofread my project report',
 'Fix grammar, wording and formatting in a 30-page engineering report before submission.', 250.00, '2026-12-11 17:00:00'),
(1, 8, 'Next.js dashboard for a student startup',
 'Build a small admin dashboard with charts and a login page using Next.js and a REST API.', 3000.00, '2027-01-15 18:00:00');

SELECT COUNT(*) AS total_tasks FROM Tasks;
