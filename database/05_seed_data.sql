-- ============================================================================
-- Project: Hospital OPD Multi-Specialty Appointment & Room Scheduling System
-- Target Engine: MySQL 8.0+ (InnoDB)
-- File: 05_seed_data.sql (Production-Grade Academic Relational Seed Data)
-- Author: Principal Database Architect & University DBMS Evaluator
-- Repository: https://github.com/affaan-891/hospital-opd-appointment-database-project
-- ============================================================================

USE `hospital_opd_db`;

-- Temporarily disable foreign key checks to allow deterministic truncation
SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE `scheduling_audit_logs`;
TRUNCATE TABLE `prescribed_investigations`;
TRUNCATE TABLE `consultation_notes`;
TRUNCATE TABLE `billing_invoices`;
TRUNCATE TABLE `opd_queue_tokens`;
TRUNCATE TABLE `appointments`;
TRUNCATE TABLE `doctor_schedules`;
TRUNCATE TABLE `doctors`;
TRUNCATE TABLE `consultation_rooms`;
TRUNCATE TABLE `patients`;
TRUNCATE TABLE `clinical_departments`;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- 1. CLINICAL DEPARTMENTS (4 Core Specialties)
-- ============================================================================
INSERT INTO `clinical_departments` (`dept_id`, `dept_code`, `dept_name`, `floor_number`, `emergency_supported`) VALUES
(1, 'CARD', 'Cardiology & Cardiovascular Sciences', 1, TRUE),
(2, 'PEDS', 'Pediatrics & Neonatology', 2, TRUE),
(3, 'NEUR', 'Neurology & Neuro-Surgery', 3, TRUE),
(4, 'ORTH', 'Orthopedics & Joint Reconstruction', 1, FALSE);

-- ============================================================================
-- 2. CONSULTATION ROOMS (8 Dedicated Clinical Suites)
-- ============================================================================
INSERT INTO `consultation_rooms` (`room_id`, `room_number`, `dept_id`, `room_type`, `is_operational`) VALUES
(1, 'CR-101', 1, 'Consultation', TRUE),
(2, 'CR-102', 1, 'Specialist_Suite', TRUE),
(3, 'CR-201', 2, 'Consultation', TRUE),
(4, 'CR-202', 2, 'Procedure', TRUE),
(5, 'CR-301', 3, 'Consultation', TRUE),
(6, 'CR-302', 3, 'Specialist_Suite', TRUE),
(7, 'CR-105', 4, 'Consultation', TRUE),
(8, 'CR-106', 4, 'Procedure', TRUE);

-- ============================================================================
-- 3. DOCTORS (8 Medical Specialists with Tiered Ranks & Patient Caps)
-- ============================================================================
INSERT INTO `doctors` (`doctor_id`, `medical_license_number`, `first_name`, `last_name`, `dept_id`, `designation`, `base_consultation_fee`, `max_daily_patients`, `is_active`) VALUES
(1, 'MD-CARD-001', 'Dr. Rajesh', 'Sharma', 1, 'Consultant_Professor', 1500.00, 25, TRUE),
(2, 'MD-CARD-002', 'Dr. Priya', 'Nair', 1, 'Assistant_Professor', 1000.00, 30, TRUE),
(3, 'MD-PEDS-001', 'Dr. Fatima', 'Zahra', 2, 'Consultant_Professor', 1200.00, 20, TRUE),
(4, 'MD-PEDS-002', 'Dr. Amit', 'Verma', 2, 'Senior_Registrar', 800.00, 35, TRUE),
(5, 'MD-NEUR-001', 'Dr. Vikramaditya', 'Rao', 3, 'Consultant_Professor', 1800.00, 20, TRUE),
(6, 'MD-NEUR-002', 'Dr. Ananya', 'Deshmukh', 3, 'Assistant_Professor', 1200.00, 25, TRUE),
(7, 'MD-ORTH-001', 'Dr. Harpreet', 'Singh', 4, 'Consultant_Professor', 1400.00, 25, TRUE),
(8, 'MD-ORTH-002', 'Dr. Sneha', 'Kulkarni', 4, 'Medical_Officer', 600.00, 40, TRUE);

