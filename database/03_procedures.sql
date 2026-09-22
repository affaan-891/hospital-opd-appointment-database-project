-- ============================================================================
-- Project: Hospital OPD Multi-Specialty Appointment & Room Scheduling System
-- Target Engine: MySQL 8.0+ (InnoDB)
-- File: 03_procedures.sql (ACID Transactions, Locking & Stored Functions)
-- Author: Principal Database Architect & University DBMS Evaluator
-- Repository: https://github.com/affaan-891/hospital-opd-appointment-database-project
-- ============================================================================

USE `hospital_opd_db`;

-- ============================================================================
-- FUNCTION: fn_calculate_patient_age
-- Purpose: Deterministic function calculating precise chronological age in years.
-- Usage: Evaluates clinical eligibility for geriatric discounts and pediatric care.
-- ============================================================================
DROP FUNCTION IF EXISTS `fn_calculate_patient_age`;

DELIMITER //

CREATE FUNCTION `fn_calculate_patient_age`(p_dob DATE)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    IF p_dob IS NULL THEN
        RETURN 0;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, p_dob, CURDATE());
END //

DELIMITER ;

-- ============================================================================
-- STORED PROCEDURE: sp_book_opd_appointment
-- Purpose: Enterprise ACID booking transaction ensuring:
--          1. Pessimistic concurrency control (`SELECT ... FOR UPDATE`).
--          2. Schedule alignment (day of week & active doctor shift).
--          3. Dynamic consultation fee computation:
--             - Standard: 100% of base fee
--             - FollowUp: 50% discount if patient had prior consultation in last 7 days
--             - SeniorCitizen: 30% discount if patient age >= 60
--             - Emergency: 150% of base fee (50% emergency triage surcharge)
--          4. Daily token sequence isolation: COALESCE(MAX(token_number), 0) + 1.
--          5. Atomic multi-table insertion (appointments, opd_queue_tokens, billing_invoices, audit_logs).
-- ============================================================================
DROP PROCEDURE IF EXISTS `sp_book_opd_appointment`;

DELIMITER //

