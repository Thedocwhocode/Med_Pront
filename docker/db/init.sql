-- Ensure correct charset and collation for OpenEMR after container creation
ALTER DATABASE openemr CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Set session defaults
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
