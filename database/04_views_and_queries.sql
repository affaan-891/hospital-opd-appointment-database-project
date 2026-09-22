-- ============================================================================
-- Project: Hospital OPD Multi-Specialty Appointment & Room Scheduling System
-- Target Engine: MySQL 8.0+ (InnoDB)
-- File: 04_views_and_queries.sql (Analytical Views & Viva Queries)
-- Author: Principal Database Architect & University DBMS Evaluator
-- Repository: https://github.com/affaan-891/hospital-opd-appointment-database-project
-- ============================================================================

USE `hospital_opd_db`;

-- ============================================================================
-- VIEW 1: vw_daily_doctor_opd_summary
-- Purpose: Real-time clinical OPD operations dashboard summarizing doctor caseload,
--          queue throughput, and financial performance for the current business date.
-- Metrics: Total booked, waiting tokens, completed/serviced consultations, gross revenue.
-- ============================================================================
DROP VIEW IF EXISTS `vw_daily_doctor_opd_summary`;

CREATE VIEW `vw_daily_doctor_opd_summary` AS
SELECT 
    d.doctor_id,
    CONCAT(d.first_name, ' ', d.last_name) AS doctor_name,
    d.designation,
    cd.dept_name AS department,
    d.max_daily_patients AS daily_quota,
    COUNT(a.appointment_id) AS total_booked_appointments,
    SUM(CASE WHEN t.queue_status = 'Waiting' THEN 1 ELSE 0 END) AS tokens_waiting,
    SUM(CASE WHEN t.queue_status = 'In_Consultation' THEN 1 ELSE 0 END) AS tokens_in_consultation,
    SUM(CASE WHEN t.queue_status = 'Serviced' THEN 1 ELSE 0 END) AS tokens_serviced,
    SUM(CASE WHEN t.queue_status = 'Skipped' THEN 1 ELSE 0 END) AS tokens_skipped,
    COALESCE(SUM(b.net_payable), 0.00) AS total_revenue_collected
FROM `doctors` d
INNER JOIN `clinical_departments` cd 
    ON d.dept_id = cd.dept_id
LEFT JOIN `appointments` a 
    ON d.doctor_id = a.doctor_id 
   AND a.appointment_date = CURDATE()
   AND a.booking_status != 'Cancelled'
LEFT JOIN `opd_queue_tokens` t 
    ON a.appointment_id = t.appointment_id
LEFT JOIN `billing_invoices` b 
    ON a.appointment_id = b.appointment_id 
   AND b.payment_status = 'Paid'
WHERE d.is_active = TRUE
GROUP BY 
    d.doctor_id, 
    d.first_name, 
    d.last_name, 
    d.designation, 
    cd.dept_name, 
    d.max_daily_patients;

-- ============================================================================
-- VIEW 2: vw_room_utilization_matrix
-- Purpose: Evaluates physical asset utilization by computing total scheduled
--          hours per room against a standard weekly clinical OPD capacity (60 hrs:
--          Mon-Sat, 10 hours daily from 08:00 to 18:00).
-- ============================================================================
DROP VIEW IF EXISTS `vw_room_utilization_matrix`;

CREATE VIEW `vw_room_utilization_matrix` AS
SELECT 
    r.room_id,
    r.room_number,
    r.room_type,
    cd.dept_name AS department,
    r.is_operational,
    COUNT(DISTINCT s.schedule_id) AS total_weekly_shifts,
    COALESCE(
        ROUND(
            SUM(
                TIMESTAMPDIFF(MINUTE, s.shift_start, s.shift_end) / 60.0
            ), 
            2
        ), 
        0.00
    ) AS allocated_hours_per_week,
    60.00 AS hospital_standard_weekly_hours,
    ROUND(
        GREATEST(
            0, 
            100.00 - (
                COALESCE(
                    SUM(TIMESTAMPDIFF(MINUTE, s.shift_start, s.shift_end) / 60.0), 
                    0.00
                ) / 60.00 * 100.00
            )
        ), 
        2
    ) AS vacant_capacity_percentage