-- ============================================================================
-- 4. DOCTOR SCHEDULES (14 Roster Slots - Rigorously Clash-Free)
-- ============================================================================
INSERT INTO `doctor_schedules` (`schedule_id`, `doctor_id`, `room_id`, `day_of_week`, `shift_start`, `shift_end`, `is_active`) VALUES
-- Cardiology Schedules (Room 1 & Room 2)
(1, 1, 1, 'Mon', '09:00:00', '13:00:00', TRUE),
(2, 2, 1, 'Mon', '14:00:00', '18:00:00', TRUE),
(3, 1, 2, 'Tue', '09:00:00', '13:00:00', TRUE),
(4, 2, 2, 'Wed', '10:00:00', '14:00:00', TRUE),
-- Pediatrics Schedules (Room 3 & Room 4)
(5, 3, 3, 'Mon', '08:30:00', '12:30:00', TRUE),
(6, 4, 3, 'Mon', '13:00:00', '17:00:00', TRUE),
(7, 3, 4, 'Tue', '09:00:00', '13:00:00', TRUE),
(8, 4, 3, 'Thu', '10:00:00', '14:00:00', TRUE),
-- Neurology Schedules (Room 5 & Room 6)
(9, 5, 5, 'Mon', '09:30:00', '13:30:00', TRUE),
(10, 6, 5, 'Mon', '14:00:00', '18:00:00', TRUE),
(11, 5, 6, 'Wed', '09:00:00', '13:00:00', TRUE),
(12, 6, 5, 'Fri', '10:00:00', '14:00:00', TRUE),
-- Orthopedics Schedules (Room 7)
(13, 7, 7, 'Mon', '09:00:00', '13:00:00', TRUE),
(14, 8, 7, 'Tue', '14:00:00', '18:00:00', TRUE);

-- ============================================================================
-- 5. PATIENTS (15 Diverse Profiles: Geriatrics, Adults, Pediatrics)
-- ============================================================================
INSERT INTO `patients` (`patient_id`, `mrn_number`, `first_name`, `last_name`, `gender`, `dob`, `phone`, `national_id`) VALUES
(1,  'MRN-100001', 'Ramesh', 'Patel', 'M', '1955-04-12', '+91-9820011221', 'NID-IND-77889901'), -- Senior Citizen (71y)
(2,  'MRN-100002', 'Sunita', 'Sharma', 'F', '1961-08-25', '+91-9820011222', 'NID-IND-77889902'), -- Senior Citizen (65y)
(3,  'MRN-100003', 'Aarav', 'Gupta', 'M', '2018-03-15', '+91-9820011223', 'NID-IND-77889903'), -- Pediatric (8y)
(4,  'MRN-100004', 'Diya', 'Mehta', 'F', '2021-11-04', '+91-9820011224', 'NID-IND-77889904'), -- Pediatric (4y)
(5,  'MRN-100005', 'Karan', 'Malhotra', 'M', '1988-06-19', '+91-9820011225', 'NID-IND-77889905'), -- Adult (38y)
(6,  'MRN-100006', 'Pooja', 'Iyer', 'F', '1992-09-30', '+91-9820011226', 'NID-IND-77889906'), -- Adult (33y)
(7,  'MRN-100007', 'Mohammad', 'Ali', 'M', '1952-01-10', '+91-9820011227', 'NID-IND-77889907'), -- Senior Citizen (74y)
(8,  'MRN-100008', 'Lakshmi', 'Narayanan', 'F', '1975-12-14', '+91-9820011228', 'NID-IND-77889908'), -- Adult (50y)
(9,  'MRN-100009', 'Gurpreet', 'Kaur', 'F', '1984-05-02', '+91-9820011229', 'NID-IND-77889909'), -- Adult (42y)
(10, 'MRN-100010', 'Tariq', 'Mansoor', 'M', '1963-07-22', '+91-9820011230', 'NID-IND-77889910'), -- Senior Citizen (63y)
(11, 'MRN-100011', 'Ananya', 'Sen', 'F', '2000-02-18', '+91-9820011231', 'NID-IND-77889911'), -- Young Adult (26y)
(12, 'MRN-100012', 'Kabir', 'Khan', 'M', '2016-09-08', '+91-9820011232', 'NID-IND-77889912'), -- Pediatric (9y)
(13, 'MRN-100013', 'Bhavna', 'Joshi', 'F', '1979-10-11', '+91-9820011233', 'NID-IND-77889913'), -- Adult (46y)
(14, 'MRN-100014', 'Suresh', 'Reddy', 'M', '1958-03-05', '+91-9820011234', 'NID-IND-77889914'), -- Senior Citizen (68y)
(15, 'MRN-100015', 'Nisha', 'Bansal', 'F', '1995-12-28', '+91-9820011235', 'NID-IND-77889915'); -- Adult (30y)

