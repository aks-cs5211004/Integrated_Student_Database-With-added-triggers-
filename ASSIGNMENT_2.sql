
--create tables

CREATE TABLE department (
    dept_id CHAR(3) PRIMARY KEY,
    dept_name VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE student (
    first_name VARCHAR(40) NOT NULL,
    last_name VARCHAR(40),
    student_id CHAR(11) PRIMARY KEY NOT NULL,
    address VARCHAR(100),
    contact_number CHAR(10) NOT NULL UNIQUE ,
    email_id VARCHAR(50),
    tot_credits NUMERIC NOT NULL CHECK(tot_credits>=0),
    dept_id CHAR(3) REFERENCES department(dept_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE courses (
    course_id CHAR(6) PRIMARY KEY NOT NULL,
    course_name VARCHAR(20) NOT NULL UNIQUE,
    course_desc TEXT,
    credits NUMERIC NOT NULL check(credits>=0),
    dept_id CHAR(3) REFERENCES department(dept_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE professor (
    professor_id VARCHAR(10) PRIMARY KEY,
    professor_first_name varchar(40) NOT NULL,
    professor_last_name varchar(40) NOT NULL,
    office_number varchar(20),
    contact_number char(10) NOT NULL,
    start_year INTEGER ,
    resign_year integer check(start_year<=resign_year),
    dept_id char(3) references department(dept_id) ON UPDATE CASCADE ON DELETE CASCADE
    
);


CREATE TABLE course_offers (
    course_id CHAR(6) REFERENCES courses(course_id) ON UPDATE CASCADE ON DELETE CASCADE,
    session VARCHAR(9) ,
    semester INTEGER NOT NULL 
    CHECK (semester IN (1, 2)) ,
    professor_id VARCHAR(10) REFERENCES professor(professor_id) ON UPDATE CASCADE ON DELETE CASCADE,
    capacity integer,
    enrollments integer,
    PRIMARY KEY (course_id, session, semester)
);


CREATE TABLE student_courses (
    student_id CHAR(11) REFERENCES student(student_id) ON UPDATE CASCADE ON DELETE CASCADE,
    course_id CHAR(6) ,
    session VARCHAR(9),
    semester INTEGER 
    CHECK (semester IN (1, 2)),
    grade NUMERIC NOT NULL CHECK (grade >= 0 AND grade <= 10),
    FOREIGN KEY (course_id, session, semester) 
        REFERENCES course_offers (course_id, session, semester) ON DELETE CASCADE ON UPDATE CASCADE
);



CREATE TABLE valid_entry (
    dept_id char(3) REFERENCES department(dept_id) ON UPDATE CASCADE ON DELETE CASCADE,
    entry_year integer NOT NULL,
    seq_number integer NOT NULL
);



--creat depc table

CREATE TABLE student_dept_change (
    old_student_id CHAR(11),
    old_dept_id char(3) ,
    new_dept_id char(3),
    new_student_id CHAR(11)
);





--1.6

CREATE OR REPLACE FUNCTION check_course_id_format()
RETURNS TRIGGER 
AS $$
BEGIN
    IF NEW.course_id !~ '[A-Z0-9][A-Z0-9][A-Z0-9][0-9][0-9][0-9]' OR  LEFT(NEW.course_id, 3) <> NEW.dept_id
    THEN
        RAISE EXCEPTION 'Invalid course_id format';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER courses_check_course_id
BEFORE INSERT OR UPDATE ON courses
FOR EACH ROW
EXECUTE procedure check_course_id_format();






--2.1.1


CREATE OR REPLACE FUNCTION t_2_1()
RETURNS TRIGGER 
AS $$
DECLARE
    v_entry_year INTEGER;
    v_dept_id CHAR(3);
    v_seq_number INTEGER;
BEGIN
    v_entry_year := CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER);
    v_dept_id := SUBSTRING(NEW.student_id FROM 5 FOR 3);
    v_seq_number := CAST(SUBSTRING(NEW.student_id FROM 8 FOR 3) AS INTEGER);
    
    IF NOT EXISTS (
        SELECT *
        FROM valid_entry
        WHERE dept_id = v_dept_id AND entry_year = v_entry_year AND seq_number=v_seq_number
    ) THEN
        RAISE EXCEPTION 'invalid';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER validate_student_id
BEFORE INSERT ON student
FOR EACH ROW
EXECUTE FUNCTION t_2_1();




--2.1.2

CREATE OR REPLACE FUNCTION t_2_2()
RETURNS TRIGGER 
AS $$
DECLARE
    v_entry_year INTEGER;
    v_dept_id CHAR(3);
    v_seq_number INTEGER;
BEGIN
    v_entry_year := CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER);
    v_dept_id := SUBSTRING(NEW.student_id FROM 5 FOR 3);
    v_seq_number := CAST(SUBSTRING(NEW.student_id FROM 8 FOR 3) AS INTEGER);
    
    UPDATE valid_entry
    SET seq_number = seq_number + 1
    WHERE dept_id = v_dept_id AND entry_year = v_entry_year;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE  OR REPLACE TRIGGER update_seq_number
AFTER INSERT ON student
FOR EACH ROW 
EXECUTE FUNCTION t_2_2();









--2.1.3

CREATE OR REPLACE FUNCTION t_2_3()
RETURNS TRIGGER AS $$
BEGIN
    DECLARE
        v_entry_year CHAR(4);
        v_dept_id CHAR(3);
        v_seq_number CHAR(3);
        v_dept_id_col CHAR(3);
        v_dept_id_email CHAR(3);
    BEGIN
        v_entry_year := SUBSTRING(NEW.student_id FROM 1 FOR 4);
        v_dept_id := SUBSTRING(NEW.student_id FROM 5 FOR 3);
        v_seq_number := SUBSTRING(NEW.student_id FROM 8 FOR 3);
        v_dept_id_col:= NEW.dept_id;
        v_dept_id_email := SUBSTRING(NEW.email_id FROM 5 FOR 3);
        
        IF NEW.email_id = CONCAT(v_entry_year, v_dept_id, v_seq_number , '@', v_dept_id, '.iitd.ac.in')
        AND v_dept_id_email = v_dept_id_col
        THEN 
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'invalid';
        END IF;
    END;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER validate_student_email
BEFORE INSERT ON student
FOR EACH ROW
EXECUTE FUNCTION t_2_3();





--2.1.4
CREATE OR REPLACE FUNCTION t_2_4()
RETURNS TRIGGER AS $$
DECLARE
    v_old_dept_id CHAR(3);
    v_new_dept_id CHAR(3);
    v_entry_year INTEGER;
    v_seq_number INTEGER;


    
BEGIN
    v_old_dept_id := (SELECT dept_id FROM student WHERE student_id = NEW.student_id);
    v_new_dept_id := NEW.dept_id;
    v_entry_year := CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER);
    
    
    IF (NEW.dept_id <> OLD.dept_id 
    AND EXISTS (select * from department where dept_id= NEW.dept_id)
    AND EXISTS (select * from department where dept_id= OLD.dept_id))
    THEN
        IF EXISTS (
            SELECT *
            FROM student_dept_change
            WHERE new_student_id = NEW.student_id
        ) THEN
            RAISE EXCEPTION 'Department can be changed only once';
        END IF;


        IF CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER) < 2022 THEN
            RAISE EXCEPTION 'Entry year must be >= 2022';
        END IF;

        IF (SELECT AVG(grade) FROM student_courses WHERE student_id = NEW.student_id group by student_id) <= 8.5 THEN
            RAISE EXCEPTION 'Low Grade';
        END IF;
        
        select seq_number into v_seq_number from valid_entry
        where entry_year= v_entry_year and dept_id= v_new_dept_id;
        
        
        NEW.student_id := (v_entry_year)::TEXT || v_new_dept_id || LPAD((v_seq_number)::TEXT, 3, '0');
        NEW.email_id := NEW.student_id || '@' || NEW.dept_id || '.iitd.ac.in';
    
    
    END IF;
    RETURN NEW;
    
    
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER log_student_dept_change
BEFORE UPDATE ON student
FOR EACH ROW
EXECUTE FUNCTION t_2_4();




--2.1.4 second trigger

CREATE OR REPLACE FUNCTION insert_into_student_dept_change()
RETURNS TRIGGER AS $$

DECLARE
    v_entry_year INTEGER;
    v_dept_id CHAR(3);
    v_seq_number INTEGER;
BEGIN
    IF (NEW.dept_id <> OLD.dept_id 
    AND EXISTS (select * from department where dept_id= NEW.dept_id)
    AND EXISTS (select * from department where dept_id= OLD.dept_id)) THEN
    
    v_entry_year := CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER);
    v_dept_id := SUBSTRING(NEW.student_id FROM 5 FOR 3);
    v_seq_number := CAST(SUBSTRING(NEW.student_id FROM 8 FOR 3) AS INTEGER);
    
    UPDATE valid_entry
    SET seq_number = seq_number + 1
    WHERE dept_id = v_dept_id AND entry_year = v_entry_year;
    
    INSERT INTO student_dept_change
    VALUES (OLD.student_id, OLD.dept_id, NEW.dept_id, NEW.student_id);
    
    
    UPDATE student_courses
    SET student_id = NEW.student_id
    WHERE student_id = OLD.student_id;
    
    END IF;
    RETURN NULL;
 
 END;   
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER insert_student_dept_change
AFTER UPDATE ON student
FOR EACH ROW
EXECUTE FUNCTION insert_into_student_dept_change();