FROM `consultation_rooms` r
INNER JOIN `clinical_departments` cd 
    ON r.dept_id = cd.dept_id
LEFT JOIN `doctor_schedules` s 
    ON r.room_id = s.room_id 
   AND s.is_active = TRUE
GROUP BY 
    r.room_id, 
    r.room_number, 
    r.room_type, 
    cd.dept_name, 
    r.is_operational;

-- ============================================================================
-- VIVA-READY COMPLEX QUERIES FOR EVALUATION
-- ============================================================================

-- ----------------------------------------------------------------------------
-- QUERY 1: Doctors Generating Revenue Above Their Department Average
-- Concepts Tested: INNER JOIN, LEFT JOIN, Correlated/Subquery aggregation,
--                  GROUP BY, HAVING, Window comparison.
-- ----------------------------------------------------------------------------
SELECT 
    d.doctor_id,
    CONCAT(d.first_name, ' ', d.last_name) AS doctor_name,
    cd.dept_name,
    COUNT(a.appointment_id) AS total_consultations,
    SUM(b.net_payable) AS total_doctor_revenue,
    dept_avg.avg_department_revenue
FROM `doctors` d
INNER JOIN `clinical_departments` cd 
    ON d.dept_id = cd.dept_id
INNER JOIN `appointments` a 
    ON d.doctor_id = a.doctor_id
INNER JOIN `billing_invoices` b 
    ON a.appointment_id = b.appointment_id 
   AND b.payment_status = 'Paid'
INNER JOIN (
    -- Subquery: Compute average physician revenue per clinical department
    SELECT 
        d2.dept_id,
        ROUND(AVG(sub.doc_rev), 2) AS avg_department_revenue
    FROM `doctors` d2
    INNER JOIN (
        SELECT 
            a2.doctor_id,
            SUM(b2.net_payable) AS doc_rev
        FROM `appointments` a2
        INNER JOIN `billing_invoices` b2 
            ON a2.appointment_id = b2.appointment_id 
           AND b2.payment_status = 'Paid'
        GROUP BY a2.doctor_id
    ) sub ON d2.doctor_id = sub.doctor_id
    GROUP BY d2.dept_id
) dept_avg ON d.dept_id = dept_avg.dept_id
GROUP BY 
    d.doctor_id, 
    d.first_name, 
    d.last_name, 
    cd.dept_name, 
    dept_avg.avg_department_revenue
HAVING SUM(b.net_payable) > dept_avg.avg_department_revenue
ORDER BY total_doctor_revenue DESC;

-- ----------------------------------------------------------------------------
-- QUERY 2: Operational Consultation Rooms With Zero Allocated Doctor Shifts
-- Concepts Tested: Anti-Join using NOT EXISTS, Left Semi-Join optimization,
--                  Resource underutilization audit.
-- ----------------------------------------------------------------------------
SELECT 
    cr.room_id,
    cr.room_number,
    cr.room_type,
    cd.dept_name,
    cr.is_operational,
    'Unassigned Asset' AS utilization_status
FROM `consultation_rooms` cr
INNER JOIN `clinical_departments` cd 
    ON cr.dept_id = cd.dept_id
WHERE cr.is_operational = TRUE
  AND NOT EXISTS (
      -- Correlated check: verify no active duty shifts exist for this room
      SELECT 1
      FROM `doctor_schedules` ds
      WHERE ds.room_id = cr.room_id
        AND ds.is_active = TRUE
  )
ORDER BY cd.dept_name, cr.room_number;

-- ----------------------------------------------------------------------------
-- QUERY 3: Multi-Specialty Frequent Patients (Visited >= 3 Distinct Departments)
-- Concepts Tested: Correlated Subquery, HAVING COUNT(DISTINCT), Clinical triage,
--                  Patient trajectory tracking.
-- ----------------------------------------------------------------------------
SELECT 
    p.patient_id,
    p.mrn_number,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    p.phone,
    p.gender,
    TIMESTAMPDIFF(YEAR, p.dob, CURDATE()) AS age_years,
    COUNT(DISTINCT cd.dept_id) AS distinct_specialties_visited,
    COUNT(a.appointment_id) AS total_visits,
    GROUP_CONCAT(DISTINCT cd.dept_code ORDER BY cd.dept_code SEPARATOR ', ') AS departments_consulted