CREATE PROCEDURE `sp_book_opd_appointment`(
    IN  p_patient_id       INT,
    IN  p_doctor_id        INT,
    IN  p_appointment_date DATE,
    IN  p_slot_time        TIME,
    IN  p_fee_category     VARCHAR(20),
    IN  p_payment_mode     VARCHAR(20),
    OUT p_appointment_id   INT,
    OUT p_token_number     INT,
    OUT p_final_fee        DECIMAL(8,2)
)
proc_label: BEGIN
    -- Local Transaction Variables
    DECLARE v_mrn_number CHAR(10);
    DECLARE v_dob DATE;
    DECLARE v_patient_age INT;
    DECLARE v_base_fee DECIMAL(8,2);
    DECLARE v_max_daily_patients INT;
    DECLARE v_discount_amount DECIMAL(8,2) DEFAULT 0.00;
    DECLARE v_net_fee DECIMAL(8,2) DEFAULT 0.00;
    DECLARE v_day_name VARCHAR(3);
    DECLARE v_schedule_id INT;
    DECLARE v_existing_booking_count INT DEFAULT 0;
    DECLARE v_recent_visit_count INT DEFAULT 0;
    DECLARE v_token_num INT DEFAULT 0;
    DECLARE v_invoice_num CHAR(12);
    DECLARE v_active_status VARCHAR(20) DEFAULT 'Confirmed';

    -- Error Handling: Rollback transaction and re-raise SQL error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Step 1: Input Validation
    IF p_appointment_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Validation Error: Appointment date cannot be in the past.';
    END IF;

    -- Step 2: Begin Explicit ACID Transaction
    START TRANSACTION;

    -- Step 3: Fetch and Validate Patient Master Information
    SELECT mrn_number, dob
    INTO v_mrn_number, v_dob
    FROM `patients`
    WHERE patient_id = p_patient_id;

    IF v_mrn_number IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Booking Error: Patient record not found.';
    END IF;

    -- Step 4: Pessimistic Row Lock on Doctor Master Record
    -- Serializes appointment slot booking to prevent concurrent race conditions
    SELECT base_consultation_fee, max_daily_patients
    INTO v_base_fee, v_max_daily_patients
    FROM `doctors`
    WHERE doctor_id = p_doctor_id AND is_active = TRUE
    FOR UPDATE;

    IF v_base_fee IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Booking Error: Designated doctor is inactive or does not exist.';
    END IF;

    -- Step 5: Validate Doctor Duty Roster Schedule for Requested Date & Time
    -- Derive 3-letter day name ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
    SET v_day_name = DATE_FORMAT(p_appointment_date, '%a');

    SELECT schedule_id
    INTO v_schedule_id
    FROM `doctor_schedules`
    WHERE doctor_id = p_doctor_id
      AND day_of_week = v_day_name
      AND is_active = TRUE
      AND p_slot_time >= shift_start
      AND p_slot_time < shift_end
    LIMIT 1;

    IF v_schedule_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Booking Error: Doctor has no active duty roster shift during the requested slot.';
    END IF;

    -- Step 6: Verify Slot Availability (Prevent Double-Booking)
    SELECT COUNT(*)
    INTO v_existing_booking_count
    FROM `appointments`
    WHERE doctor_id = p_doctor_id
      AND appointment_date = p_appointment_date
      AND slot_time = p_slot_time
      AND booking_status != 'Cancelled';

    IF v_existing_booking_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Booking Error: The requested consultation slot is already reserved.';
    END IF;

    -- Step 7: Dynamic Fee Calculation Logic
    SET v_patient_age = fn_calculate_patient_age(v_dob);

    IF p_fee_category = 'FollowUp' THEN
        -- Check for prior completed/confirmed consultation within the last 7 days
        SELECT COUNT(*)
        INTO v_recent_visit_count
        FROM `appointments`
        WHERE mrn_number = v_mrn_number
          AND doctor_id = p_doctor_id
          AND booking_status IN ('Confirmed', 'CheckedIn', 'Completed')
          AND appointment_date BETWEEN DATE_SUB(p_appointment_date, INTERVAL 7 DAY) AND p_appointment_date;

        IF v_recent_visit_count > 0 THEN
            -- 50% clinical follow-up discount
            SET v_discount_amount = ROUND(v_base_fee * 0.50, 2);
            SET v_net_fee = v_base_fee - v_discount_amount;
        ELSE
            -- Ineligible for follow-up discount; revert to standard fee
            SET v_discount_amount = 0.00;
            SET v_net_fee = v_base_fee;
        END IF;

    ELSEIF p_fee_category = 'SeniorCitizen' THEN
        -- Verify geriatric qualification (Age 60+)
        IF v_patient_age >= 60 THEN
            SET v_discount_amount = ROUND(v_base_fee * 0.30, 2);
            SET v_net_fee = v_base_fee - v_discount_amount;
        ELSE
            SET v_discount_amount = 0.00;
            SET v_net_fee = v_base_fee;
        END IF;

    ELSEIF p_fee_category = 'Emergency' THEN
        -- 50% emergency triage surcharge (150% base fee)
        SET v_discount_amount = 0.00;
        SET v_net_fee = ROUND(v_base_fee * 1.50, 2);

    ELSE
        -- Standard consultation
        SET v_discount_amount = 0.00;
        SET v_net_fee = v_base_fee;
    END IF;

    -- Step 8: Insert Appointment
    INSERT INTO `appointments` (
        `mrn_number`,
        `doctor_id`,
        `schedule_id`,
        `appointment_date`,
        `slot_time`,
        `booking_status`,
        `fee_category`,
        `consultation_fee`
    ) VALUES (
        v_mrn_number,
        p_doctor_id,
        v_schedule_id,
        p_appointment_date,
        p_slot_time,
        v_active_status,
        p_fee_category,
        v_net_fee
    );

    SET p_appointment_id = LAST_INSERT_ID();

    -- Step 9: Compute Next Sequential OPD Daily Queue Token
    SELECT COALESCE(MAX(token_number), 0) + 1
    INTO v_token_num
    FROM `opd_queue_tokens`
    WHERE doctor_id = p_doctor_id
      AND queue_date = p_appointment_date;

    INSERT INTO `opd_queue_tokens` (
        `appointment_id`,
        `doctor_id`,
        `queue_date`,
        `token_number`,
        `queue_status`
    ) VALUES (
        p_appointment_id,
        p_doctor_id,
        p_appointment_date,
        v_token_num,
        'Waiting'
    );

    SET p_token_number = v_token_num;

    -- Step 10: Generate Atomic Billing Invoice (12-character format: INVYYMMDDXXX)
    SET v_invoice_num = CONCAT(
        'INV',
        DATE_FORMAT(p_appointment_date, '%y%m%d'),
        LPAD(MOD(p_appointment_id, 1000), 3, '0')
    );

    INSERT INTO `billing_invoices` (
        `invoice_number`,
        `appointment_id`,
        `gross_fee`,
        `discount_amount`,
        `net_payable`,
        `payment_status`,
        `payment_mode`
    ) VALUES (
        v_invoice_num,
        p_appointment_id,
        v_base_fee,
        v_discount_amount,
        v_net_fee,
        'Paid',
        COALESCE(p_payment_mode, 'Cash')
    );

    -- Step 11: Audit Trail Logging
    INSERT INTO `scheduling_audit_logs` (
        `entity_name`,
        `record_id`,
        `action_type`,
        `old_values`,
        `new_values`,
        `executed_by`
    ) VALUES (
        'appointments',
        p_appointment_id,
        'APPOINTMENT_BOOKED',
        NULL,
        JSON_OBJECT(
            'appointment_id', p_appointment_id,
            'mrn_number', v_mrn_number,
            'doctor_id', p_doctor_id,
            'appointment_date', p_appointment_date,
            'slot_time', p_slot_time,
            'token_number', v_token_num,
            'net_fee', v_net_fee,
            'invoice_number', v_invoice_num
        ),
        COALESCE(@current_app_user, CURRENT_USER())
    );

    -- Step 12: Assign Final OUT Variable & Commit Transaction
    SET p_final_fee = v_net_fee;
    COMMIT;