--2.2.1
CREATE OR REPLACE VIEW course_eval AS
SELECT
    sc.course_id,
    sc.session,
    sc.semester,
    COUNT(sc.student_id) AS number_of_students,
    AVG(sc.grade) AS average_grade,
    MAX(sc.grade) AS max_grade,
    MIN(sc.grade) AS min_grade
FROM
    student_courses sc
GROUP BY
    sc.course_id, sc.session, sc.semester;





--2.2.2

CREATE OR REPLACE FUNCTION update_student_tot_credits()
RETURNS TRIGGER AS $$
DECLARE
    v_course_credits NUMERIC;
BEGIN
IF TG_OP ='INSERT' THEN
    SELECT credits INTO v_course_credits
    FROM courses
    WHERE course_id = NEW.course_id;

    UPDATE student
    SET tot_credits = tot_credits+ v_course_credits
    WHERE student_id = NEW.student_id;
    RETURN NEW;
END IF;
IF TG_OP='DELETE' THEN
    SELECT credits INTO v_course_credits
    FROM courses
    WHERE course_id = OLD.course_id;

    UPDATE student
    SET tot_credits = tot_credits- v_course_credits
    WHERE student_id = OLD.student_id;
    RETURN OLD;
END IF;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER update_student_tot_credits_trigger
AFTER INSERT OR DELETE ON student_courses
FOR EACH ROW
EXECUTE FUNCTION update_student_tot_credits();





