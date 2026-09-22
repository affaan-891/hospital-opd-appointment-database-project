-- ============================================================================
-- Project: Hospital OPD Multi-Specialty Appointment & Room Scheduling System
-- Target Engine: MySQL 8.0+ (InnoDB)
-- File: 02_triggers.sql (Business Logic Integrity & Auditing)
-- Author: Principal Database Architect & University DBMS Evaluator
-- Repository: https://github.com/affaan-891/hospital-opd-appointment-database-project
-- ============================================================================

USE `hospital_opd_db`;

-- ============================================================================
-- TRIGGER 1: trg_prevent_doctor_roster_room_clash
-- Event: BEFORE INSERT ON doctor_schedules
-- Purpose: Prevents double-booking physical consultation rooms across doctors.
-- Algorithm: Interval overlap test between (shift_start, shift_end):
--            Overlap exists iff: NEW.shift_start < existing.shift_end 
--                           AND NEW.shift_end > existing.shift_start
-- Exception: Throws SQLSTATE '45000' with descriptive clinical roster message.
-- ============================================================================
DROP TRIGGER IF EXISTS `trg_prevent_doctor_roster_room_clash_insert`;

DELIMITER //

CREATE TRIGGER `trg_prevent_doctor_roster_room_clash_insert`
BEFORE INSERT ON `doctor_schedules`
FOR EACH ROW
BEGIN
    DECLARE v_clash_count INT DEFAULT 0;
    DECLARE v_doctor_name VARCHAR(100);

    -- Check for overlapping active shifts in the same room on the same day
    SELECT COUNT(*), CONCAT(d.first_name, ' ', d.last_name)
    INTO v_clash_count, v_doctor_name
    FROM `doctor_schedules` s
    INNER JOIN `doctors` d ON s.doctor_id = d.doctor_id
    WHERE s.room_id = NEW.room_id
      AND s.day_of_week = NEW.day_of_week
      AND s.is_active = TRUE
      AND (NEW.shift_start < s.shift_end AND NEW.shift_end > s.shift_start)
    GROUP BY d.doctor_id
    LIMIT 1;

    IF v_clash_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Roster Conflict: Consultation room is already booked by another doctor for this day and time window.';
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- TRIGGER 1b: trg_prevent_doctor_roster_room_clash_update
-- Event: BEFORE UPDATE ON doctor_schedules
-- Purpose: Ensures schedule modifications do not introduce room collisions.
-- ============================================================================
DROP TRIGGER IF EXISTS `trg_prevent_doctor_roster_room_clash_update`;

DELIMITER //

CREATE TRIGGER `trg_prevent_doctor_roster_room_clash_update`
BEFORE UPDATE ON `doctor_schedules`
FOR EACH ROW
BEGIN
    DECLARE v_clash_count INT DEFAULT 0;

    -- Evaluate overlap excluding the current schedule row being updated
    SELECT COUNT(*)
    INTO v_clash_count
    FROM `doctor_schedules` s
    WHERE s.room_id = NEW.room_id
      AND s.day_of_week = NEW.day_of_week
      AND s.schedule_id != NEW.schedule_id
      AND s.is_active = TRUE
      AND (NEW.shift_start < s.shift_end AND NEW.shift_end > s.shift_start);

    IF v_clash_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Roster Conflict: Consultation room is already booked by another doctor for this day and time window.';
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- TRIGGER 2: trg_enforce_daily_opd_patient_limit
-- Event: BEFORE INSERT ON appointments
-- Purpose: Guarantees patient safety and prevents clinical burn-out by
--          enforcing maximum daily patient quota defined per doctor.
-- Exception: Throws SQLSTATE '45000' when quota is exhausted.
-- ============================================================================
DROP TRIGGER IF EXISTS `trg_enforce_daily_opd_patient_limit`;

DELIMITER //

CREATE TRIGGER `trg_enforce_daily_opd_patient_limit`
BEFORE INSERT ON `appointments`
FOR EACH ROW
BEGIN
    DECLARE v_max_patients INT DEFAULT 0;
    DECLARE v_current_booked INT DEFAULT 0;

    -- Retrieve physician maximum daily quota
    SELECT max_daily_patients
    INTO v_max_patients
    FROM `doctors`
    WHERE doctor_id = NEW.doctor_id;

    -- Count active bookings (excluding cancelled consultations)
    SELECT COUNT(*)
    INTO v_current_booked
    FROM `appointments`
    WHERE doctor_id = NEW.doctor_id
      AND appointment_date = NEW.appointment_date
      AND booking_status != 'Cancelled';

    IF v_current_booked >= v_max_patients THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Doctor Daily Capacity Reached: Cannot schedule more patients for this date.';
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- TRIGGER 3: trg_log_appointment_cancellation
-- Event: AFTER UPDATE ON appointments
-- Purpose: Automatically audits cancelled appointments with historical state
--          snapshots in JSON format for hospital administrative compliance.
-- ============================================================================
DROP TRIGGER IF EXISTS `trg_log_appointment_cancellation`;

DELIMITER //

CREATE TRIGGER `trg_log_appointment_cancellation`
AFTER UPDATE ON `appointments`
FOR EACH ROW
BEGIN
    -- Detect state transition into 'Cancelled'
    IF OLD.booking_status = 'Confirmed' AND NEW.booking_status = 'Cancelled' THEN
        INSERT INTO `scheduling_audit_logs` (
            `entity_name`,
            `record_id`,
            `action_type`,
            `old_values`,
            `new_values`,
            `executed_by`,
            `logged_at`
        ) VALUES (
            'appointments',
            NEW.appointment_id,
            'CANCELLED',
            JSON_OBJECT(
                'booking_status', OLD.booking_status,
                'appointment_date', OLD.appointment_date,
                'slot_time', OLD.slot_time,
                'doctor_id', OLD.doctor_id,
                'mrn_number', OLD.mrn_number,
                'fee_category', OLD.fee_category,
                'consultation_fee', OLD.consultation_fee
            ),
            JSON_OBJECT(
                'booking_status', NEW.booking_status,
                'cancellation_timestamp', NOW()
            ),
            COALESCE(@current_app_user, CURRENT_USER()),
            CURRENT_TIMESTAMP
        );
    END IF;
END //

DELIMITER ;

-- ============================================================================
-- End of 02_triggers.sql
-- ============================================================================
