CREATE USER dean_acads WITH PASSWORD "iitropar";
CREATE USER acads_office WITH PASSWORD "iitropar";

CREATE DATABASE AIMS;

CREATE TABLE course_catalog (
    course_id INT UNIQUE PRIMARY KEY,
    LTPSC INT [] NOT NULL,
    course_name VARCHAR(255) NOT NULL
);

CREATE TABLE course_prereq (
    course_id INT NOT NULL,
    prereq_id INT NOT NULL,
    PRIMARY KEY (course_id, prereq_id),
    FOREIGN KEY (course_id) REFERENCES course_catalog(course_id),
    FOREIGN KEY (prereq_id) REFERENCES course_catalog(course_id)
); -- course_id is the course that has prereqs, prereq_id is the prereq

CREATE TABLE course_offering (
    faculty_id INT NOT NULL,
    course_id INT NOT NULL,
    semester INT NOT NULL,
    year INT NOT NULL
);

CREATE TABLE student_past_semester_credits (
    entry_number VARCHAR(15) NOT NULL,
    last_semester INT,
    second_last_semester INT
);

GRANT SELECT, UPDATE, INSERT, DELETE ON course_catalog TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_catalog TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON course_prereq TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_prereq TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON course_offering TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON course_offering TO acads_office;

GRANT SELECT, UPDATE, INSERT, DELETE ON student_past_semester_credits TO dean_acads;
GRANT SELECT, UPDATE, INSERT, DELETE ON student_past_semester_credits TO acads_office;

CREATE OR REPLACE FUNCTION student_registration (
    IN entry_number VARCHAR(15)
) RETURNS VOID AS $$
BEGIN

    -- make a new user with student entry number
    EXECUTE format ('CREATE USER %I WITH PASSWORD "iitropar";', entry_number);

    -- add this in past semester credits table
    INSERT INTO student_past_semester_credits VALUES (entry_number, NULL, NULL);

    -- make a table for past cources of this student
    EXECUTE format (
        'CREATE TABLE %I (
            course_id INT NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'student_past_courses_' || entry_number
    );

    -- make a table for current courses of this student
    EXECUTE format (
        'CREATE TABLE %I (
            course_id INT NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL
        );', 'student_current_courses_' || entry_number
    );
    
    -- make a table for ticket for this student
    EXECUTE format (
        'CREATE TABLE %I (
            ticket_id VARCHAR(255) NOT NULL,
            course_id VARCHAR(255) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL,
            status VARCHAR(255) NOT NULL
        );', 'student_ticket_table_' || entry_number
    );

    EXECUTE format (
        'GRANT SELECT ON %I TO %I', 
        'student_past_courses_' || entry_number, entry_number
    );

    EXECUTE format (
        'GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO %I', 
        'student_current_courses_' || entry_number, entry_number
    );

    EXECUTE format (
        'GRANT SELECT, INSERT ON %I TO %I', 
        'student_ticket_table_' || entry_number, entry_number
    );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_registration (
    IN faculty_id INT
) RETURNS VOID AS $$
BEGIN

    -- make a new user with faculty id
    EXECUTE format ('CREATE USER %I WITH PASSWORD "iitropar";', faculty_id);

    -- make a table for course offering of this faculty
    EXECUTE format (
        'CREATE TABLE %I (
            course_id VARCHAR(15) NOT NULL,
            semester INT NOT NULL,
            year INT NOT NULL
        );', 'course_offering_' || faculty_id
    );

    EXECUTE format (
        'GRANT SELECT, UPDATE, INSERT, DELETE ON %I TO %I', 
        'course_offering_' || faculty_id, faculty_id
    );

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION faculty_course_offering_table (
    IN faculty_id VARCHAR(15),
    IN course_id VARCHAR(15),
    IN semester INT,
    IN year INT
) RETURNS VOID AS $$
BEGIN
    -- add the course offering to common course offering table
    INSERT INTO course_offering VALUES (faculty_id, course_id, semester, year);

    -- add into the course offering table of the faculty
    EXECUTE format (
        'INSERT INTO %I VALUES (course_id, semester, year);',
        'course_offering' || '_' || faculty_id
    );

    -- create a table for batchwise cg criteria
    EXECUTE format (
        'CREATE TABLE %I (
            course VARCHAR(255) NOT NULL,
            branch VARCHAR(255) NOT NULL,
            year INT NOT NULL,
            cg INT
        );', faculty_id || '_' || course_id || '_' || semester || '_' || year
    );

    EXECUTE format (
        'GRANT SELECT, UPDATE, INSERT, DELETE ON %I TO %I', 
        faculty_id || '_' || course_id || '_' || semester || '_' || year, faculty_id
    );

END
$$ LANGUAGE plpgsql;