-- ============================================================================
-- 6. APPOINTMENTS (24 Multi-Date Clinical Consultations)
-- Spanning today (CURDATE()) and preceding days to fuel analytical views.
-- ============================================================================
INSERT INTO `appointments` (`appointment_id`, `mrn_number`, `doctor_id`, `schedule_id`, `appointment_date`, `slot_time`, `booking_status`, `fee_category`, `consultation_fee`) VALUES
-- Current Day Consultations (CURDATE())
(1,  'MRN-100001', 1, 1, CURDATE(), '09:00:00', 'Completed', 'SeniorCitizen', 1050.00), -- 30% off 1500
(2,  'MRN-100005', 1, 1, CURDATE(), '09:30:00', 'CheckedIn', 'Standard',      1500.00),
(3,  'MRN-100007', 1, 1, CURDATE(), '10:00:00', 'Confirmed', 'SeniorCitizen', 1050.00),
(4,  'MRN-100006', 2, 2, CURDATE(), '14:00:00', 'CheckedIn', 'Standard',      1000.00),
(5,  'MRN-100008', 2, 2, CURDATE(), '14:30:00', 'Confirmed', 'Standard',      1000.00),
(6,  'MRN-100003', 3, 5, CURDATE(), '08:30:00', 'Completed', 'Standard',      1200.00),
(7,  'MRN-100004', 3, 5, CURDATE(), '09:00:00', 'Confirmed', 'Emergency',     1800.00), -- 150% of 1200
(8,  'MRN-100012', 4, 6, CURDATE(), '13:00:00', 'CheckedIn', 'Standard',       800.00),
(9,  'MRN-100002', 5, 9, CURDATE(), '09:30:00', 'Completed', 'SeniorCitizen', 1260.00), -- 30% off 1800
(10, 'MRN-100010', 5, 9, CURDATE(), '10:00:00', 'Confirmed', 'SeniorCitizen', 1260.00),
(11, 'MRN-100011', 6, 10, CURDATE(), '14:00:00', 'Confirmed', 'Standard',     1200.00),
(12, 'MRN-100014', 7, 13, CURDATE(), '09:00:00', 'Completed', 'SeniorCitizen',  980.00), -- 30% off 1400

-- Historical Consultations (Past 1 to 10 days for Follow-Up & Multi-Specialty Analytics)
(13, 'MRN-100001', 1, 1, DATE_SUB(CURDATE(), INTERVAL 5 DAY), '09:00:00', 'Completed', 'SeniorCitizen', 1050.00),
(14, 'MRN-100001', 5, 9, DATE_SUB(CURDATE(), INTERVAL 4 DAY), '09:30:00', 'Completed', 'SeniorCitizen', 1260.00),
(15, 'MRN-100001', 7, 13, DATE_SUB(CURDATE(), INTERVAL 3 DAY), '09:00:00', 'Completed', 'SeniorCitizen',  980.00), -- MRN-100001 visited 3 depts!
(16, 'MRN-100005', 2, 2, DATE_SUB(CURDATE(), INTERVAL 6 DAY), '14:00:00', 'Completed', 'Standard',      1000.00),
(17, 'MRN-100005', 5, 10, DATE_SUB(CURDATE(), INTERVAL 4 DAY), '14:00:00', 'Completed', 'Standard',     1200.00),
(18, 'MRN-100005', 7, 13, DATE_SUB(CURDATE(), INTERVAL 2 DAY), '09:30:00', 'Completed', 'Standard',     1400.00), -- MRN-100005 visited 3 depts!
(19, 'MRN-100002', 1, 3, DATE_SUB(CURDATE(), INTERVAL 7 DAY), '09:00:00', 'Completed', 'SeniorCitizen', 1050.00),
(20, 'MRN-100002', 3, 7, DATE_SUB(CURDATE(), INTERVAL 5 DAY), '09:00:00', 'Completed', 'SeniorCitizen',  840.00),
(21, 'MRN-100002', 7, 14, DATE_SUB(CURDATE(), INTERVAL 2 DAY), '14:00:00', 'Completed', 'SeniorCitizen',  980.00), -- MRN-100002 visited 3 depts!
(22, 'MRN-100008', 1, 1, DATE_SUB(CURDATE(), INTERVAL 8 DAY), '10:30:00', 'Completed', 'Standard',      1500.00),
(23, 'MRN-100009', 2, 4, DATE_SUB(CURDATE(), INTERVAL 3 DAY), '10:00:00', 'Cancelled', 'Standard',      1000.00),
(24, 'MRN-100013', 7, 13, DATE_SUB(CURDATE(), INTERVAL 1 DAY), '10:00:00', 'Completed', 'Standard',     1400.00);

