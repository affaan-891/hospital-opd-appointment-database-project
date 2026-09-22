# DBMS Viva Voce Defense Guide & Technical Oral Exam Prep

This document prepares students for undergraduate and postgraduate university DBMS project defenses, oral vivas, and technical interviews. Each question represents a challenging probe typically posed by senior evaluators, paired with model answers, technical justifications, and code references.

---

### Question 1: How does your database prevent race conditions during high-concurrency daily token generation?
- **Examiner's Angle**: Tests concurrency control, isolation levels, and understanding of duplicate key hazards under concurrent transactional loads.
- **Model Answer**:
  In a high-throughput Outpatient Department, multiple reception desks or mobile portals may attempt to book appointments for the same physician simultaneously. If two sessions run `SELECT MAX(token_number) + 1` concurrently without locking, both read the identical maximum and attempt to insert duplicate token numbers.
  
  Our system resolves this using two layers:
  1. **Pessimistic Concurrency Control**: In `sp_book_opd_appointment`, we execute `SELECT base_consultation_fee FROM doctors WHERE doctor_id = p_doctor_id FOR UPDATE;`. In InnoDB, this places an exclusive record lock ($X$-lock) on the doctor row, serializing all booking transactions targeting that physician for the duration of the ACID transaction.
  2. **Relational Invariant Protection**: As a fail-safe against anomalies, the `opd_queue_tokens` table enforces a compound `UNIQUE` constraint on `(doctor_id, queue_date, token_number)`. Even if locking were misconfigured, the storage engine rejects collision at the B+ tree index level with an `ER_DUP_ENTRY (1062)` error, triggering the transaction's `ROLLBACK` handler.

```sql
-- Snippet from sp_book_opd_appointment
SELECT base_consultation_fee, max_daily_patients
INTO v_base_fee, v_max_daily_patients
FROM `doctors`
WHERE doctor_id = p_doctor_id AND is_active = TRUE
FOR UPDATE;

SELECT COALESCE(MAX(token_number), 0) + 1
INTO v_token_num
FROM `opd_queue_tokens`
WHERE doctor_id = p_doctor_id AND queue_date = p_appointment_date;
```

---

### Question 2: Explain the mathematical algorithm used in your trigger to detect room schedule conflicts.
- **Examiner's Angle**: Evaluates discrete interval overlap logic and boundary condition handling in database triggers.
- **Model Answer**:
  Checking whether two continuous time intervals $[A_{start}, A_{end})$ and $[B_{start}, B_{end})$ overlap is frequently implemented incorrectly by testing whether a point falls between boundaries. That approach requires 4 nested comparison cases and fails on boundary containment.
  
  The formal interval overlap theorem states that two intervals overlap if and only if:
  $$\text{Overlap} \iff (\text{Start}_A < \text{End}_B) \land (\text{End}_A > \text{Start}_B)$$
  
  In `trg_prevent_doctor_roster_room_clash_insert`, we evaluate:
  ```sql
  (NEW.shift_start < s.shift_end AND NEW.shift_end > s.shift_start)
  ```
  Because the schedule enforces `shift_start < shift_end` via a table-level `CHECK` constraint, this single boolean expression guarantees detection across all four collision topologies: complete enclosure, identical boundaries, partial overlap on the left, and partial overlap on the right. If any active shift in the same room on the same day satisfies this, MySQL signals `SQLSTATE '45000'`.

---

### Question 3: Why did you choose Pessimistic Locking (`FOR UPDATE`) over Optimistic Concurrency Control (OCC) for appointment booking?
- **Examiner's Angle**: Tests architectural decision-making between locking vs versioning in transactional systems.
- **Model Answer**:
  - **Optimistic Concurrency Control (OCC)** (e.g., using a `version_number` or timestamp column) works best in low-contention environments where rollbacks are rare. In an OPD booking rush (such as opening morning slots for a renowned cardiologist), dozens of patients compete for identical 15-minute slots simultaneously. Under OCC, 90% of concurrent requests would fail validation at commit time, forcing client retries and creating high thread thrashing.
  - **Pessimistic Locking (`SELECT ... FOR UPDATE`)** takes an exclusive lock immediately. It holds requests in a deterministic lock queue (monitored by `innodb_lock_wait_timeout`). The first transaction completes and commits within milliseconds; the second transaction immediately detects that the slot has been taken and cleanly redirects the user without wasting I/O or repeating business calculations.

