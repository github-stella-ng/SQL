-- Unit Code	COMP2350	
-- Assignment#	3
-- Student ID	46293396	
-- Student Name	Thi Ngoc Trinh Nguyen
-- Tutor’s Name	Rohitranjan Vasantkumar (Rohit) Gupta	
-- Workshop Date / Time	Thursday, 1:00 – 3:00

-- ----------------------------------------------------------------------------
-- TASK 1: Update and Manage the Member table
-- ----------------------------------------------------------------------------

-- check the data first
Select * from member;

-- then update the fee column for Member table
ALTER TABLE Member ADD FineFees DECIMAL(10, 2) DEFAULT 0.00;

-- check the data again
Select * from member;

-- Calculate and update the fine fees for overdue books
UPDATE Member m
JOIN (
    SELECT bb.MemberID, COUNT(*) * 2 AS DailyFine
    FROM Borrowedby bb
    WHERE bb.DateReturned IS NULL AND bb.ReturnDueDate < CURDATE() 
    GROUP BY bb.MemberID
) AS OverdueFees ON m.MemberID = OverdueFees.MemberID
SET m.FineFees = m.FineFees + OverdueFees.DailyFine;

-- Suspend members whose fine fees have reached or exceeded $30
UPDATE Member 
SET MemberStatus = 'SUSPENDED'
WHERE FineFees >= 30 AND MemberStatus = 'REGULAR';

-- check the data again you will see the fee column updated
Select * from member;


-- ----------------------------------------------------------------------------
-- TASK 2: Implement Trigger for BR8
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS BR8_Trigger;

-- create the trigger 
DELIMITER //
CREATE TRIGGER BR8_Trigger
BEFORE UPDATE ON Member
FOR EACH ROW 
BEGIN
    DECLARE hasOverdue INT DEFAULT 0;

    -- Error Handler
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error updating Member Status.';
    END;

    -- Check for overdue items
    SELECT COUNT(*) 
    INTO hasOverdue
    FROM Borrowedby
    WHERE MemberID = NEW.MemberID AND DateReturned IS NULL AND ReturnDueDate < CURDATE();

    -- Implementing BR8
    IF NEW.FineFees = 0.00 AND hasOverdue = 0 THEN
        SET NEW.MemberStatus = 'REGULAR';
    ELSEIF NEW.FineFees = 0.00 AND hasOverdue > 0 THEN
        SET NEW.MemberStatus = 'SUSPENDED';
    END IF;
    
END //
DELIMITER ;

-- ----------------------------------------------------------------------------
-- TASK 3: Procedure to handle repeat offenders
-- ----------------------------------------------------------------------------

-- history table to track member status since we need to track who have been suspended twice a year
DROP TABLE IF EXISTS MemberHistory;
CREATE TABLE MemberHistory (
  HistoryID INT NOT NULL AUTO_INCREMENT,
  MemberID INT NOT NULL,
  OldStatus VARCHAR(255) NOT NULL,
  NewStatus VARCHAR(255) NOT NULL,
  ChangeDate DATE NOT NULL,
  PRIMARY KEY (HistoryID),
  CONSTRAINT member_fk_3 FOREIGN KEY (MemberID) REFERENCES Member (MemberID) ON DELETE CASCADE
);

-- procedure to terminate member
DROP PROCEDURE IF EXISTS TerminateOverdueMembers;

DELIMITER //

CREATE PROCEDURE TerminateOverdueMembers()
BEGIN
    DECLARE currentDate DATE;
    SET currentDate = CURDATE();

    -- Drop temporary tables if they exist
    DROP TEMPORARY TABLE IF EXISTS TempOverdueMembers;
    DROP TEMPORARY TABLE IF EXISTS TempSuspendedMembers;

    -- Find members who have overdue items
    CREATE TEMPORARY TABLE TempOverdueMembers AS
    SELECT DISTINCT MemberID 
    FROM Borrowedby 
    WHERE DateReturned IS NULL 
    AND currentDate > ReturnDueDate;

    -- Find members who were suspended twice or more in the last three years using MemberHistory
    CREATE TEMPORARY TABLE TempSuspendedMembers AS
    SELECT MemberID
    FROM MemberHistory
    WHERE NewStatus = 'SUSPENDED' 
    AND ChangeDate BETWEEN DATE_SUB(currentDate, INTERVAL 3 YEAR) AND currentDate
    GROUP BY MemberID
    HAVING COUNT(MemberID) >= 2;

    -- Update the status of the members who meet both criteria to 'TERMINATED'
    UPDATE Member
    SET MemberStatus = 'TERMINATED'
    WHERE MemberID IN (
        SELECT o.MemberID
        FROM TempOverdueMembers o
        JOIN TempSuspendedMembers s ON o.MemberID = s.MemberID
    );

    -- Drop temporary tables
    DROP TEMPORARY TABLE IF EXISTS TempOverdueMembers;
    DROP TEMPORARY TABLE IF EXISTS TempSuspendedMembers;
    
END //

DELIMITER ;


-- ----------------------------------------------------------------------------
-- TASK 4: Testing Scenarios
-- ----------------------------------------------------------------------------

-- Test 1 member with overdue book paid all fee
-- Insert new member data for testing
INSERT INTO Member (MemberID, MemberStatus, MemberName, MemberAddress, MemberSuburb, MemberState, MemberExpDate, MemberPhone, FineFees) 
VALUES ('7', 'REGULAR', 'TestMember1', '123 Test St', 'TestTown', 'NSW', '2024-12-31', '1234567890', 50.00);

-- Insert data indicating this member has borrowed a book and it's overdue
INSERT INTO Borrowedby (BranchID, BookID, MemberID, DateBorrowed, DateReturned, ReturnDueDate)
VALUES ('1', '1', '7', '2023-01-01', NULL, '2023-01-14');