--2.2.3

CREATE OR REPLACE FUNCTION check_enrollment_constraints()
RETURNS TRIGGER AS $$
DECLARE
    no_of_courses INTEGER;
    total_credits_0 INTEGER;
    new_course_credit NUMERIC;
    v_max_courses NUMERIC := 5;
    v_max_credits NUMERIC := 60;
    sem_credits NUMERIC ;
BEGIN

    SELECT COUNT(*) INTO no_of_courses
    FROM student_courses
    WHERE student_id = NEW.student_id AND session = NEW.session AND semester = NEW.semester;
    
    SELECT tot_credits INTO total_credits_0
    FROM student
    WHERE student_id = NEW.student_id;
    
    SELECT credits INTO new_course_credit
    FROM courses
    WHERE course_id = NEW.course_id;
    
    SELECT sum(credits) into sem_credits from
    student_courses join courses using (course_id)
    WHERE student_id = NEW.student_id AND session = NEW.session AND semester = NEW.semester
    group by student_id, session, semester ;
    

    IF no_of_courses + 1 > v_max_courses OR (total_credits_0 + new_course_credit) > v_max_credits OR sem_credits + 
    new_course_credit> 26 THEN
        RAISE EXCEPTION 'invalid';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER check_enrollment_constraints_trigger