---

### Question 4: How does your schema satisfy Third Normal Form (3NF)? Show where a transitive dependency could have occurred and how you eliminated it.
- **Examiner's Angle**: Tests core relational theory, functional dependencies, and normalization proofs.
- **Model Answer**:
  A relation is in **3NF** if and only if it is in 2NF and every non-prime attribute is non-transitively dependent on every candidate key (i.e., no $X \to Y \to Z$ where $X$ is a candidate key and $Z$ is a non-prime attribute).

  - **Potential Transitive Dependency**: In an unnormalized schema, an `appointments` table might store:
    `appointment_id (PK) -> mrn_number -> patient_dob -> patient_age` or `doctor_id -> dept_id -> dept_name`.
    Here, `patient_dob` depends on `mrn_number`, which depends on `appointment_id`. If `dept_name` were stored in `appointments` or `doctors`, changing a department's name would require updating thousands of appointment rows (Update Anomaly).
  - **Resolution**:
    1. `dept_name` is isolated strictly in `clinical_departments`. `doctors` references only `dept_id`.
    2. Patient demographic attributes (`dob`, `gender`, `phone`) reside strictly in `patients`.
    3. Patient `age` is completely omitted from persistent tables to prevent transitive and temporal anomalies. It is computed dynamically through the deterministic stored function `fn_calculate_patient_age()`.

---

### Question 5: What are the performance and compliance benefits of storing audit logs in JSON format rather than discrete columns?
- **Examiner's Angle**: Explores hybrid relational-document modeling in MySQL 8.0, JSON functions, and schema evolution.
- **Model Answer**:
  The `scheduling_audit_logs` table stores `old_values` and `new_values` as native MySQL `JSON` columns.
  1. **Polymorphic Schema Flexibility**: The audit ledger tracks events across multiple distinct entities (`appointments`, `doctor_schedules`, `opd_queue_tokens`). Creating a dedicated audit table for every business table introduces schema maintenance overhead. JSON allows logging heterogeneous attributes in a single immutable table.
  2. **Point-in-Time State Snapshot**: When an appointment is cancelled, the JSON payload freezes the exact physician fee, slot time, and discount rules active at that instant, even if the doctor's base consultation fee changes the following month.
  3. **Indexing Capability**: In MySQL 8.0, individual keys inside JSON columns can be queried directly using the `->>` operator (`JSON_UNQUOTE(JSON_EXTRACT())`) and indexed using functional secondary indexes (e.g., `CREATE INDEX idx_audit_status ON scheduling_audit_logs ((CAST(new_values->>'$.booking_status' AS CHAR(20)))));`).

---

### Question 6: Explain how composite index B+ Tree traversal works for `(doctor_id, appointment_date, slot_time)` on `appointments`.
- **Examiner's Angle**: Tests physical database engine mechanics, index prefix rules, and query optimization.
- **Model Answer**:
  The composite unique index `uq_doctor_date_slot` on `(doctor_id, appointment_date, slot_time)` builds a balanced B+ Tree where nodes are ordered lexicographically: first by `doctor_id`, then by `appointment_date`, and finally by `slot_time`.
  
  - **Leftmost Prefix Rule**:
    - Queries filtering on `doctor_id` alone, or `(doctor_id, appointment_date)`, or all three columns will perform an efficient logarithmic $O(\log N)$ index range lookup.
    - A query filtering solely on `appointment_date` or `slot_time` without specifying `doctor_id` cannot navigate the root and intermediate branches of this B+ Tree directly and would require an index skip scan or full table scan.
  - **Covering Index Optimization**: In Query 5 (`EXPLAIN ANALYZE`), lookups matching this prefix satisfy the `WHERE` clause at the storage engine level without inspecting non-matching rows, reducing disk buffer page fetches from memory.

---

