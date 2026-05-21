-- ============================================================
-- Task 2: Safe DELETE Operations
-- Target: _copy / staging tables only. Originals untouched.
-- ============================================================

-- ------------------------------------------------------------
-- SETUP: Ensure working copies exist
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS students_copy AS SELECT * FROM students;
CREATE TABLE IF NOT EXISTS submissions_copy AS SELECT * FROM submissions;
CREATE TABLE IF NOT EXISTS test_results_copy AS SELECT * FROM test_results;


-- ============================================================
-- DELETE 1: Remove duplicate staging records from students_copy
-- Problem: The import process sometimes inserted the same student
--          row more than once (same email, different auto-generated
--          student_id). Keep only the row with the lowest student_id
--          (the first import) and delete the duplicates.
-- ============================================================

-- STEP 1: Identify duplicates
-- Show all rows that share an email with at least one other row
SELECT student_id, name, email, batch
FROM students_copy
WHERE email IN (
    SELECT email
    FROM students_copy
    GROUP BY email
    HAVING COUNT(*) > 1
)
ORDER BY email, student_id;

-- STEP 2: Preview which rows WILL be deleted
-- (rows that are NOT the minimum student_id for their email)
SELECT student_id, name, email
FROM students_copy s1
WHERE EXISTS (
    SELECT 1
    FROM students_copy s2
    WHERE s2.email = s1.email
      AND s2.student_id < s1.student_id
);

-- DELETE: Remove only the higher-ID duplicates
DELETE FROM students_copy
WHERE EXISTS (
    SELECT 1
    FROM (SELECT MIN(student_id) AS keep_id, email
          FROM students_copy
          GROUP BY email) AS keepers
    WHERE keepers.email = students_copy.email
      AND keepers.keep_id <> students_copy.student_id
);

-- AFTER: Verify no duplicates remain
SELECT email, COUNT(*) AS cnt
FROM students_copy
GROUP BY email
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- WHY THIS DELETE DOES NOT REMOVE UNINTENDED ROWS:
-- The subquery explicitly computes the minimum student_id per email
-- (the "keeper"). Only rows whose student_id differs from that
-- minimum are deleted. The keeper row itself is always preserved.
-- Emails that appear only once are never matched by the EXISTS clause.


-- ============================================================
-- DELETE 2: Delete orphan test_result rows (no matching submission)
-- Problem: After import, some test_results rows reference a
--          submission_id that does not exist in submissions.
--          These are broken/orphan records with no parent.
-- ============================================================

-- STEP 1: Identify orphan test_results
SELECT tr.result_id, tr.submission_id, tr.score, tr.passed
FROM test_results_copy tr
WHERE NOT EXISTS (
    SELECT 1
    FROM submissions_copy s
    WHERE s.submission_id = tr.submission_id
);

-- STEP 2: Count orphans before deletion (sanity check)
SELECT COUNT(*) AS orphan_count
FROM test_results_copy tr
WHERE NOT EXISTS (
    SELECT 1
    FROM submissions_copy s
    WHERE s.submission_id = tr.submission_id
);

-- DELETE: Remove only orphan test_result rows
DELETE FROM test_results_copy
WHERE NOT EXISTS (
    SELECT 1
    FROM submissions_copy s
    WHERE s.submission_id = test_results_copy.submission_id
);

-- AFTER: Confirm zero orphans remain
SELECT COUNT(*) AS remaining_orphans
FROM test_results_copy tr
WHERE NOT EXISTS (
    SELECT 1
    FROM submissions_copy s
    WHERE s.submission_id = tr.submission_id
);
-- Expected: 0

-- WHY THIS DELETE DOES NOT REMOVE UNINTENDED ROWS:
-- The NOT EXISTS check is a precise referential-integrity filter.
-- Any test_result that has a valid matching submission is protected
-- because its submission_id WILL be found in submissions_copy.
-- Only truly parentless rows (dangling foreign keys) are removed.

-- NOTE ON CORRECTION VS DELETION:
-- If a test_result row has a valid score and passed value but just
-- references a submission_id that was accidentally omitted from the
-- import, the correct action is to INSERT the missing submission row
-- rather than delete the test_result. Deletion is only appropriate
-- when the test_result itself is confirmed garbage (e.g., submission_id
-- was never valid in the source system).
