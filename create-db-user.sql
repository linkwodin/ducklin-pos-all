-- SQL script to create/update pos_user for Cloud SQL
-- Run this by connecting to your Cloud SQL instance

-- Create user if it doesn't exist, or update password if it does
CREATE USER IF NOT EXISTS 'pos_user'@'%' IDENTIFIED BY 'BDcm]R1bGe<DrNq0';

-- Also create user for Cloud SQL Proxy connections (this is important!)
CREATE USER IF NOT EXISTS 'pos_user'@'cloudsqlproxy~%' IDENTIFIED BY 'BDcm]R1bGe<DrNq0';

-- Grant all privileges on the database
GRANT ALL PRIVILEGES ON `pos_system`.* TO 'pos_user'@'%';
GRANT ALL PRIVILEGES ON `pos_system`.* TO 'pos_user'@'cloudsqlproxy~%';

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Verify the user was created
SELECT User, Host FROM mysql.user WHERE User = 'pos_user';

-- Show grants
SHOW GRANTS FOR 'pos_user'@'%';
SHOW GRANTS FOR 'pos_user'@'cloudsqlproxy~%';