### Question 7: Why did you use `NOT EXISTS` instead of `LEFT JOIN ... WHERE ... IS NULL` for Query 2 (finding idle rooms)?
- **Examiner's Angle**: Tests SQL optimization, execution plan differences, and null handling.
- **Model Answer**:
  In Query 2:
  ```sql
  SELECT cr.room_id, cr.room_number
  FROM consultation_rooms cr
  WHERE cr.is_operational = TRUE
    AND NOT EXISTS (
        SELECT 1 FROM doctor_schedules ds 
        WHERE ds.room_id = cr.room_id AND ds.is_active = TRUE
    );
  ```
  - **Execution Plan**: The MySQL 8.0 query optimizer transforms `NOT EXISTS` on a correlated subquery into an **Anti-Join**. Under an anti-join, the engine scans the outer table (`consultation_rooms`) and probes the inner index on `doctor_schedules(room_id)`. The moment a single matching row is located, scanning for that `room_id` stops immediately (**short-circuit evaluation**).
  - **Comparison with Outer Join**: A `LEFT JOIN ... WHERE ds.room_id IS NULL` constructs the intermediate joined result set in memory for all matches before applying the `WHERE` filter. `NOT EXISTS` expresses intent clearly, operates with zero outer-null ambiguities, and avoids unnecessary row materialization.

---

### Question 8: Compare `DENSE_RANK()`, `RANK()`, and `ROW_NUMBER()` in the context of Query 4 (Doctor Caseload Ranking).
- **Examiner's Angle**: Probes window function mechanics and analytical SQL skills.
- **Model Answer**:
  In Query 4, we rank doctors within each clinical department based on the number of completed consultations:
  ```sql
  DENSE_RANK() OVER (PARTITION BY cd.dept_id ORDER BY COUNT(a.appointment_id) DESC)
  ```
  - `ROW_NUMBER()` assigns a strictly consecutive integer ($1, 2, 3, 4\dots$) regardless of ties, arbitrarily breaking ties based on internal storage ordering. This is unfair in clinical performance appraisals.
  - `RANK()` assigns identical ranks to tied rows but leaves gaps in the sequence ($1, 2, 2, 4\dots$).
  - `DENSE_RANK()` assigns identical ranks to ties while ensuring no gaps in the numbering sequence ($1, 2, 2, 3\dots$). This accurately reflects positional tiers (e.g., tier 1 physicians, tier 2 physicians) within a medical department without skipping levels.

---

### Question 9: What transaction isolation level does your database use, and does MySQL prevent Phantom Reads during appointment scheduling?
- **Examiner's Angle**: Deep dive into ANSI SQL isolation levels, MVCC, and Next-Key Locking in InnoDB.
- **Model Answer**:
  - The default isolation level for MySQL InnoDB is **REPEATABLE READ**.
  - Under plain ANSI SQL, `REPEATABLE READ` prevents *Dirty Reads* and *Non-Repeatable Reads*, but permits *Phantom Reads* (where a concurrent transaction inserts a new row that matches a range query).
  - **InnoDB's Solution**: InnoDB solves the phantom read problem under `REPEATABLE READ` through two mechanisms:
    1. **Multi-Version Concurrency Control (MVCC)**: For consistent (non-locking) reads (`SELECT`), a transaction views a snapshot of data established at the time of its first read.
    2. **Next-Key Locking**: For locking reads (`SELECT ... FOR UPDATE`), InnoDB uses Next-Key Locks—a combination of an index-record lock and a **gap lock** on the gap preceding the index record. When `sp_book_opd_appointment` locks the doctor row and checks slots, gap locks prevent concurrent transactions from inserting new rows into that specific index interval, guaranteeing serializable behavior without the overhead of the `SERIALIZABLE` isolation level.

---

### Question 10: Justify your foreign key referential integrity choices: Why `ON DELETE RESTRICT` for departments/doctors, but `ON DELETE CASCADE` for queue tokens and notes?
- **Examiner's Angle**: Evaluates understanding of referential actions, accidental data destruction prevention, and medical-legal data retention regulations.
- **Model Answer**:
  - **`ON DELETE RESTRICT` (Parent Tables: `clinical_departments`, `doctors`, `patients`)**:
    In healthcare administration, medical practitioners and patient records are subject to strict legal and regulatory compliance. If an administrator accidentally deletes a doctor or department, cascading that deletion would instantly wipe out hundreds of historical medical consultations, billing records, and audit logs. `ON DELETE RESTRICT` blocks deletion if dependent child records exist, enforcing administrative protection.
  - **`ON DELETE CASCADE` (Dependent Sub-entities: `opd_queue_tokens`, `consultation_notes`, `prescribed_investigations`)**:
    These tables represent transient or dependent weak entity concepts that possess no standalone meaning outside the context of an appointment. A queue token or clinical diagnosis note cannot exist without its parent appointment. When a draft or erroneous test appointment record is legally expunged, cascading ensures no orphaned diagnostic or queue rows remain to fragment the database.