-- ============================================================================
-- 7. OPD QUEUE TOKENS (Tracking daily clinical queue lifecycle)
-- ============================================================================
INSERT INTO `opd_queue_tokens` (`token_id`, `appointment_id`, `doctor_id`, `queue_date`, `token_number`, `queue_status`, `called_at`, `completed_at`) VALUES
-- Current Day Queue
(1,  1,  1, CURDATE(), 1, 'Serviced',        CONCAT(CURDATE(), ' 09:02:00'), CONCAT(CURDATE(), ' 09:25:00')),
(2,  2,  1, CURDATE(), 2, 'In_Consultation', CONCAT(CURDATE(), ' 09:30:00'), NULL),
(3,  3,  1, CURDATE(), 3, 'Waiting',         NULL, NULL),
(4,  4,  2, CURDATE(), 1, 'In_Consultation', CONCAT(CURDATE(), ' 14:02:00'), NULL),
(5,  5,  2, CURDATE(), 2, 'Waiting',         NULL, NULL),
(6,  6,  3, CURDATE(), 1, 'Serviced',        CONCAT(CURDATE(), ' 08:35:00'), CONCAT(CURDATE(), ' 08:58:00')),
(7,  7,  3, CURDATE(), 2, 'Waiting',         NULL, NULL),
(8,  8,  4, CURDATE(), 1, 'In_Consultation', CONCAT(CURDATE(), ' 13:05:00'), NULL),
(9,  9,  5, CURDATE(), 1, 'Serviced',        CONCAT(CURDATE(), ' 09:35:00'), CONCAT(CURDATE(), ' 10:05:00')),
(10, 10, 5, CURDATE(), 2, 'Waiting',         NULL, NULL),
(11, 11, 6, CURDATE(), 1, 'Waiting',         NULL, NULL),
(12, 12, 7, CURDATE(), 1, 'Serviced',        CONCAT(CURDATE(), ' 09:05:00'), CONCAT(CURDATE(), ' 09:30:00')),
-- Historical Queue Tokens
(13, 13, 1, DATE_SUB(CURDATE(), INTERVAL 5 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 5 DAY), DATE_SUB(NOW(), INTERVAL 5 DAY)),
(14, 14, 5, DATE_SUB(CURDATE(), INTERVAL 4 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 4 DAY), DATE_SUB(NOW(), INTERVAL 4 DAY)),
(15, 15, 7, DATE_SUB(CURDATE(), INTERVAL 3 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 3 DAY), DATE_SUB(NOW(), INTERVAL 3 DAY)),
(16, 16, 2, DATE_SUB(CURDATE(), INTERVAL 6 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 6 DAY), DATE_SUB(NOW(), INTERVAL 6 DAY)),
(17, 17, 5, DATE_SUB(CURDATE(), INTERVAL 4 DAY), 2, 'Serviced', DATE_SUB(NOW(), INTERVAL 4 DAY), DATE_SUB(NOW(), INTERVAL 4 DAY)),
(18, 18, 7, DATE_SUB(CURDATE(), INTERVAL 2 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY)),
(19, 19, 1, DATE_SUB(CURDATE(), INTERVAL 7 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 7 DAY), DATE_SUB(NOW(), INTERVAL 7 DAY)),
(20, 20, 3, DATE_SUB(CURDATE(), INTERVAL 5 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 5 DAY), DATE_SUB(NOW(), INTERVAL 5 DAY)),
(21, 21, 7, DATE_SUB(CURDATE(), INTERVAL 2 DAY), 2, 'Serviced', DATE_SUB(NOW(), INTERVAL 2 DAY), DATE_SUB(NOW(), INTERVAL 2 DAY)),
(22, 22, 1, DATE_SUB(CURDATE(), INTERVAL 8 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 8 DAY), DATE_SUB(NOW(), INTERVAL 8 DAY)),
(23, 23, 2, DATE_SUB(CURDATE(), INTERVAL 3 DAY), 1, 'Skipped',  NULL, NULL),
(24, 24, 7, DATE_SUB(CURDATE(), INTERVAL 1 DAY), 1, 'Serviced', DATE_SUB(NOW(), INTERVAL 1 DAY), DATE_SUB(NOW(), INTERVAL 1 DAY));