BEFORE INSERT ON  student_courses
FOR EACH ROW
EXECUTE FUNCTION check_enrollment_constraints();







--2.2.4

CREATE OR REPLACE FUNCTION check_credit_and_first_year()
RETURNS TRIGGER AS $$
DECLARE
    v_student_entry_year INTEGER;
    v_course_credits NUMERIC;
BEGIN

    v_student_entry_year := CAST(SUBSTRING(NEW.student_id FROM 1 FOR 4) AS INTEGER);

    SELECT credits INTO v_course_credits
    FROM courses
    WHERE course_id = NEW.course_id;

    IF v_course_credits = 5 AND (v_student_entry_year) != CAST(SUBSTRING(NEW.session FROM 1 FOR 4) AS INTEGER) THEN
        RAISE EXCEPTION 'invalid';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER check_credit_and_first_year_trigger
BEFORE INSERT ON student_courses
FOR EACH ROW
EXECUTE FUNCTION check_credit_and_first_year();





--2.2.5 View
CREATE  MATERIALIZED VIEW student_semester_summary AS
SELECT
    sc.student_id,
    sc.session,
    sc.semester,
    CASE
        WHEN COALESCE(SUM(CASE WHEN sc.grade >= 5.0 THEN c.credits ELSE 0 END), 0) = 0 THEN NULL
        ELSE SUM(CASE WHEN sc.grade >= 5.0 THEN sc.grade * c.credits ELSE 0 END)
             / NULLIF(SUM(CASE WHEN sc.grade >= 5.0 THEN c.credits ELSE 0 END), 0)
    END AS sgpa,
    SUM(CASE WHEN sc.grade >= 5.0 THEN c.credits ELSE 0 END) AS credits
FROM
    student_courses sc
JOIN
    courses c ON sc.course_id = c.course_id
GROUP BY
    sc.student_id, sc.session, sc.semester;







--2.2.5 Trig
CREATE OR REPLACE FUNCTION update_student_semester_summary()
RETURNS TRIGGER AS $$
DECLARE
    semester_credits NUMERIC;
BEGIN
    IF TG_OP = 'INSERT' THEN
        REFRESH MATERIALIZED VIEW student_semester_summary;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        REFRESH MATERIALIZED VIEW student_semester_summary;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        REFRESH MATERIALIZED VIEW student_semester_summary;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE OR REPLACE TRIGGER update_semester_summary
AFTER INSERT OR UPDATE OR DELETE ON student_courses
FOR EACH ROW
EXECUTE FUNCTION update_student_semester_summary();





--2.2.6
CREATE OR REPLACE FUNCTION check_course_capacity_and_update_enrollments()
RETURNS TRIGGER AS $$
BEGIN
IF TG_OP ='INSERT' THEN
    IF (SELECT enrollments +1 > capacity FROM course_offers
        WHERE course_id = NEW.course_id AND session = NEW.session AND semester = NEW.semester) THEN
        RAISE EXCEPTION 'course is full';
    END IF;

    UPDATE course_offers
    SET enrollments = enrollments + 1
    WHERE course_id = NEW.course_id AND session = NEW.session AND semester = NEW.semester;
    RETURN NEW;
END IF;
IF TG_OP ='DELETE' THEN
    UPDATE course_offers
    SET enrollments = enrollments - 1
    WHERE course_id = OLD.course_id AND session = OLD.session AND semester = OLD.semester;
    RETURN OLD;
