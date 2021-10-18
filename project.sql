CREATE DATABASE AIMS;CREATE TABLE course_catalog (
    course_id INT UNIQUE PRIMARY KEY,
    LTPSC INT [] NOT NULL,
    course_name VARCHAR(255) NOT NULL,
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
    year INT NOT NULL,
);

CREATE TABLE student_past_semester_credits (
    student_id INT NOT NULL,
    last_semester INT,
    second_last_semester INT,
);

CREATE TABLE batchwise_cg (
    course VARCHAR(255) NOT NULL,
    branch VARCHAR(255) NOT NULL,
    year INT NOT NULL,
    cg INT, 
); -- will contail cg criteria of each course and name of the table will change according to course