-- ============================================================================
-- 8. CONSULTATION NOTES (Electronic Health Records)
-- ============================================================================
INSERT INTO `consultation_notes` (`note_id`, `appointment_id`, `chief_complaint`, `clinical_diagnosis`, `follow_up_recommended_days`) VALUES
(1,  1,  'Exertional dyspnea and retrosternal heaviness for 2 weeks.', 'Hypertensive heart disease; early coronary insufficiency.', 7),
(2,  6,  'Persistent dry cough and mild wheezing, aggravated at night.', 'Pediatric bronchial hyperreactivity; rule out atopy.', 5),
(3,  9,  'Frequent unprovoked migraine episodes with visual aura.', 'Chronic migraine with episodic aura.', 14),
(4,  12, 'Left knee severe joint pain and morning stiffness.', 'Primary knee osteoarthritis, Kellgren-Lawrence Grade III.', 10),
(5,  13, 'Follow-up on titrated anti-hypertensive regimen.', 'Essential hypertension, blood pressure now stabilized.', 30),
(6,  14, 'Tremors in right index finger at rest.', 'Benign essential tremor, early Parkinsonism ruled out.', 14),
(7,  15, 'Lumbar spine radiation pain down right leg.', 'L4-L5 disc protrusion with radiculopathy.', 7),
(8,  16, 'Occasional tachycardia episodes after caffeine intake.', 'Sinus tachycardia, structurally normal echocardiogram.', 15),
(9,  17, 'Bilateral tension headaches associated with prolonged screen time.', 'Tension-type cervical headache.', 7),
(10, 18, 'Post-traumatic wrist pain following gym hyperextension.', 'Scapholunate ligament sprain.', 10),
(11, 20, 'Seasonal allergic rhinitis and skin rash.', 'Atopic dermatitis with allergic rhinitis flare.', 7),
(12, 24, 'Right rotator cuff impingement during abduction.', 'Subacromial impingement syndrome.', 14);

-- ============================================================================
-- 9. PRESCRIBED INVESTIGATIONS (Diagnostic Workup)
-- ============================================================================
INSERT INTO `prescribed_investigations` (`investigation_id`, `note_id`, `test_name`, `clinical_priority`, `status`) VALUES
(1,  1,  '12-Lead Electrocardiogram (ECG)', 'Urgent', 'Reported'),
(2,  1,  '2D Transthoracic Echocardiography', 'Routine', 'Sample_Collected'),
(3,  1,  'Serum Troponin-I & CK-MB', 'Stat', 'Reported'),
(4,  2,  'Chest Radiograph (PA View)', 'Routine', 'Reported'),
(5,  2,  'Complete Blood Count (CBC) with Absolute Eosinophil Count', 'Routine', 'Reported'),
(6,  3,  'Magnetic Resonance Imaging (MRI) Brain without Contrast', 'Routine', 'Pending'),
(7,  4,  'Bilateral Knee Weight-Bearing X-Ray (AP & Lateral)', 'Routine', 'Reported'),
(8,  4,  'Serum Uric Acid & ESR', 'Routine', 'Reported'),
(9,  7,  'MRI Lumbosacral Spine', 'Urgent', 'Reported'),
(10, 8,  '24-Hour Ambulatory Holter ECG Monitoring', 'Routine', 'Sample_Collected'),
(11, 10, 'Wrist Dedicated Radiograph (3 Views)', 'Routine', 'Reported'),
(12, 12, 'Musculoskeletal Ultrasound - Right Shoulder', 'Routine', 'Pending');

