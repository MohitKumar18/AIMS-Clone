CREATE USER dean_acads WITH PASSWORD 'iitropar';
CREATE USER acads_office WITH PASSWORD 'iitropar';

CREATE DATABASE AIMS;

CREATE TABLE course_catalog (
    course_id VARCHAR(10) UNIQUE PRIMARY KEY,
    course_title VARCHAR(255) NOT NULL,
    lecture INT NOT NULL,
    tutorial INT NOT NULL,
    practical INT NOT NULL,
    self_study FLOAT NOT NULL,
    credits FLOAT NOT NULL
);

CREATE TABLE time_table_slots (
    id INT UNIQUE PRIMARY KEY,
    day VARCHAR(10),
    beginning TIME,
    ending TIME
);

CREATE TABLE course_offering (
    offering_id VARCHAR(255) UNIQUE PRIMARY KEY,
    faculty_id INT NOT NULL,
    course_id VARCHAR(10) NOT NULL,
    semester INT NOT NULL,
    year INT NOT NULL,
    time_slot INT [] NOT NULL
);

CREATE TABLE student_credit_info (
    entry_number VARCHAR(15) NOT NULL,
    last_semester INT,
    second_last_semester INT,
    maximum_credits_allowed FLOAT
);

CREATE TABLE student_database (
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    entry_number VARCHAR(15),
    course VARCHAR(100),
    branch VARCHAR(100),
    year INT,
    credits_completed FLOAT,
    cgpa FLOAT
);

CREATE TABLE faculty_database (
    faculty_id INT PRIMARY KEY,
    first_name varchar(100),
    last_name varchar(100),
    department varchar(100)
);

CREATE TABLE batchwise_FA_list (
    course VARCHAR(100),
    branch VARCHAR(100),
    year INT,
    faculty_id INT
);

CREATE TABLE dean_ticket_table (
    ticket_id VARCHAR(255) PRIMARY KEY,
    entry_number VARCHAR(15),
    extra_credits_required FLOAT,
    status VARCHAR(255)
);