FROM `patients` p
INNER JOIN `appointments` a 
    ON p.mrn_number = a.mrn_number
INNER JOIN `doctors` d 
    ON a.doctor_id = d.doctor_id
INNER JOIN `clinical_departments` cd 
    ON d.dept_id = cd.dept_id
WHERE a.booking_status IN ('Confirmed', 'CheckedIn', 'Completed')
  AND a.appointment_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY 
    p.patient_id, 
    p.mrn_number, 
    p.first_name, 
    p.last_name, 
    p.phone, 
    p.gender, 
    p.dob
HAVING COUNT(DISTINCT cd.dept_id) >= 3
ORDER BY distinct_specialties_visited DESC, total_visits DESC;

-- ----------------------------------------------------------------------------
-- QUERY 4: Physician Caseload Ranking Within Department Using Window Functions
-- Concepts Tested: DENSE_RANK() OVER (PARTITION BY ... ORDER BY ...),
--                  Windowing vs traditional self-joins, Analytical ranking.
-- ----------------------------------------------------------------------------
SELECT 
    cd.dept_name,
    CONCAT(d.first_name, ' ', d.last_name) AS doctor_name,
    d.designation,
    COUNT(a.appointment_id) AS total_patients_managed,
    COALESCE(SUM(b.net_payable), 0.00) AS total_revenue_generated,
    DENSE_RANK() OVER (
        PARTITION BY cd.dept_id 
        ORDER BY COUNT(a.appointment_id) DESC, SUM(b.net_payable) DESC
    ) AS department_caseload_rank
FROM `doctors` d
INNER JOIN `clinical_departments` cd 
    ON d.dept_id = cd.dept_id
LEFT JOIN `appointments` a 
    ON d.doctor_id = a.doctor_id 
   AND a.booking_status != 'Cancelled'
LEFT JOIN `billing_invoices` b 
    ON a.appointment_id = b.appointment_id 
   AND b.payment_status = 'Paid'
GROUP BY 
    cd.dept_id, 
    cd.dept_name, 
    d.doctor_id, 
    d.first_name, 
    d.last_name, 
    d.designation
ORDER BY cd.dept_name, department_caseload_rank;

-- ----------------------------------------------------------------------------
-- QUERY 5: Performance Execution Profiling using EXPLAIN ANALYZE
-- Concepts Tested: Index Lookup vs Table Scan, Execution plan cost,
--                  Composite key filtering on (doctor_id, appointment_date, slot_time).
-- ----------------------------------------------------------------------------
-- In MySQL 8.0+, EXPLAIN ANALYZE executes the statement and prints timing/iterator tree
EXPLAIN ANALYZE
SELECT 
    a.appointment_id,
    a.mrn_number,
    CONCAT(p.first_name, ' ', p.last_name) AS patient_name,
    d.doctor_id,
    CONCAT(d.first_name, ' ', d.last_name) AS doctor_name,
    a.appointment_date,
    a.slot_time,
    a.booking_status,
    t.token_number,
    b.net_payable
FROM `appointments` a
INNER JOIN `patients` p 
    ON a.mrn_number = p.mrn_number
INNER JOIN `doctors` d 
    ON a.doctor_id = d.doctor_id
LEFT JOIN `opd_queue_tokens` t 
    ON a.appointment_id = t.appointment_id
LEFT JOIN `billing_invoices` b 
    ON a.appointment_id = b.appointment_id
WHERE a.doctor_id = 1
  AND a.appointment_date = CURDATE()
  AND a.slot_time = '09:00:00';

-- ============================================================================
-- End of 04_views_and_queries.sql
-- ============================================================================
