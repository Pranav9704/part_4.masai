# Task 4: ACID Properties – Applied to Transaction Scenario 3

## Selected Transaction: Score Correction with SAVEPOINT

```sql
BEGIN;
  SAVEPOINT before_score_fix;
  UPDATE test_results_copy SET score = 78, passed = TRUE WHERE result_id = 101 AND score <> 78;
  SAVEPOINT after_score_fix;
  UPDATE submissions_copy SET status = 'accepted' WHERE submission_id = (...) AND status = 'pending';
COMMIT;
```

---

## Atomicity

**Definition:** Every operation inside the transaction either completes fully or not at all. There is no partial success.

**Applied here:**  
Scenario 3 performs two related updates — correcting the score in `test_results_copy` and promoting the submission status in `submissions_copy`. If the database crashes or a runtime error occurs after the first UPDATE but before `COMMIT`, neither change is saved. The transaction is automatically rolled back to the state before `BEGIN`. This means it is impossible to end up with a corrected score but a still-pending submission status — both changes succeed together or both are discarded.

The use of `SAVEPOINT after_score_fix` adds a finer layer of atomicity control: if the second update is determined to be premature (e.g., other test cases are still failing), only that second change can be rolled back while the first is preserved, and the transaction can then be committed partially. This is a controlled exception to all-or-nothing, deliberately designed into the workflow.

---

## Consistency

**Definition:** A transaction takes the database from one valid state to another valid state, never violating defined rules or integrity constraints.

**Applied here:**  
Before the score update, the database may be in an inconsistent logical state — the instructor has determined the score `101` is wrong, but the database still reflects the old value. After `COMMIT`, the database reaches a new consistent state:

- `score = 78` and `passed = TRUE` are internally consistent (a passing score is correctly flagged as passed).  
- The submission's `status = 'accepted'` is only set after confirming that no other test results for that submission are still failing (`still_failing = 0`).  

The guard condition `AND score <> 78` on the UPDATE ensures the query does not create a false "dirty" change if the value is already correct. Consistency is preserved at every step.

---

## Isolation

**Definition:** Concurrent transactions do not interfere with each other. Intermediate (uncommitted) states of a transaction are invisible to other sessions.

**Applied here:**  
While Scenario 3 is executing — after the first UPDATE but before `COMMIT` — another session querying `test_results_copy` for `result_id = 101` would still see the old score (e.g., the incorrect value), not `78`. This is because the change is not yet committed. Similarly, the submission status change is invisible to the outside world until `COMMIT` is issued.

This is particularly important in a CodeJudge system where multiple users (students, instructors, automated judges) may query scores simultaneously. Isolation ensures a student does not momentarily see a corrected score followed by a reversion — they only ever see a stable, committed state.

The exact isolation behaviour (e.g., whether dirty reads or phantom reads are possible) depends on the isolation level set in the DBMS (e.g., `READ COMMITTED`, `REPEATABLE READ`). PostgreSQL defaults to `READ COMMITTED`, which prevents dirty reads.

---

## Durability

**Definition:** Once a transaction is committed, its changes are permanent — even in the event of a system crash, power failure, or restart.

**Applied here:**  
After `COMMIT` is issued in Scenario 3, both the score correction and the status update are written to the database's persistent storage (WAL – Write-Ahead Log in PostgreSQL, or redo log in MySQL). If the server crashes one millisecond after `COMMIT` returns, the changes are not lost. When the database restarts, it replays the log and restores the committed state.

This guarantees that a grade correction, once confirmed by an instructor and committed, cannot silently disappear. Students and administrators can trust that a committed score change is final.

---

## Summary Table

| Property | Guarantee | How Scenario 3 demonstrates it |
|---|---|---|
| **Atomicity** | All-or-nothing | Both UPDATEs commit together; SAVEPOINT allows controlled partial rollback |
| **Consistency** | Valid state → valid state | Guards (`AND score <> 78`, `still_failing` check) ensure logical correctness |
| **Isolation** | Uncommitted changes are invisible | Other sessions see old score until COMMIT |
| **Durability** | Committed data survives crashes | WAL/redo log ensures persistence after COMMIT |
