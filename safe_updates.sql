-- ============================================================
-- Task 1: Safe UPDATE Operations
-- Target: _copy tables only. Original tables are NOT modified.
-- ============================================================

-- ------------------------------------------------------------
-- SETUP: Create working copies before any modification
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS students_copy AS SELECT * FROM students;
CREATE TABLE IF NOT EXISTS submissions_copy AS SELECT * FROM submissions;
CREATE TABLE IF NOT EXISTS test_results_copy AS SELECT * FROM test_results;
CREATE TABLE IF NOT EXISTS enrollments_copy AS SELECT * FROM enrollments;


-- ============================================================
-- UPDATE 1: Correct invalid email values
-- Problem: Some students have emails that do not contain '@',
--          likely due to import corruption.
-- ============================================================

-- BEFORE: Identify rows with invalid emails
SELECT student_id, name, email
FROM students_copy
WHERE email NOT LIKE '%@%.%';

-- UPDATE: Replace malformed emails with a placeholder pattern
--         so they can be flagged for manual correction
UPDATE students_copy
SET email = CONCAT('fix_required_', student_id, '@placeholder.invalid')
WHERE email NOT LIKE '%@%.%';

-- AFTER: Confirm the fix was applied only to invalid rows
SELECT student_id, name, email
FROM students_copy
WHERE email LIKE 'fix_required_%';

-- WHY THE WHERE CLAUSE IS SAFE:
-- The condition `email NOT LIKE '%@%.%'` matches only rows where
-- the email is structurally invalid (missing @ or domain). Valid
-- emails are completely untouched. Using CONCAT with student_id
-- makes every placeholder unique and traceable.


-- ============================================================
-- UPDATE 2: Correct missing batch values
-- Problem: Some students were imported with NULL or empty batch.
-- ============================================================

-- BEFORE: Find students with no batch assigned
SELECT student_id, name, batch
FROM students_copy
WHERE batch IS NULL OR TRIM(batch) = '';

-- UPDATE: Assign a default batch label for triage
UPDATE students_copy
SET batch = 'BATCH_UNKNOWN'
WHERE batch IS NULL OR TRIM(batch) = '';

-- AFTER: Verify correction
SELECT student_id, name, batch
FROM students_copy
WHERE batch = 'BATCH_UNKNOWN';

-- WHY THE WHERE CLAUSE IS SAFE:
-- Only rows with NULL or empty batch strings are matched.
-- Students with any valid non-empty batch value are excluded
-- from the update entirely.


-- ============================================================
-- UPDATE 3: Fix incorrect score values
-- Problem: Some test_results rows have scores outside [0, 100].
--          Negative or >100 scores are data-entry errors.
-- ============================================================

-- BEFORE: Identify out-of-range scores
SELECT result_id, submission_id, score
FROM test_results_copy
WHERE score < 0 OR score > 100;

-- UPDATE: Clamp values to boundary (0 or 100 as appropriate)
UPDATE test_results_copy
SET score = CASE
    WHEN score < 0 THEN 0
    WHEN score > 100 THEN 100
    ELSE score
END
WHERE score < 0 OR score > 100;

-- AFTER: Confirm no out-of-range scores remain
SELECT result_id, submission_id, score
FROM test_results_copy
WHERE score < 0 OR score > 100;
-- Expected: 0 rows

-- WHY THE WHERE CLAUSE IS SAFE:
-- The condition targets only provably invalid values (< 0 or > 100).
-- Valid scores in [0, 100] are completely bypassed by the WHERE clause.
-- The CASE inside the SET is also bounded, so no valid row is altered.


-- ============================================================
-- UPDATE 4: Update submission status based on test-result evidence
-- Problem: Submissions marked 'pending' but all their test results
--          show passed = TRUE should be promoted to 'accepted'.
-- ============================================================

-- BEFORE: Find affected submissions
SELECT s.submission_id, s.status, s.student_id
FROM submissions_copy s
WHERE s.status = 'pending'
  AND NOT EXISTS (
      SELECT 1
      FROM test_results_copy tr
      WHERE tr.submission_id = s.submission_id
        AND tr.passed = FALSE
  )
  AND EXISTS (
      SELECT 1
      FROM test_results_copy tr
      WHERE tr.submission_id = s.submission_id
  );

-- UPDATE: Promote qualifying submissions to 'accepted'
UPDATE submissions_copy
SET status = 'accepted'
WHERE status = 'pending'
  AND NOT EXISTS (
      SELECT 1
      FROM test_results_copy tr
      WHERE tr.submission_id = submissions_copy.submission_id
        AND tr.passed = FALSE
  )
  AND EXISTS (
      SELECT 1
      FROM test_results_copy tr
      WHERE tr.submission_id = submissions_copy.submission_id
  );

-- AFTER: Verify status change
SELECT submission_id, status
FROM submissions_copy
WHERE status = 'accepted';

-- WHY THE WHERE CLAUSE IS SAFE:
-- Three guards are layered:
--   (1) status = 'pending'     → only pending rows are touched
--   (2) NOT EXISTS failed test → only all-pass submissions qualify
--   (3) EXISTS at least one    → submissions with zero test rows are excluded
-- This triple guard prevents false promotions.
