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

CREATE TABLE course_prereq (
    course_id VARCHAR(10) NOT NULL,
    prereq_id VARCHAR(10) NOT NULL,
    PRIMARY KEY (course_id, prereq_id),
    FOREIGN KEY (course_id) REFERENCES course_catalog(course_id),
    FOREIGN KEY (prereq_id) REFERENCES course_catalog(course_id)
); -- course_id is the course that has prereqs, prereq_id is the prereq

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

CREATE OR REPLACE FUNCTION student_ticket_generator (
    IN entry_number VARCHAR(15),
    IN extra_credits_required INT,
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
DECLARE
    faculty_id INT,
BEGIN
    -- add ticket to student ticket table
    EXECUTE format (
        'INSERT INTO %I VALUES(%I, %I, %I, %I, Awaiting FA Approval);', 'student_ticket_table_' || entry_number, entry_number || '_' || semester || '_' || year, extra_credits_required, semester, year
    );

    SELECT l.faculty_id FROM student_database s, batchwise_FA_list l WHERE s.entry_number = entry_number and l.branch = s.branch and l.year = s.year and l.course = s.course INTO faculty_id;

    -- add ticket to FA's table
    EXECUTE format(
        'INSERT INTO %I VALUES(%I, %I, %I, Awaiting Approval);', 'FA_ticket_table_' || faculty_id, entry_number || '_' || semester || '_' || year, entry_number, extra_credits_required
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION student_course_registration_trigger (
) RETURNS TRIGGER AS $$
DECLARE
    total_credits INT;
    maximum_credit_limit FLOAT;
    past_credits RECORD;
    current_user VARCHAR(15);
BEGIN
    SELECT CURRENT_USER INTO current_user;

    EXECUTE format (
        'total_credits := 0

        FOR student_course IN SELECT * FROM  student_current_courses_%I
        LOOP
            total_credits := total_credits + student_course.credits
        END LOOP

        SELECT maximum_credits_allowed INTO maximum_credit_limit FROM student_credit_info WHERE entry_number = %I;

        IF ((total_credits + NEW.credits) > maximum_credit_limit) THEN
            RAISE EXCEPTION ''You have exceeded the maximum credits limit.'' USING ERRCODE = ''FATAL''
        END IF

        FOR student_batch IN SELECT * FROM student_database WHERE entry_number = %I;
        LOOP
            FOR batches IN SELECT * FROM %I
            LOOP
                IF batches.year = student_batch.year AND batches.course = student_batch.course AND batches.branch = student_batch.branch THEN
                    IF batches.cg > student_batch.cg THEN
                        RAISE EXCEPTION ''You dont satisfy the cg criteria'' USING ERRCODE = ''FATAL''
                    END IF

                END IF

            END LOOP

            IF (SELECT * FROM %I WHERE year = student_batch.year AND course = student_batch.course AND branch = student_batch.branch = NULL) THEN
                RAISE EXCEPTION ''Your batch is not allowed to register for this course'' USING ERRCODE = ''FATAL''
            END IF

        END LOOP

        SELECT time_slots FROM course_offering WHERE course_id = NEW.course_id AND faculty_id = NEW.faculty_id AND semester = NEW.semester AND year = NEW.year INTO new_slots;

        FOR courses IN SELECT * FROM %I
        LOOP
            FOR courses_time_slot IN SELECT time_slot FROM course_offering WHERE course_id = courses.course_id
            LOOP
                FOREACH slot IN ARRAY courses_time_slot
                LOOP
                    FOREACH new_slot IN ARRAY new_slots
                    LOOP
                        IF new_slot = slot THEN
                            RAISE EXCEPTION ''This course have time overlap with some other registered course'' USING ERRCODE = ''FATAL''
                        END IF

                    END LOOP

                END LOOP

            END LOOP

        END LOOP', current_user, current_user, current_user, NEW.faculty_id || '_' || NEW.course_id || '_' || NEW.semester || '_' || NEW.year, NEW.faculty_id || '_' || NEW.course_id || '_' || NEW.semester || '_' || NEW.year, 'student_current_courses_' || current_user
    );
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
    INSERT INTO student_credit_info VALUES (entry_number, NULL, NULL);

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
        'CREATE TRIGGER student_course_registration_trigger_%I
        BEFORE INSERT ON student_current_courses_%I
        FOR EACH ROW
        EXECUTE PROCEDURE student_course_registration_trigger()', entry_number, entry_number
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_registration (
    IN faculty_id INT,
    IN first_name VARCHAR(100),
    IN last_name VARCHAR(100),
    IN department VARCHAR(100),
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
BEGIN
    -- add the course offering to common course offering table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'INSERT INTO course_offering VALUES (%I, faculty_id, course_id, semester, year, time_slots);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year
    );

    -- add into the course offering table of the faculty
    EXECUTE format (
        'INSERT INTO %I VALUES (course_id, semester, year, time_slots);',
        'course_offering_' || faculty_id
    );

    -- create a table for batchwise cg criteria
    EXECUTE format (
        'CREATE TABLE %I (
            course VARCHAR(255) NOT NULL,
            branch VARCHAR(255) NOT NULL,
            year INT NOT NULL,
            cg FLOAT NOT NULL
        );', faculty_id || '_' || course_id || '_' || semester || '_' || year
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
        'INSERT INTO %I VALUES (course, branch, year_of_joining, cgpa);',
        faculty_id || '_' || course_id || '_' || semester || '_' || year
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
    SELECT CURRENT_USER AS entry_number;

    EXECUTE format (
        'INSERT INTO %I VALUES (faculty_id, course_id, semester, year);',
        'student_current_courses_' || entry_number        
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
         SET status = "Awaiting dean approval"
         WHERE ticket_id = %I;', 'student_ticket_table_' || entry_number, ticket_id
    );

    -- update status in FAs ticket table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = "Approved"
         WHERE ticket_id = %I;', 'FA_ticket_table_' || faculty_id, ticket_id
    );

    -- update status in dean's ticket table
    EXECUTE format(
        'SELECT stt.extra_credits_required
        FROM %I stt
        WHERE stt.ticket_id = ticket_id INTO extra_credits_required;
        INSERT INTO dean_ticket_table VALUES(%I, %I, %I, "Awaiting Approval");', 'student_ticket_table_' || entry_number, ticket_id, entry_number, extra_credits_required
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
         SET status = "Rejected by FA"
         WHERE ticket_id = %I;', 'student_ticket_table_' || entry_number, ticket_id
    );

    -- update status in FAs ticket table
    SELECT CURRENT_USER INTO faculty_id;
    EXECUTE format (
        'UPDATE %I 
         SET status = "Rejected"
         WHERE ticket_id = %I;', 'FA_ticket_table_' || faculty_id, ticket_id
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dean_acceptance (
    IN ticket_id varchar(100),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = "Approved"
         WHERE ticket_id = %I;', 'student_ticket_table_' || entry_number, ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = "Approved"
         WHERE ticket_id = %I;', ticket_id
    );

    -- update max credit limit for the student

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dean_acceptance (
    IN ticket_id varchar(100),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
DECLARE
    extra_credits_required FLOAT;
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = "Approved"
         WHERE ticket_id = %I;', 'student_ticket_table_' || entry_number, ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = "Approved"
         WHERE ticket_id = %I;', ticket_id
    );

    EXECUTE format(
        'SELECT stt.extra_credits_required
        FROM %I stt
        WHERE stt.ticket_id = ticket_id INTO extra_credits_required',
        'student_ticket_table_' || entry_number
    )
    -- update max credit limit for the student
    EXECUTE format (
        'UPDATE student_credit_info
         SET maximum_credits = maximum_credits + extra_credits_required
         WHERE entry_number = %I;', entry_number
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION dean_rejection (
    IN ticket_id varchar(100),
    IN entry_number varchar(15)
) RETURNS VOID AS $$
BEGIN
    -- update status in student ticket table
    EXECUTE format (
        'UPDATE %I 
         SET status = "Rejected by dean"
         WHERE ticket_id = %I;', 'student_ticket_table_' || entry_number, ticket_id
    );

    -- update status in dean's table
    EXECUTE format (
        'UPDATE dean_ticket_table
         SET status = "Rejected"
         WHERE ticket_id = %I;', ticket_id
    );
END
$$ LANGUAGE plpgsql;