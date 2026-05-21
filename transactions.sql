-- ============================================================
-- Task 3: Transaction Scenarios
-- All scenarios operate on _copy tables to preserve originals.
-- ============================================================

-- SETUP
CREATE TABLE IF NOT EXISTS submissions_copy AS SELECT * FROM submissions;
CREATE TABLE IF NOT EXISTS test_results_copy AS SELECT * FROM test_results;
CREATE TABLE IF NOT EXISTS enrollments_copy AS SELECT * FROM enrollments;
CREATE TABLE IF NOT EXISTS regrade_requests_copy AS SELECT * FROM regrade_requests;
CREATE TABLE IF NOT EXISTS students_copy AS SELECT * FROM students;
CREATE TABLE IF NOT EXISTS courses_copy AS SELECT * FROM courses;


-- ============================================================
-- SCENARIO 1: Student submits a solution — INSERT submission
--             and corresponding test_result rows atomically.
--             Uses COMMIT.
-- ============================================================

BEGIN;

    -- Insert the new submission record
    INSERT INTO submissions_copy (submission_id, student_id, problem_id, status, submitted_at)
    VALUES (9001, 42, 7, 'pending', NOW());

    -- Insert two test result rows tied to this submission
    INSERT INTO test_results_copy (result_id, submission_id, score, passed)
    VALUES (8001, 9001, 85, TRUE);

    INSERT INTO test_results_copy (result_id, submission_id, score, passed)
    VALUES (8002, 9001, 90, TRUE);

    -- Verify before committing
    SELECT * FROM submissions_copy WHERE submission_id = 9001;
    SELECT * FROM test_results_copy WHERE submission_id = 9001;

COMMIT;

-- EXPECTED FINAL STATE:
-- submissions_copy has a new row: submission_id=9001, status='pending'
-- test_results_copy has two new rows for submission_id=9001
-- Both inserts succeed together or neither is saved (atomicity).
-- After COMMIT the changes are durable and visible to other sessions.


-- ============================================================
-- SCENARIO 2: A course enrollment is attempted but ROLLED BACK
--             because the course_id does not exist (invalid condition).
--             Uses ROLLBACK.
-- ============================================================

BEGIN;

    -- Attempt to enroll student 42 into a non-existent course 999
    INSERT INTO enrollments_copy (enrollment_id, student_id, course_id, enrolled_at)
    VALUES (5001, 42, 999, NOW());

    -- Validation check: does course 999 exist?
    -- If the following query returns 0 rows, we must rollback.
    SELECT course_id FROM courses_copy WHERE course_id = 999;
    -- (Application layer / script detects 0 rows and issues ROLLBACK)

ROLLBACK;

-- EXPECTED FINAL STATE:
-- The INSERT into enrollments_copy is completely undone.
-- No row with enrollment_id=5001 exists in enrollments_copy.
-- The database is in the same state as before this transaction began.
-- This demonstrates that a failed business-rule check can cleanly
-- abort the entire operation without leaving partial data.


-- ============================================================
-- SCENARIO 3: A score correction is validated and committed.
--             Uses SAVEPOINT for partial rollback safety.
-- ============================================================

BEGIN;

    -- SAVEPOINT before any changes — safe restore point
    SAVEPOINT before_score_fix;

    -- Step A: Check current score for result_id = 101
    SELECT result_id, submission_id, score, passed
    FROM test_results_copy
    WHERE result_id = 101;

    -- Step B: Apply score correction (instructor confirmed new score = 78)
    UPDATE test_results_copy
    SET score = 78,
        passed = TRUE
    WHERE result_id = 101
      AND score <> 78;      -- guard: skip if already correct

    -- SAVEPOINT after score correction
    SAVEPOINT after_score_fix;

    -- Step C: Also update the submission status to 'accepted'
    --         (assuming this was the only failing test)
    UPDATE submissions_copy
    SET status = 'accepted'
    WHERE submission_id = (
        SELECT submission_id FROM test_results_copy WHERE result_id = 101
    )
    AND status = 'pending';

    -- Validation: confirm the submission now has no failing tests
    SELECT COUNT(*) AS still_failing
    FROM test_results_copy
    WHERE submission_id = (
        SELECT submission_id FROM test_results_copy WHERE result_id = 101
    )
    AND passed = FALSE;

    -- If still_failing > 0, roll back only the status change (partial rollback)
    -- and keep the score fix:
    --   ROLLBACK TO SAVEPOINT after_score_fix;
    -- Otherwise, commit everything:

COMMIT;

-- EXPECTED FINAL STATE (happy path — no partial rollback needed):
-- test_results_copy: result_id=101 now has score=78, passed=TRUE
-- submissions_copy: related submission status promoted to 'accepted'
-- Both changes are durable after COMMIT.
--
-- If the partial rollback (ROLLBACK TO SAVEPOINT after_score_fix) had been
-- triggered instead:
--   - Score fix (Step B) is kept
--   - Submission status change (Step C) is undone
--   - Transaction can then be COMMITted with only the score fix applied