-- check the member first 
Select * from member;

-- Update the fines of TestMember1 to $0 and see if the trigger works
UPDATE Member 
SET FineFees = 0.00
WHERE MemberID = 7;

-- Check the status of TestMember1 again
SELECT * FROM Member WHERE MemberID = 7;

-- Test 2 member with no overdue book paid all fee
-- Insert new member data for testing
INSERT INTO Member (MemberID, MemberStatus, MemberName, MemberAddress, MemberSuburb, MemberState, MemberExpDate, MemberPhone, FineFees) 
VALUES ('8', 'Suspended', 'TestMember2', '456 Test Ave', 'TestCity', 'QLD', '2024-12-31', '0987654321', 5.00);

-- check the member first
Select * from member;

-- Update the fines of TestMember2 to $0
UPDATE Member 
SET FineFees = 0.00
WHERE MemberID = 8;

-- Check the status of TestMember2 again
SELECT * FROM Member WHERE MemberID = 8;



-- Procedure test Scenario 1 (Member with Overdue Items, Suspended Twice in Last 3 Years)

-- 1. Insert the member data for testing

INSERT INTO Member (MemberID, MemberStatus, MemberName, MemberAddress, MemberSuburb, MemberState, MemberExpDate, MemberPhone, FineFees) 
VALUES (10, 'SUSPENDED', 'TestMember3', '789 Test Road', 'TestVille', 'VIC', '2024-12-31', '1122334455', 10.00);

-- 2. Insert data indicating this member has borrowed 2 books and both are overdue.

-- First overdue book for TestMember3
INSERT INTO Borrowedby (BranchID, BookID, MemberID, DateBorrowed, DateReturned, ReturnDueDate)
VALUES ('1', '2', '10', '2023-01-01', NULL, '2023-01-14');

-- Second overdue book for TestMember3
INSERT INTO Borrowedby (BranchID, BookID, MemberID, DateBorrowed, DateReturned, ReturnDueDate)
VALUES ('1', '3', '10', '2023-01-02', NULL, '2023-01-15');

-- 3. Insert data in MemberHistory to indicate the member was suspended twice in the last three years.

-- First suspension for TestMember3
INSERT INTO MemberHistory (MemberID, OldStatus, NewStatus, ChangeDate)
VALUES (10, 'REGULAR', 'SUSPENDED', '2021-02-01');

-- Second suspension for TestMember3
INSERT INTO MemberHistory (MemberID, OldStatus, NewStatus, ChangeDate)
VALUES (10, 'REGULAR', 'SUSPENDED', '2022-01-01');

-- check the member status first
Select * from member;

-- 4. Now, run the procedure to terminate members who have overdue items and have been suspended twice or more in the last three years.
-- set number of char bigger than 9 (default) because terminated is 10 char
ALTER TABLE Member MODIFY MemberStatus CHAR(20);

CALL TerminateOverdueMembers();

-- 5. Check the status of TestMember3 after running the procedure. 
-- If everything works correctly, the MemberStatus should be set to 'TERMINATED'.
SELECT * FROM Member WHERE MemberID = 10;


-- Scenario 2 (Member without Overdue Items, Suspended Twice in Last 3 Years):

-- 1. Insert the member data for testing
INSERT INTO Member (MemberID, MemberStatus, MemberName, MemberAddress, MemberSuburb, MemberState, MemberExpDate, MemberPhone, FineFees) 
VALUES (11, 'SUSPENDED', 'TestMember4', '321 Test Blvd', 'TestBorough', 'SA', '2024-12-31', '6655443322', 0.00);

-- 2. Insert data in MemberHistory to indicate the member was suspended twice in the last three years.
INSERT INTO MemberHistory (MemberID, OldStatus, NewStatus, ChangeDate)
VALUES (11, 'REGULAR', 'SUSPENDED', '2021-02-15');

INSERT INTO MemberHistory (MemberID, OldStatus, NewStatus, ChangeDate)
VALUES (11, 'REGULAR', 'SUSPENDED', '2022-02-15');

-- check the member status first
Select * from member;

-- 3. Run the procedure
CALL TerminateOverdueMembers();

-- 4. Check the status of TestMember4
SELECT * FROM Member WHERE MemberID = 11;


-- Scenario 3 (Member with Overdue Items, Suspended Only Once in Last 3 Years):

-- 1. Insert the member data for testing
INSERT INTO Member (MemberID, MemberStatus, MemberName, MemberAddress, MemberSuburb, MemberState, MemberExpDate, MemberPhone, FineFees) 
VALUES (12, 'SUSPENDED', 'TestMember5', '654 Test Lane', 'TestDistrict', 'TAS', '2024-12-31', '7766554433', 10.00);

-- 2. Insert data indicating this member has borrowed 2 books and both are overdue.
INSERT INTO Borrowedby (BranchID,BookID,MemberID,DateBorrowed,DateReturned,ReturnDueDate)
VALUES ('1', '1','12','2023-01-03',NULL,'2023-01-16');

INSERT INTO Borrowedby (BranchID,BookID,MemberID,DateBorrowed,DateReturned,ReturnDueDate)
VALUES ('1', '3','12','2023-01-05',NULL,'2023-01-18');

-- 3. Insert data in MemberHistory to indicate the member was suspended once in the last three years.
INSERT INTO MemberHistory (MemberID, OldStatus, NewStatus, ChangeDate)
VALUES (12, 'REGULAR', 'SUSPENDED', '2022-03-01');

-- check the member status first
Select * from member;

-- 4. Run the procedure
CALL TerminateOverdueMembers();

-- 5. Check the status of TestMember5
SELECT * FROM Member WHERE MemberID = 12;
	