CREATE OR REPLACE FUNCTION student_ticket_generator (
    IN extra_credits_required INT,
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
DECLARE
    entry_number VARCHAR(15);
    faculty_id INT;
    student RECORD;
BEGIN
    -- add ticket to student ticket table

    SELECT CURRENT_USER INTO entry_number;

    EXECUTE format ('INSERT INTO %I VALUES(%L, %L, %L, %L, %L);', 'student_ticket_table_' || entry_number, entry_number || '_' || semester || '_' || year, extra_credits_required, semester, year, 'Awaiting FA Approval');

    EXECUTE format ('SELECT l.faculty_id FROM student_database s, batchwise_FA_list l WHERE s.entry_number = %L and l.branch = s.branch and l.year = s.year and l.course = s.course', entry_number) INTO faculty_id;
    -- add ticket to FA's table
    FOR student IN
        EXECUTE format ('SELECT * FROM student_database WHERE entry_number = %L', entry_number)
    LOOP
        EXECUTE format ('SELECT faculty_id FROM batchwise_FA_list WHERE course = %L and branch = %L and year = %L', student.course, student.branch, student.year) INTO faculty_id;
    END LOOP;

    EXECUTE format ('INSERT INTO %I VALUES(%L, %L, %L, %L);', 'FA_ticket_table_' || faculty_id, entry_number || '_' || semester || '_' || year, entry_number, extra_credits_required, 'Awaiting Approval');
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_course_registration_trigger (
) RETURNS TRIGGER AS $$
DECLARE
    total_credits INT;
    maximum_credit_limit FLOAT;
    student_course RECORD;
    student_batch RECORD;
    batches RECORD;
    batch_exist INT;
    new_slots INT [];
    courses RECORD;
    current_user VARCHAR(15);
    courses_time_slot INT [];
    slot INT;
    new_slot INT;
    course_credits INT;
    new_course_credits INT;
    new_course_offering_id VARCHAR(255);
    prereq_not_done INT;
BEGIN
    SELECT CURRENT_USER INTO current_user;

    total_credits := 0;
    -- this loop will count total_credits
    FOR student_course IN
        EXECUTE format('SELECT * FROM %I', 'student_current_courses_' || current_user)
    LOOP
        SELECT credits 
        FROM course_catalog
        WHERE student_course.course_id = course_catalog.course_id INTO course_credits;
        total_credits := total_credits + credits;
    END LOOP;

    -- extracting maximum credit limit
    EXECUTE format (
        'SELECT maximum_credits_allowed FROM student_credit_info WHERE entry_number = %L',
        current_user
    ) INTO maximum_credit_limit;

    -- checking if the limit is satisfied
    EXECUTE format ('SELECT course_id FROM course_catalog WHERE course_id = %L', NEW.course_id) INTO new_course_credits;
    
    IF (total_credits + new_course_credits > maximum_credit_limit) THEN
        RAISE EXCEPTION 'You have exceeded the maximum credits limit.' USING ERRCODE = 'FATAL';
    END IF;

    -- checking the cg criteria
    EXECUTE format ('SELECT offering_id FROM course_offering WHERE course_id = %L', NEW.course_id) INTO new_course_offering_id;

    FOR student_batch IN
        EXECUTE format ('SELECT * FROM student_database WHERE entry_number = %L', current_user)
    LOOP
        FOR batches IN
            EXECUTE format ('SELECT * FROM %I', new_course_offering_id)
        LOOP
            IF batches.year = student_batch.year AND batches.course = student_batch.course AND batches.branch = student_batch.branch THEN
                IF batches.cg > student_batch.cgpa THEN
                    RAISE EXCEPTION 'You dont satisfy the cg criteria' USING ERRCODE = 'FATAL';
                END IF;
            END IF;
        END LOOP;

        -- if the batch doesn't exist
        EXECUTE format ('SELECT count(*) FROM %I WHERE year = %L AND course = %L AND branch = %L', new_course_offering_id, student_batch.year, student_batch.course, student_batch.branch) INTO batch_exist;
        IF (batch_exist = 0) THEN
            RAISE EXCEPTION 'Your batch is not allowed to register for this course' USING ERRCODE = 'FATAL';
        END IF;
    END LOOP;

    SELECT time_slot FROM course_offering WHERE course_id = NEW.course_id AND faculty_id = NEW.faculty_id AND semester = NEW.semester AND year = NEW.year INTO new_slots;

    FOR courses IN
        EXECUTE format('SELECT * FROM %I', 'student_current_courses_' || current_user)
    LOOP
        FOR courses_time_slot IN 
            SELECT time_slot FROM course_offering WHERE course_id = courses.course_id
        LOOP
            FOREACH slot IN ARRAY courses_time_slot
            LOOP
                FOREACH new_slot IN ARRAY new_slots
                LOOP
                    IF new_slot = slot THEN
                        RAISE EXCEPTION 'This course have time overlap with some other registered course' USING ERRCODE = 'FATAL';
                    END IF;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;

    -- checking prereq
    SELECT count(*) FROM (
        EXECUTE format (
            'SELECT course_id FROM %I
            EXCEPT
            SELECT course_id FROM %I', 
            new_course_offering_id || '_prereq', 'student_current_courses_' || current_user)
    ) INTO prereq_not_done;

    IF (prereq_not_done > 0) THEN
        RAISE EXCEPTION 'You havent done all the prerequisites of the course' USING ERRCODE = 'FATAL';
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_registration (
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN entry_number VARCHAR(15),
    IN course VARCHAR(100),
    IN branch VARCHAR(100),
    IN year INT,
    IN credits_completed FLOAT,
    IN cgpa FLOAT
) RETURNS VOID AS $$
BEGIN

    -- make a new user with student entry number
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', entry_number);

    -- add this in past semester credits table
    INSERT INTO student_credit_info VALUES (entry_number, NULL, NULL, NULL);

    INSERT INTO student_database VALUES (first_name, last_name, entry_number, course, branch, year, credits_completed, cgpa);

    -- make a table for past courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT NOT NULL,
            course_id VARCHAR(10) NOT NULL,
            year INT NOT NULL,
            semester INT NOT NULL,
            status VARCHAR(255) NOT NULL,
            grade INT NOT NULL
        );', 'student_past_courses_' || entry_number
    );

    -- make a table for current courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            faculty_id INT NOT NULL,
            course_id VARCHAR(10) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL
        );', 'student_current_courses_' || entry_number
    );

    -- make a table for ticket for this student
    -- ticket id = entry number_semester_year
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) NOT NULL,
            extra_credits_required FLOAT NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'student_ticket_table_' || entry_number
    );

    EXECUTE format (
        'CREATE TRIGGER %I
        BEFORE INSERT ON %I
        FOR EACH ROW
        EXECUTE PROCEDURE student_course_registration_trigger()
        END LOOP;   
        RETURN NULL;', 'student_course_registration_trigger_' || entry_number, 'student_current_courses_' || entry_number
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_registration (
    IN faculty_id INT,
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN department VARCHAR(100)
) RETURNS VOID AS $$
BEGIN
    -- make a new user with faculty id
    EXECUTE format ('CREATE USER %I WITH PASSWORD ''iitropar'';', faculty_id);

    INSERT INTO faculty_database VALUES (faculty_id, first_name, last_name, department);

    -- make a table for course offering of this faculty
    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(15) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            time_slots INT [] NOT NULL
        );', 'course_offering_' || faculty_id
    );

    -- make a table for FA
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) NOT NULL,
            entry_number VARCHAR(15) NOT NULL,
            extra_credits_required FLOAT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'FA_ticket_table_' || faculty_id
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_course_offering_table (
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT,
    IN time_slots INT []
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
    offering_id VARCHAR(255);
BEGIN
    -- add the course offering to common course offering table
    SELECT CURRENT_USER INTO faculty_id;
    SELECT faculty_id || '_' || course_id || '_' || semester || '_' || year INTO offering_id;

    INSERT INTO course_offering VALUES (offering_id, faculty_id, course_id, semester, year, time_slots);

    -- add into the course offering table of the faculty
    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        'course_offering_' || faculty_id, course_id, semester, year, time_slots
    );

    -- create a table for batchwise cg criteria
    EXECUTE format (
        'CREATE TABLE %I (
            course VARCHAR(255) NOT NULL,
            branch VARCHAR(255) NOT NULL,
            year INT NOT NULL,
            cg FLOAT NOT NULL
        );', offering_id
    );

    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(10) NOT NULL,
        );', offering_id || '_prereq'
    );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION batchwise_cg_criteria (
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT,
    IN course VARCHAR(100),
    IN branch VARCHAR(100),
    IN year_of_joining INT,
    IN cgpa FLOAT
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
BEGIN
    -- add into the course offering table of the faculty
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year, course, branch, year_of_joining, cgpa
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_course_registration (
    IN faculty_id INT,
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
DECLARE
    entry_number VARCHAR(15);
BEGIN
    -- add the course offering to common course offering table
    SELECT CURRENT_USER INTO entry_number;

    EXECUTE format (
        'INSERT INTO %I VALUES (%L, %L, %L, %L);',
        'student_current_courses_' || entry_number, faculty_id, course_id, semester, year
    );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION FA_acceptance (
    IN ticket_id varchar(100),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
DECLARE
    extra_credits_required FLOAT;
    faculty_id INT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Awaiting dean approval', ticket_id
    );

    -- update status in FAs ticket table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'FA_ticket_table_' || faculty_id, 'Approved', ticket_id
    );

    -- update status in student's ticket table
    EXECUTE format(
        'SELECT extra_credits_required
        FROM %I
        WHERE ticket_id = %L', 'student_ticket_table_' || entry_number, ticket_id
    ) INTO extra_credits_required;

    EXECUTE format (
        'INSERT INTO dean_ticket_table VALUES(%L, %L, %L, %L)', ticket_id, entry_number, extra_credits_required, 'Awaiting Approval'
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION FA_rejection (
    IN ticket_id varchar(100),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
DECLARE
    faculty_id INT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Rejected by FA', ticket_id
    );

    -- update status in FAs ticket table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'FA_ticket_table_' || faculty_id, 'Rejected', ticket_id
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dean_acceptance (
    IN ticket_id varchar(255),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
DECLARE
    extra_credits_required FLOAT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Approved', ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = %L
         WHERE ticket_id = %L;', 'Approved', ticket_id
    );

    EXECUTE format(
        'SELECT extra_credits_required
        FROM %I
        WHERE ticket_id = %L', 'student_ticket_table_' || entry_number, ticket_id
    ) INTO extra_credits_required;
    -- update max credit limit for the student
    EXECUTE format (
        'UPDATE student_credit_info
         SET maximum_credits = maximum_credits + %L
         WHERE entry_number = %L;', extra_credits_required, entry_number
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dean_rejection (
    IN ticket_id varchar(255),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = %L
         WHERE ticket_id = %L;', 'student_ticket_table_' || entry_number, 'Rejected by dean', ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = %L
         WHERE ticket_id = %L;', 'Rejected', ticket_id
    );
END
$$ LANGUAGE plpgsql;