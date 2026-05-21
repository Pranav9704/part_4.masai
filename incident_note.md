# Task 5: Reliability Incident Note

**System:** CodeJudge – IITMD CSE Assignment Database  
**Incident Type:** Accidental Unbounded UPDATE / DELETE (Missing WHERE Clause)  
**Severity:** Critical  
**Date of Scenario:** Hypothetical – used for preventive learning  

---

## What Went Wrong

A developer, intending to mark a single student's submission as `'rejected'` due to a plagiarism flag, executed the following command against the live `submissions` table:

```sql
UPDATE submissions SET status = 'rejected';
```

The `WHERE` clause was omitted — either forgotten or accidentally deleted during editing. Because no filter was applied, **every row** in the `submissions` table had its `status` column overwritten to `'rejected'`.

Similarly, a separate developer attempting to remove one test dummy record ran:

```sql
DELETE FROM test_results;
```

Again without a `WHERE` clause, resulting in **complete erasure** of the `test_results` table.

---

## What Data Could Be Affected

| Table | Rows at risk | Impact |
|-------|-------------|--------|
| `submissions` | All submissions from all students, all batches | Every submission now shows `status = 'rejected'`; no record of `'accepted'` or `'pending'` state survives |
| `test_results` | All test result rows | All scores, pass/fail flags, and grading evidence are permanently gone |
| Dependent reports | Leaderboards, score aggregations, progress dashboards | All derived views and reports now reflect incorrect or empty data |

In a real CodeJudge deployment with hundreds of students, this would mean all grading history is destroyed and student scores cannot be reconstructed without a backup.

---

## How the Issue Could Be Detected

1. **Immediate post-execution row count check:**  
   Running `SELECT COUNT(*) FROM submissions WHERE status <> 'rejected';` immediately after the UPDATE would return `0`, which is an obvious anomaly.

2. **Application-layer alerts:**  
   If the CodeJudge platform monitors grade distributions, a sudden spike of 100% rejection rate would trigger an automated alert or dashboard anomaly.

3. **Audit logs:**  
   If the DBMS has query logging or an audit table enabled (e.g., `pg_audit` in PostgreSQL), the unbounded UPDATE/DELETE would be logged with its full SQL text, timestamp, and executing user — enabling rapid identification.

4. **Replication lag / monitoring:**  
   In a primary-replica setup, monitoring tools (e.g., pgBadger, pt-query-digest) might flag an unusually large write operation affecting millions of rows.

---

## How Rollback, Backups, or Transactions Could Help

### Transactions (Best Protection)
Had the developer wrapped the operation in a transaction:
```sql
BEGIN;
UPDATE submissions SET status = 'rejected' WHERE submission_id = 305;
-- Pause and verify: SELECT * FROM submissions WHERE submission_id = 305;
COMMIT;  -- only after visual confirmation
```
The `BEGIN` creates a safe window. If the error is noticed before `COMMIT`, a simple `ROLLBACK` restores the entire table to its pre-update state instantly with zero data loss.

### ROLLBACK After the Fact
If the session is still open and `COMMIT` has **not** yet been issued, `ROLLBACK` alone is sufficient to undo all changes in that session.

### Database Backups
If `COMMIT` was already issued:
- A full daily backup or point-in-time recovery (PITR) using WAL archiving (PostgreSQL) or binary log replay (MySQL) can restore the database to the state it was in just before the erroneous statement.
- Recovery time depends on backup frequency — hourly backups cap data loss at ~1 hour of work.

### Copy/Staging Tables (Used in This Assignment)
This assignment's safety strategy — always operating on `_copy` tables — directly prevents this scenario. Even an unbounded DELETE on `submissions_copy` leaves the original `submissions` table untouched.

---

## Preventive Measures for the Future

1. **Never run UPDATE or DELETE without a WHERE clause on production tables.**  
   Use a pre-execution checklist or linting tool (e.g., `sqlfluff`) that warns on unbounded DML.

2. **Always run the equivalent SELECT first:**
   ```sql
   -- Before:
   SELECT * FROM submissions WHERE student_id = 42 AND problem_id = 7;
   -- Then, only if the result looks right:
   UPDATE submissions SET status = 'rejected' WHERE student_id = 42 AND problem_id = 7;
   ```

3. **Use transactions with explicit COMMIT for all DML on production.**  
   Set `AUTOCOMMIT = OFF` in development environments to force deliberate commits.

4. **Apply the principle of least privilege.**  
   Developer accounts should not have direct `DELETE` or `UPDATE` access on production tables. Use stored procedures or application-layer APIs instead.

5. **Enable `safe_updates` mode (MySQL) or equivalent:**
   ```sql
   SET SQL_SAFE_UPDATES = 1;  -- MySQL rejects UPDATE/DELETE without WHERE on indexed column
   ```

6. **Maintain automated daily backups with PITR enabled**, so the recovery window is minimised even when a mistake slips through.

7. **Conduct peer code review for all SQL scripts** before execution on any environment beyond local development.

---

*This incident note is a hypothetical scenario constructed for learning purposes as part of the IITMD CSE SQL Assignment.*