-- ============================================================================
-- 10. BILLING INVOICES (Matching All 24 Appointments)
-- ============================================================================
INSERT INTO `billing_invoices` (`invoice_id`, `invoice_number`, `appointment_id`, `gross_fee`, `discount_amount`, `net_payable`, `payment_status`, `payment_mode`) VALUES
(1,  'INV260901001', 1,  1500.00, 450.00, 1050.00, 'Paid', 'Card'),
(2,  'INV260901002', 2,  1500.00,   0.00, 1500.00, 'Paid', 'Cash'),
(3,  'INV260901003', 3,  1500.00, 450.00, 1050.00, 'Paid', 'DigitalWallet'),
(4,  'INV260901004', 4,  1000.00,   0.00, 1000.00, 'Paid', 'Card'),
(5,  'INV260901005', 5,  1000.00,   0.00, 1000.00, 'Paid', 'Cash'),
(6,  'INV260901006', 6,  1200.00,   0.00, 1200.00, 'Paid', 'DigitalWallet'),
(7,  'INV260901007', 7,  1800.00,   0.00, 1800.00, 'Paid', 'Cash'),
(8,  'INV260901008', 8,   800.00,   0.00,  800.00, 'Paid', 'Card'),
(9,  'INV260901009', 9,  1800.00, 540.00, 1260.00, 'Paid', 'Insurance'),
(10, 'INV260901010', 10, 1800.00, 540.00, 1260.00, 'Paid', 'Card'),
(11, 'INV260901011', 11, 1200.00,   0.00, 1200.00, 'Paid', 'Cash'),
(12, 'INV260901012', 12, 1400.00, 420.00,  980.00, 'Paid', 'DigitalWallet'),
(13, 'INV260901013', 13, 1500.00, 450.00, 1050.00, 'Paid', 'Card'),
(14, 'INV260901014', 14, 1800.00, 540.00, 1260.00, 'Paid', 'Insurance'),
(15, 'INV260901015', 15, 1400.00, 420.00,  980.00, 'Paid', 'Card'),
(16, 'INV260901016', 16, 1000.00,   0.00, 1000.00, 'Paid', 'Cash'),
(17, 'INV260901017', 17, 1200.00,   0.00, 1200.00, 'Paid', 'Card'),
(18, 'INV260901018', 18, 1400.00,   0.00, 1400.00, 'Paid', 'DigitalWallet'),
(19, 'INV260901019', 19, 1500.00, 450.00, 1050.00, 'Paid', 'Card'),
(20, 'INV260901020', 20, 1200.00, 360.00,  840.00, 'Paid', 'Cash'),
(21, 'INV260901021', 21, 1400.00, 420.00,  980.00, 'Paid', 'DigitalWallet'),
(22, 'INV260901022', 22, 1500.00,   0.00, 1500.00, 'Paid', 'Insurance'),
(23, 'INV260901023', 23, 1000.00,   0.00, 1000.00, 'Refunded', 'Card'),
(24, 'INV260901024', 24, 1400.00,   0.00, 1400.00, 'Paid', 'Cash');

-- ============================================================================
-- 11. SCHEDULING AUDIT LOGS (Compliance Tracking)
-- ============================================================================
INSERT INTO `scheduling_audit_logs` (`log_id`, `entity_name`, `record_id`, `action_type`, `old_values`, `new_values`, `executed_by`, `logged_at`) VALUES
(1, 'appointments', 1,  'APPOINTMENT_BOOKED', NULL, JSON_OBJECT('status', 'Confirmed', 'slot', '09:00:00', 'fee', 1050.00), 'OPD_PORTAL_USER', DATE_SUB(NOW(), INTERVAL 1 DAY)),
(2, 'appointments', 23, 'CANCELLED', JSON_OBJECT('status', 'Confirmed', 'slot', '10:00:00'), JSON_OBJECT('status', 'Cancelled', 'reason', 'Patient travel delay'), 'RECEPTIONIST_01', DATE_SUB(NOW(), INTERVAL 3 DAY)),
(3, 'appointments', 7,  'APPOINTMENT_BOOKED', NULL, JSON_OBJECT('status', 'Confirmed', 'triage', 'Emergency', 'fee', 1800.00), 'TRIAGE_NURSE_02', NOW());

-- ============================================================================
-- Verification Count Check
-- ============================================================================
SELECT 'clinical_departments'    AS Table_Name, COUNT(*) AS Row_Count FROM `clinical_departments`
UNION ALL
SELECT 'consultation_rooms',     COUNT(*) FROM `consultation_rooms`
UNION ALL
SELECT 'doctors',                COUNT(*) FROM `doctors`
UNION ALL
SELECT 'doctor_schedules',       COUNT(*) FROM `doctor_schedules`
UNION ALL
SELECT 'patients',               COUNT(*) FROM `patients`
UNION ALL
SELECT 'appointments',           COUNT(*) FROM `appointments`
UNION ALL
SELECT 'opd_queue_tokens',       COUNT(*) FROM `opd_queue_tokens`
UNION ALL
SELECT 'consultation_notes',     COUNT(*) FROM `consultation_notes`
UNION ALL
SELECT 'prescribed_investigations', COUNT(*) FROM `prescribed_investigations`
UNION ALL
SELECT 'billing_invoices',       COUNT(*) FROM `billing_invoices`
UNION ALL
SELECT 'scheduling_audit_logs',  COUNT(*) FROM `scheduling_audit_logs`;

-- ============================================================================
-- End of 05_seed_data.sql
-- ============================================================================