END IF;

END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER check_course_capacity_and_update_enrollments_trigger
BEFORE INSERT OR DELETE ON student_courses
FOR EACH ROW
EXECUTE FUNCTION check_course_capacity_and_update_enrollments();





--2.3.1

CREATE OR REPLACE FUNCTION remove_students_for_removed_course()
RETURNS TRIGGER AS $$
DECLARE

    course_credits NUMERIC;

BEGIN
    SELECT credits INTO course_credits
    FROM courses
    WHERE course_id = OLD.course_id;

    UPDATE student
    SET tot_credits = tot_credits - course_credits
    WHERE student_id IN (
        SELECT student_id
        FROM student_courses
        WHERE course_id = OLD.course_id
            AND session = OLD.session
            AND semester = OLD.semester);

    DELETE FROM student_courses
    WHERE course_id = OLD.course_id
        AND session = OLD.session
        AND semester = OLD.semester;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER remove_students_for_removed_course_trigger
AFTER DELETE ON course_offers
FOR EACH ROW
EXECUTE FUNCTION remove_students_for_removed_course();



--2.3.1 second trig

CREATE OR REPLACE FUNCTION f_2_3_1()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM courses WHERE course_id = NEW.course_id) THEN
        RAISE EXCEPTION 'Invalid course_id: Course does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM professor WHERE professor_id = NEW.professor_id) THEN
        RAISE EXCEPTION 'Invalid professor_id: Professor does not exist';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER t_2_3_1
BEFORE INSERT ON course_offers
FOR EACH ROW
EXECUTE FUNCTION f_2_3_1();





--2.3.2

CREATE OR REPLACE FUNCTION check_professor_course_limit_and_resignation()
RETURNS TRIGGER AS $$
BEGIN

    IF (SELECT COUNT(*) FROM course_offers WHERE professor_id = NEW.professor_id AND session = NEW.session) >= 4 THEN
        RAISE EXCEPTION 'invalid';
    END IF;


    IF CAST(SUBSTRING(NEW.session FROM 6 FOR 4) AS INTEGER) > (SELECT resign_year FROM professor WHERE professor_id = NEW.professor_id) THEN
        RAISE EXCEPTION 'Invalid: Course offered after the professor resigned';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER check_professor_course_limit_and_resignation_trigger
BEFORE INSERT ON course_offers
FOR EACH ROW
EXECUTE FUNCTION check_professor_course_limit_and_resignation();





--2.4
CREATE OR REPLACE FUNCTION update_delete_department_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.dept_id <> OLD.dept_id THEN

            UPDATE student
            SET 
                student_id = LEFT(student_id,4) || NEW.dept_id || RIGHT(student_id, 3),  
                email_id   = LEFT(student_id,4) || NEW.dept_id || RIGHT(student_id, 3) || '@' || NEW.dept_id || '.iitd.ac.in'
            WHERE dept_id = OLD.dept_id;
            
            DROP TRIGGER courses_check_course_id on courses;
            
            UPDATE courses
            SET course_id = NEW.dept_id || RIGHT(course_id, 3)
            WHERE LEFT(course_id, 3) = OLD.dept_id;
            
            CREATE OR REPLACE TRIGGER courses_check_course_id
            BEFORE INSERT OR UPDATE ON courses
            FOR EACH ROW
            EXECUTE procedure check_course_id_format();
            
            RETURN NEW;    
        END IF;
    END IF;
    
    IF TG_OP = 'DELETE' THEN

        IF EXISTS (SELECT 1 FROM student WHERE dept_id = OLD.dept_id) THEN
            RAISE EXCEPTION 'Department has students';
        ELSE
            DELETE FROM course_offers WHERE LEFT(course_id, 3) = OLD.dept_id;
        END IF;

        RETURN OLD;

    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER update_delete_department_trigger
BEFORE UPDATE OR DELETE ON department
FOR EACH ROW
EXECUTE FUNCTION update_delete_department_trigger_func();





