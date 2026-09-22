# Hospital OPD Multi-Specialty Appointment & Room Scheduling System

[![MySQL 8.0+](https://img.shields.io/badge/MySQL-8.0%2B-blue.svg?logo=mysql&logoColor=white)](https://dev.mysql.com/)
[![Storage Engine](https://img.shields.io/badge/Storage_Engine-InnoDB-orange.svg)](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html)
[![Normalization](https://img.shields.io/badge/Schema-3NF_Strict-green.svg)](#relational-normalization--architecture)
[![ACID Compliant](https://img.shields.io/badge/Transactions-ACID_Compliant-red.svg)](#stored-procedures--acid-transactions)
[![Academic Project](https://img.shields.io/badge/Target-University_DBMS_Coursework-purple.svg)](#viva-defense--evaluation-rubric)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade, open-source relational database project engineered for university computer science and software engineering students. The project models a high-throughput **Hospital Outpatient Department (OPD)**, featuring multi-specialty consultation booking, automated clash-free room scheduling, pessimistic concurrency control, dynamic consultation pricing, live patient token queues, EHR clinical documentation, and tamper-evident audit logging.

---

## Table of Contents
- [System Architecture](#system-architecture)
- [Repository Structure](#repository-structure)
- [Database Schema (11 Tables, 3NF Compliant)](#database-schema-11-tables-3nf-compliant)
- [Business Integrity & Triggers](#business-integrity--triggers)
- [Stored Procedures & ACID Transactions](#stored-procedures--acid-transactions)
- [Analytical Views & Complex Viva Queries](#analytical-views--complex-viva-queries)
- [Installation & Quickstart Guide](#installation--quickstart-guide)
- [Viva Voce Defense & Theory](#viva-voce-defense--theory)
- [Git Setup & Submission Workflow](#git-setup--submission-workflow)
- [License](#license)

---

## System Architecture

```text
                               +-----------------------------+
                               |    CLINICAL_DEPARTMENTS     |
                               +--------------+--------------+
                                              | 1:N
                       +----------------------+----------------------+
                       |                                             |
                       v 1:N                                         v 1:N
        +-----------------------------+               +-----------------------------+
        |     CONSULTATION_ROOMS      |               |           DOCTORS           |
        +--------------+--------------+               +--------------+--------------+
                       |                                             |
                       +----------------------+----------------------+
                                              |
                                              v 1:N
                               +-----------------------------+
                               |      DOCTOR_SCHEDULES       |
                               +--------------+--------------+
                                              | 1:N
    +-----------------------------+           |
    |          PATIENTS           |           |
    +--------------+--------------+           |
                   |                          |
                   +-------------------+------+
                                       |
                                       v 1:N
                        +-----------------------------+
                        |        APPOINTMENTS         |
                        +--------------+--------------+
                                       |
        +------------------------------+------------------------------+
        | 1:1                          | 1:1                          | 1:0..1
        v                              v                              v
+---------------+              +---------------+              +--------------------+
|OPD_QUEUE_TOKEN|              |BILLING_INVOICE|              | CONSULTATION_NOTES |
+---------------+              +---------------+              +---------+----------+
                                                                        | 1:N
                                                                        v
                                                              +--------------------+
                                                              |PRESCRIBED_INVESTIG |
                                                              +--------------------+
```

---

## Repository Structure

```text
hospital-opd-appointment-database-project/
├── database/
│   ├── 01_schema.sql             # Database creation, 11 3NF tables, foreign keys, CHECK constraints
│   ├── 02_triggers.sql           # Temporal room clash prevention, doctor capacity, cancellation audit
│   ├── 03_procedures.sql         # ACID booking transaction, pessimistic locking, dynamic fees, rescheduling
│   ├── 04_views_and_queries.sql  # 2 Analytical views + 5 viva-level complex SQL queries
│   └── 05_seed_data.sql          # Realistic relational dataset (4 depts, 8 rooms, 8 doctors, 15 patients, 24 appts)
├── docs/
│   ├── ERD.md                    # Data dictionary & Mermaid.js Crow's Foot ER diagram
│   └── VIVA_QUESTIONS.md         # 10 comprehensive viva defense questions with technical answers
└── README.md                     # Project overview, architecture, and import guide
```

---

## Database Schema (11 Tables, 3NF Compliant)

| # | Table Name | Purpose | Key Constraints |
| :--- | :--- | :--- | :--- |
| 1 | `clinical_departments` | Specialty divisions (Cardiology, Pediatrics, etc.) | `dept_id` (PK), `dept_code` (UK) |
| 2 | `consultation_rooms` | Physical OPD suites and procedure suites | `room_id` (PK), `room_number` (UK), `dept_id` (FK) |
| 3 | `doctors` | Physician credentials, designation, and fees | `doctor_id` (PK), `medical_license_number` (UK), `dept_id` (FK) |
| 4 | `doctor_schedules` | Weekly duty roster mapping doctors to rooms | `schedule_id` (PK), `(doctor_id, day, start)` (UK), `(room_id, day, start)` (UK) |
| 5 | `patients` | Patient master demographics and unique MRN | `patient_id` (PK), `mrn_number` (UK), `phone` (UK), `national_id` (UK) |
| 6 | `appointments` | Booked outpatient consultation sessions | `appointment_id` (PK), `(doctor_id, date, slot)` (UK), FKs to patients/doctors/schedules |
| 7 | `opd_queue_tokens` | Live daily outpatient queue sequencing | `token_id` (PK), `appointment_id` (UK), `(doctor_id, date, token)` (UK) |
| 8 | `consultation_notes` | Clinical EHR records (diagnosis, symptoms) | `note_id` (PK), `appointment_id` (UK) |
| 9 | `prescribed_investigations` | Diagnostic lab and radiology test orders | `investigation_id` (PK), `note_id` (FK) |
| 10 | `billing_invoices` | Financial transactions and net fee receipts | `invoice_id` (PK), `invoice_number` (UK), `appointment_id` (UK) |
| 11 | `scheduling_audit_logs` | Immutable JSON audit ledger of system events | `log_id` (PK), indexed on `(entity_name, record_id)` |

---

## Business Integrity & Triggers

### 1. Doctor Roster Room Clash Detection (`trg_prevent_doctor_roster_room_clash_insert`)
Enforces that no two doctors can be scheduled in the same consultation room during overlapping hours on the same day:
$$\text{Conflict} \iff (\text{NEW.shift\_start} < \text{EXISTING.shift\_end}) \land (\text{NEW.shift\_end} > \text{EXISTING.shift\_start})$$
If an overlap is detected, MySQL raises `SIGNAL SQLSTATE '45000'` with the message:
`"Roster Conflict: Consultation room is already booked by another doctor for this day and time window."`

### 2. Daily Doctor Patient Quota (`trg_enforce_daily_opd_patient_limit`)
Checks total active appointments for a physician on a given date against `doctors.max_daily_patients`. Prevents doctor burnout and ensures patient safety by throwing `SIGNAL SQLSTATE '45000'`.

### 3. State Transition Cancellation Auditing (`trg_log_appointment_cancellation`)
When an appointment transitions from `Confirmed` to `Cancelled`, this trigger automatically snapshots the old and new states as native JSON objects in `scheduling_audit_logs`.

---

## Stored Procedures & ACID Transactions

### `sp_book_opd_appointment`
An atomic stored procedure that handles end-to-end appointment creation:
1. **Pessimistic Concurrency Lock**: Executes `SELECT ... FOR UPDATE` on the doctor record to serialize bookings and prevent slot oversubscription.
2. **Duty Roster Verification**: Validates that the doctor has an active shift covering the requested slot.
3. **Dynamic Fee Calculation**:
   - `Standard`: 100% of base fee.
   - `FollowUp`: 50% discount if the patient attended a consultation within the past 7 days.
   - `SeniorCitizen`: 30% discount if the patient is 60+ years old (via `fn_calculate_patient_age()`).
   - `Emergency`: 150% of base fee (50% triage surcharge).
4. **Token Generation**: Atomically assigns the next sequential queue token `COALESCE(MAX(token_number), 0) + 1`.
5. **Multi-Table Atomic Commit**: Inserts `appointments`, `opd_queue_tokens`, `billing_invoices`, and `scheduling_audit_logs` in a single ACID transaction (`START TRANSACTION` / `COMMIT` / `ROLLBACK`).

```sql
-- Execution Example:
CALL sp_book_opd_appointment(
    1,                  -- Patient ID (Ramesh Patel, Senior Citizen)
    1,                  -- Doctor ID (Dr. Rajesh Sharma, Cardiology)
    CURDATE(),          -- Appointment Date
    '11:00:00',         -- Slot Time
    'SeniorCitizen',    -- Category
    'Card',             -- Payment Mode
    @out_appt_id,       -- OUT Appointment ID
    @out_token_num,     -- OUT Token Number
    @out_fee            -- OUT Final Calculated Fee
);

SELECT @out_appt_id AS Appointment_ID, @out_token_num AS Token_Number, @out_fee AS Net_Payable;
```

---

## Analytical Views & Complex Viva Queries

### Views
- **`vw_daily_doctor_opd_summary`**: Summarizes daily caseload, waiting tokens, completed visits, and revenue collected per physician for `CURDATE()`.
- **`vw_room_utilization_matrix`**: Computes allocated weekly hours per consultation room and displays vacant room capacity percentage.

### Complex Viva Queries Included
1. **Doctors Exceeding Department Average Revenue**: Uses `INNER JOIN`, `LEFT JOIN`, `GROUP BY`, and `HAVING` with a subquery.
2. **Idle Operational Rooms**: Utilizes an anti-join via `NOT EXISTS` to find operational rooms with zero doctor assignments.
3. **Multi-Specialty Frequent Patients**: Correlated subquery identifying patients who consulted in $\ge 3$ distinct specialties within the past 30 days.
4. **Physician Caseload Ranking**: Uses the window function `DENSE_RANK() OVER (PARTITION BY dept_id ORDER BY COUNT(...) DESC)`.
5. **Query Optimization Profiling**: Uses `EXPLAIN ANALYZE` on composite index lookups `(doctor_id, appointment_date, slot_time)`.

---

## Installation & Quickstart Guide

### Prerequisites
- MySQL Community Server 8.0 or higher (or MariaDB 10.5+ / XAMPP / WampServer).
- Command-line MySQL client or GUI (MySQL Workbench, phpMyAdmin, DBeaver).

### Step-by-Step Database Setup

#### Option A: Command Line (PowerShell / Bash)
```bash
# Clone the repository
git clone https://github.com/affaan-891/hospital-opd-appointment-database-project.git
cd hospital-opd-appointment-database-project/database

# Execute scripts in sequence
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_triggers.sql
mysql -u root -p < 03_procedures.sql
mysql -u root -p < 04_views_and_queries.sql
mysql -u root -p < 05_seed_data.sql
```

#### Option B: MySQL Workbench / phpMyAdmin
1. Open and execute `database/01_schema.sql`.
2. Open and execute `database/02_triggers.sql`.
3. Open and execute `database/03_procedures.sql`.
4. Open and execute `database/04_views_and_queries.sql`.
5. Open and execute `database/05_seed_data.sql`.

---

## Viva Voce Defense & Theory

For in-depth explanations designed for semester oral exams and technical defense, refer to:
- 📖 [Comprehensive ERD & Data Dictionary](docs/ERD.md)
- 🎓 [Top 10 Viva Voce Questions & Model Answers](docs/VIVA_QUESTIONS.md)

---

## Git Setup & Submission Workflow

After cloning or generating project files, synchronize with your remote repository:

```powershell
# 1. Initialize Git repository
git init

# 2. Add remote repository
git remote add origin https://github.com/affaan-891/hospital-opd-appointment-database-project.git

# 3. Pull any remote files (e.g., LICENSE)
git pull origin main --allow-unrelated-histories

# 4. Stage and commit all files
git add .
git commit -m "feat: complete hospital OPD scheduling and appointment DBMS project with 3NF schema, triggers, procedures, views and ERD"

# 5. Push to GitHub
git branch -M main
git push -u origin main
```

---

## License
This project is open-source under the [MIT License](LICENSE).
Feel free to use and adapt this repository for university coursework, lab submissions, and technical portfolio presentations.
