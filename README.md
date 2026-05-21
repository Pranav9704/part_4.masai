# IITMD CSE SQL Assignment – Data Modification & Transaction Safety

## Overview

This submission covers safe data modification practices on the CodeJudge assignment database.
All destructive operations (UPDATE, DELETE) are performed on **copies or staging tables**, never directly on the original imported database.

---

## Repository Structure

| File | Description |
|------|-------------|
| `safe_updates.sql` | Task 1 – 4 safe UPDATE operations with before/after SELECTs |
| `safe_deletes.sql` | Task 2 – 2 safe DELETE operations with row-identification SELECTs |
| `transactions.sql` | Task 3 – 3 transaction scenarios (COMMIT, ROLLBACK, SAVEPOINT) |
| `acid_explanation.md` | Task 4 – ACID properties explained using Transaction Scenario 3 |
| `incident_note.md` | Task 5 – Reliability incident note for a missing-WHERE-clause disaster |

---

## Safety Strategy

Before any modification task, a working copy of each relevant table is created:

```sql
CREATE TABLE students_copy AS SELECT * FROM students;
CREATE TABLE submissions_copy AS SELECT * FROM submissions;
CREATE TABLE test_results_copy AS SELECT * FROM test_results;
CREATE TABLE enrollments_copy AS SELECT * FROM enrollments;
```

All UPDATE and DELETE operations in Tasks 1 and 2 target these `_copy` tables.
Transaction scenarios in Task 3 also use copies or are wrapped in ROLLBACK-safe blocks.

---

## Database Assumed Schema (CodeJudge)

| Table | Key Columns |
|-------|-------------|
| `students` | student_id, name, email, batch |
| `submissions` | submission_id, student_id, problem_id, status, submitted_at |
| `test_results` | result_id, submission_id, score, passed |
| `enrollments` | enrollment_id, student_id, course_id, enrolled_at |
| `courses` | course_id, course_name |
| `regrade_requests` | request_id, submission_id, status, resolved_at |

---

## How to Run

1. Import your original database.
2. Run the copy-creation block at the top of each `.sql` file before executing any modification.
3. Verify with the provided `SELECT` queries before and after each operation.
4. Only promote changes to the original tables after full validation.
