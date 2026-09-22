-- ============================================================================
-- Project: Hospital OPD Multi-Specialty Appointment & Room Scheduling System
-- Target Engine: MySQL 8.0+ (InnoDB)
-- File: 01_schema.sql (Data Definition Language)
-- Normalization: Strictly 3NF Compliant
-- Author: Principal Database Architect & University DBMS Evaluator
-- Repository: https://github.com/affaan-891/hospital-opd-appointment-database-project
-- ============================================================================

-- Drop database if already exists to ensure clean idempotent builds
DROP DATABASE IF EXISTS `hospital_opd_db`;

-- Create schema with UTF-8 Multilingual 4-byte support
CREATE DATABASE `hospital_opd_db`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `hospital_opd_db`;

-- Disable foreign key checks temporarily during schema setup
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================================
-- TABLE 1: clinical_departments
-- Represents medical specialties / OPD departments within the hospital.
-- 3NF: All attributes depend strictly on primary key `dept_id`.
-- ============================================================================
DROP TABLE IF EXISTS `clinical_departments`;
CREATE TABLE `clinical_departments` (
    `dept_id` INT AUTO_INCREMENT PRIMARY KEY,
    `dept_code` VARCHAR(10) NOT NULL,
    `dept_name` VARCHAR(100) NOT NULL,
    `floor_number` INT NOT NULL,
    `emergency_supported` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_clinical_dept_code` UNIQUE (`dept_code`),
    CONSTRAINT `chk_dept_floor` CHECK (`floor_number` BETWEEN -2 AND 20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 2: consultation_rooms
-- Physical OPD consultation rooms allocated to departments.
-- 3NF: `dept_id` is a foreign key; room operational state is captured here.
-- ============================================================================
DROP TABLE IF EXISTS `consultation_rooms`;
CREATE TABLE `consultation_rooms` (
    `room_id` INT AUTO_INCREMENT PRIMARY KEY,
    `room_number` VARCHAR(20) NOT NULL,
    `dept_id` INT NOT NULL,
    `room_type` ENUM('Consultation', 'Procedure', 'Specialist_Suite') NOT NULL DEFAULT 'Consultation',
    `is_operational` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_room_number` UNIQUE (`room_number`),
    CONSTRAINT `fk_rooms_dept` 
        FOREIGN KEY (`dept_id`) REFERENCES `clinical_departments` (`dept_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_rooms_dept_operational` ON `consultation_rooms` (`dept_id`, `is_operational`);

-- ============================================================================
-- TABLE 3: doctors
-- Medical practitioners affiliated with clinical departments.
-- 3NF: Doctor profile, medical license, ranking, and daily capacity limits.
-- ============================================================================
DROP TABLE IF EXISTS `doctors`;
CREATE TABLE `doctors` (
    `doctor_id` INT AUTO_INCREMENT PRIMARY KEY,
    `medical_license_number` VARCHAR(30) NOT NULL,
    `first_name` VARCHAR(50) NOT NULL,
    `last_name` VARCHAR(50) NOT NULL,
    `dept_id` INT NOT NULL,
    `designation` ENUM(
        'Medical_Officer',
        'Senior_Registrar',
        'Assistant_Professor',
        'Consultant_Professor'
    ) NOT NULL DEFAULT 'Medical_Officer',
    `base_consultation_fee` DECIMAL(8, 2) NOT NULL,
    `max_daily_patients` INT NOT NULL DEFAULT 30,
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_doctor_license` UNIQUE (`medical_license_number`),
    CONSTRAINT `chk_base_consultation_fee` CHECK (`base_consultation_fee` > 0),
    CONSTRAINT `chk_max_daily_patients` CHECK (`max_daily_patients` > 0),
    CONSTRAINT `fk_doctors_department` 
        FOREIGN KEY (`dept_id`) REFERENCES `clinical_departments` (`dept_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_doctors_dept_designation` ON `doctors` (`dept_id`, `designation`);

-- ============================================================================
-- TABLE 4: doctor_schedules
-- Master duty roster assigning doctors to consultation rooms on specific days and shifts.
-- 3NF: Time ranges ensure deterministic weekly scheduling without redundant patient data.
-- ============================================================================
DROP TABLE IF EXISTS `doctor_schedules`;
CREATE TABLE `doctor_schedules` (
    `schedule_id` INT AUTO_INCREMENT PRIMARY KEY,
    `doctor_id` INT NOT NULL,
    `room_id` INT NOT NULL,
    `day_of_week` ENUM('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun') NOT NULL,
    `shift_start` TIME NOT NULL,
    `shift_end` TIME NOT NULL,
    `is_active` BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT `chk_shift_time_window` CHECK (`shift_start` < `shift_end`),
    CONSTRAINT `uq_doctor_day_shift` UNIQUE (`doctor_id`, `day_of_week`, `shift_start`),
    CONSTRAINT `uq_room_day_shift` UNIQUE (`room_id`, `day_of_week`, `shift_start`),
    CONSTRAINT `fk_schedules_doctor` 
        FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`doctor_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_schedules_room` 
        FOREIGN KEY (`room_id`) REFERENCES `consultation_rooms` (`room_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_sched_room_day` ON `doctor_schedules` (`room_id`, `day_of_week`, `shift_start`, `shift_end`);

-- ============================================================================
-- TABLE 5: patients
-- Patient master records with demographic, contact, and MRN identifiers.
-- 3NF: No appointment or billing attributes stored here to eliminate update anomalies.
-- ============================================================================
DROP TABLE IF EXISTS `patients`;
CREATE TABLE `patients` (
    `patient_id` INT AUTO_INCREMENT PRIMARY KEY,
    `mrn_number` CHAR(10) NOT NULL,
    `first_name` VARCHAR(50) NOT NULL,
    `last_name` VARCHAR(50) NOT NULL,
    `gender` ENUM('M', 'F', 'Other') NOT NULL,
    `dob` DATE NOT NULL,
    `phone` VARCHAR(20) NOT NULL,
    `national_id` VARCHAR(30) NOT NULL,
    `registered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_patient_mrn` UNIQUE (`mrn_number`),
    CONSTRAINT `uq_patient_phone` UNIQUE (`phone`),
    CONSTRAINT `uq_patient_national_id` UNIQUE (`national_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_patients_dob` ON `patients` (`dob`);

-- ============================================================================
-- TABLE 6: appointments
-- Outpatient consultation bookings.
-- 3NF: References patients via `mrn_number`, doctors, and operational schedules.
-- Composite Unique constraint prevents double-booking a doctor at the same slot.
-- ============================================================================
DROP TABLE IF EXISTS `appointments`;
CREATE TABLE `appointments` (
    `appointment_id` INT AUTO_INCREMENT PRIMARY KEY,
    `mrn_number` CHAR(10) NOT NULL,
    `doctor_id` INT NOT NULL,
    `schedule_id` INT NOT NULL,
    `appointment_date` DATE NOT NULL,
    `slot_time` TIME NOT NULL,
    `booking_status` ENUM('Confirmed', 'CheckedIn', 'Completed', 'Cancelled', 'NoShow') NOT NULL DEFAULT 'Confirmed',
    `fee_category` ENUM('Standard', 'FollowUp', 'SeniorCitizen', 'Emergency') NOT NULL DEFAULT 'Standard',
    `consultation_fee` DECIMAL(8, 2) NOT NULL,
    `booked_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_doctor_date_slot` UNIQUE (`doctor_id`, `appointment_date`, `slot_time`),
    CONSTRAINT `chk_appt_fee` CHECK (`consultation_fee` >= 0),
    CONSTRAINT `fk_appts_patient` 
        FOREIGN KEY (`mrn_number`) REFERENCES `patients` (`mrn_number`) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_appts_doctor` 
        FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`doctor_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_appts_schedule` 
        FOREIGN KEY (`schedule_id`) REFERENCES `doctor_schedules` (`schedule_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_appts_doctor_date_status` ON `appointments` (`doctor_id`, `appointment_date`, `booking_status`);
CREATE INDEX `idx_appts_patient_date` ON `appointments` (`mrn_number`, `appointment_date`);

-- ============================================================================
-- TABLE 7: opd_queue_tokens
-- Daily token queue management for real-time OPD flow tracking.
-- 3NF: 1:1 relationship with appointments; tracks dynamic triage lifecycle.
-- ============================================================================
DROP TABLE IF EXISTS `opd_queue_tokens`;
CREATE TABLE `opd_queue_tokens` (
    `token_id` INT AUTO_INCREMENT PRIMARY KEY,
    `appointment_id` INT NOT NULL,
    `doctor_id` INT NOT NULL,
    `queue_date` DATE NOT NULL,
    `token_number` INT NOT NULL,
    `queue_status` ENUM('Waiting', 'In_Consultation', 'Serviced', 'Skipped') NOT NULL DEFAULT 'Waiting',
    `called_at` DATETIME NULL DEFAULT NULL,
    `completed_at` DATETIME NULL DEFAULT NULL,
    CONSTRAINT `uq_token_appointment` UNIQUE (`appointment_id`),
    CONSTRAINT `uq_doctor_date_token` UNIQUE (`doctor_id`, `queue_date`, `token_number`),
    CONSTRAINT `chk_token_positive` CHECK (`token_number` > 0),
    CONSTRAINT `fk_tokens_appointment` 
        FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`appointment_id`) 
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_tokens_doctor` 
        FOREIGN KEY (`doctor_id`) REFERENCES `doctors` (`doctor_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_tokens_queue_lookup` ON `opd_queue_tokens` (`doctor_id`, `queue_date`, `queue_status`);

-- ============================================================================
-- TABLE 8: consultation_notes
-- Electronic Health Record (EHR) documentation authored by the physician.
-- 3NF: 1:1 relationship with `appointments`. Separates clinical notes from billing/scheduling.
-- ============================================================================
DROP TABLE IF EXISTS `consultation_notes`;
CREATE TABLE `consultation_notes` (
    `note_id` INT AUTO_INCREMENT PRIMARY KEY,
    `appointment_id` INT NOT NULL,
    `chief_complaint` TEXT NOT NULL,
    `clinical_diagnosis` TEXT NOT NULL,
    `follow_up_recommended_days` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_notes_appointment` UNIQUE (`appointment_id`),
    CONSTRAINT `chk_follow_up_days` CHECK (`follow_up_recommended_days` >= 0),
    CONSTRAINT `fk_notes_appointment` 
        FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`appointment_id`) 
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- TABLE 9: prescribed_investigations
-- Diagnostic tests (Lab/Radiology) ordered during outpatient consultation.
-- 3NF: 1:N relationship with `consultation_notes`.
-- ============================================================================
DROP TABLE IF EXISTS `prescribed_investigations`;
CREATE TABLE `prescribed_investigations` (
    `investigation_id` INT AUTO_INCREMENT PRIMARY KEY,
    `note_id` INT NOT NULL,
    `test_name` VARCHAR(100) NOT NULL,
    `clinical_priority` ENUM('Routine', 'Urgent', 'Stat') NOT NULL DEFAULT 'Routine',
    `status` ENUM('Pending', 'Sample_Collected', 'Reported') NOT NULL DEFAULT 'Pending',
    `prescribed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_investigations_note` 
        FOREIGN KEY (`note_id`) REFERENCES `consultation_notes` (`note_id`) 
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_investigations_status` ON `prescribed_investigations` (`note_id`, `status`);

-- ============================================================================
-- TABLE 10: billing_invoices
-- Financial invoices generated upon appointment confirmation.
-- 3NF: 1:1 relationship with `appointments`. Tracks gross, discounts, and net payable.
-- ============================================================================
DROP TABLE IF EXISTS `billing_invoices`;
CREATE TABLE `billing_invoices` (
    `invoice_id` INT AUTO_INCREMENT PRIMARY KEY,
    `invoice_number` CHAR(12) NOT NULL,
    `appointment_id` INT NOT NULL,
    `gross_fee` DECIMAL(8, 2) NOT NULL,
    `discount_amount` DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    `net_payable` DECIMAL(8, 2) NOT NULL,
    `payment_status` ENUM('Paid', 'Waived', 'Refunded') NOT NULL DEFAULT 'Paid',
    `payment_mode` ENUM('Cash', 'Card', 'Insurance', 'DigitalWallet') NOT NULL,
    `billed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `uq_billing_invoice_num` UNIQUE (`invoice_number`),
    CONSTRAINT `uq_billing_appointment` UNIQUE (`appointment_id`),
    CONSTRAINT `chk_invoice_math` CHECK (`gross_fee` >= 0 AND `discount_amount` >= 0 AND `net_payable` >= 0),
    CONSTRAINT `fk_invoices_appointment` 
        FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`appointment_id`) 
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_invoices_status_date` ON `billing_invoices` (`payment_status`, `billed_at`);

-- ============================================================================
-- TABLE 11: scheduling_audit_logs
-- Immutable compliance and audit ledger storing historical state snapshots.
-- Captures state transitions (cancellations, reschedules, overrides) as JSON payloads.
-- ============================================================================
DROP TABLE IF EXISTS `scheduling_audit_logs`;
CREATE TABLE `scheduling_audit_logs` (
    `log_id` INT AUTO_INCREMENT PRIMARY KEY,
    `entity_name` VARCHAR(50) NOT NULL,
    `record_id` INT NOT NULL,
    `action_type` ENUM(
        'APPOINTMENT_BOOKED',
        'RESCHEDULED',
        'CANCELLED',
        'ROOM_OVERRIDE',
        'TOKEN_SKIPPED'
    ) NOT NULL,
    `old_values` JSON NULL,
    `new_values` JSON NULL,
    `executed_by` VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    `logged_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX `idx_audit_entity_record` ON `scheduling_audit_logs` (`entity_name`, `record_id`);
CREATE INDEX `idx_audit_action_date` ON `scheduling_audit_logs` (`action_type`, `logged_at`);

-- Re-enable foreign key constraints
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- End of 01_schema.sql
-- ============================================================================
