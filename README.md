# Campus Bid (Next.js 15 + MySQL 8)

A campus micro-task marketplace: students post tasks, others bid, the poster accepts one bid,
the money is held in escrow and released on completion, and both sides build a reputation.

## Setup
1. In MySQL Workbench, run these in order (as root):
   1. `database/campus_bid_platform_database_setup_fixed.sql`  (tables + sample data)
   2. `database/02_advanced.sql`  (role column, indexes, function, triggers, procedures, MySQL users + GRANTs)
   3. `database/03_queries_and_tests.sql`  (optional; run block by block for the report screenshots)
   4. `database/04_more_sample_tasks.sql`  (optional; extra tasks to demonstrate semantic search)
2. `cp .env.local.example .env.local` and set the passwords you chose in `02_advanced.sql`
   and a long random `SESSION_SECRET`.
3. Start the vector service (needs Python 3.10+; the first run downloads the ~80 MB MiniLM model):
   ```
   cd vector-service
   python -m venv .venv && source .venv/bin/activate      # Windows PowerShell: .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   uvicorn main:app --port 8000
   ```
4. In a second terminal: `npm install && npm run dev`, open http://localhost:3000
5. Log in as the admin, open **Admin**, and press **Re-index all tasks** once.

## Demo logins (password `campus123`)
| Email | Role |
|---|---|
| admin@campus.edu | admin |
| aarav.sharma@campus.edu, diya.nair@campus.edu, rohan.mehta@campus.edu, ananya.rao@campus.edu, kabir.shah@campus.edu | student |

## Architecture
- **Pages / server actions** (`app/`): all writes call stored procedures through `lib/db.js`.
- **Auth** (`lib/auth.js`): scrypt-hashed passwords, HMAC-signed httpOnly session cookie.
- **Roles**: the session role selects which MySQL account runs the query.
  - `app_student`: SELECT on data tables (no `password_hash`), EXECUTE on procedures only.
  - `app_admin`: SELECT + EXECUTE, plus INSERT/UPDATE/DELETE on Categories and UPDATE on `Users.role`.
- **Business rules in the database**: triggers (no bidding on own task, no self-rating, reputation refresh,
  status audit log), procedures with transactions (`sp_accept_bid`, `sp_complete_task`, ...).

## Vector database (Chroma)
| Question | Answer |
|---|---|
| What is embedded | One document per task: `<category>: <title>. <description>` |
| Model | all-MiniLM-L6-v2 (384 dimensions, runs locally) |
| How vectors are stored | Chroma persistent collection `tasks` (HNSW index, on disk in `vector-service/chroma_data`) with metadata `task_id, category, budget, status, poster_id` |
| Similarity metric | Cosine (score = 1 - cosine distance) |
| Retrieval | Embed the query with the same model and return the top-k nearest tasks, optionally filtered by `status` |
| Create / Update | Posting or editing a task, or changing its status, upserts its vector |
| Read | `/search` (semantic vs MySQL FULLTEXT side by side), "Similar tasks" on each task, "Recommended for you" |
| Delete | Deleting a task removes its vector |

Why a vector database: task titles and descriptions are free text. People describe the same need in different
words ("branding for our club" vs "logo for the robotics society"), which keyword matching misses.
MySQL stays the source of truth for transactional data (bids, escrow, ratings) that needs ACID guarantees.
The app keeps working if the vector service is down; search then falls back to keyword results only.

## API routes
`GET /api/tasks?status=open`, `GET /api/search?q=...`, `GET /api/tasks/:id/similar` (all need a login session).