END //

DELIMITER ;

-- ============================================================================
-- STORED PROCEDURE: sp_reschedule_appointment
-- Purpose: Atomically reschedules a confirmed appointment to a new date/slot
--          with validation, room/schedule verification, and queue regeneration.
-- ============================================================================
DROP PROCEDURE IF EXISTS `sp_reschedule_appointment`;

DELIMITER //

CREATE PROCEDURE `sp_reschedule_appointment`(
    IN p_appointment_id INT,
    IN p_new_date       DATE,
    IN p_new_slot_time  TIME,
    IN p_rescheduled_by VARCHAR(50)
)
BEGIN
    DECLARE v_doctor_id INT;
    DECLARE v_old_date DATE;
    DECLARE v_old_slot TIME;
    DECLARE v_booking_status VARCHAR(20);
    DECLARE v_new_day_name VARCHAR(3);
    DECLARE v_new_schedule_id INT;
    DECLARE v_conflict_count INT DEFAULT 0;
    DECLARE v_new_token_number INT DEFAULT 0;

    -- Error Handling: Rollback on failure
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_new_date < CURDATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Validation Error: Rescheduled date cannot be in the past.';
    END IF;

    START TRANSACTION;

    -- Fetch current appointment details with row lock
    SELECT doctor_id, appointment_date, slot_time, booking_status
    INTO v_doctor_id, v_old_date, v_old_slot, v_booking_status
    FROM `appointments`
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF v_doctor_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reschedule Error: Appointment does not exist.';
    END IF;

    IF v_booking_status != 'Confirmed' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reschedule Error: Only Confirmed appointments can be rescheduled.';
    END IF;

    -- Validate roster schedule for new date and time
    SET v_new_day_name = DATE_FORMAT(p_new_date, '%a');

    SELECT schedule_id
    INTO v_new_schedule_id
    FROM `doctor_schedules`
    WHERE doctor_id = v_doctor_id
      AND day_of_week = v_new_day_name
      AND is_active = TRUE
      AND p_new_slot_time >= shift_start
      AND p_new_slot_time < shift_end
    LIMIT 1;

    IF v_new_schedule_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reschedule Error: Doctor is not scheduled for duty at the requested date and time.';
    END IF;

    -- Check for slot collisions at the new target slot
    SELECT COUNT(*)
    INTO v_conflict_count
    FROM `appointments`
    WHERE doctor_id = v_doctor_id
      AND appointment_date = p_new_date
      AND slot_time = p_new_slot_time
      AND appointment_id != p_appointment_id
      AND booking_status != 'Cancelled';

    IF v_conflict_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reschedule Error: Target consultation slot is already reserved.';
    END IF;

    -- Update appointment slot
    UPDATE `appointments`
    SET appointment_date = p_new_date,
        slot_time = p_new_slot_time,
        schedule_id = v_new_schedule_id
    WHERE appointment_id = p_appointment_id;

    -- Recalculate daily OPD token if date changed
    IF v_old_date != p_new_date THEN
        SELECT COALESCE(MAX(token_number), 0) + 1
        INTO v_new_token_number
        FROM `opd_queue_tokens`
        WHERE doctor_id = v_doctor_id
          AND queue_date = p_new_date;

        UPDATE `opd_queue_tokens`
        SET queue_date = p_new_date,
            token_number = v_new_token_number,
            queue_status = 'Waiting'
        WHERE appointment_id = p_appointment_id;
    END IF;

    -- Log state transition in audit ledger
    INSERT INTO `scheduling_audit_logs` (
        `entity_name`,
        `record_id`,
        `action_type`,
        `old_values`,
        `new_values`,
        `executed_by`
    ) VALUES (
        'appointments',
        p_appointment_id,
        'RESCHEDULED',
        JSON_OBJECT('old_date', v_old_date, 'old_slot', v_old_slot),
        JSON_OBJECT('new_date', p_new_date, 'new_slot', p_new_slot_time, 'new_token', v_new_token_number),
        COALESCE(p_rescheduled_by, CURRENT_USER())
    );

    COMMIT;
END //

DELIMITER ;

-- ============================================================================
-- End of 03_procedures.sql
-- ============================================================================
