/* ============================================================================
   01 - Enable external scripts and confirm the Java language is installed.
   Run ONCE per SQL Server instance, as sysadmin.

   Prerequisites:
     - SQL Server 2019 (15.x) or later, Windows.
     - The "Machine Learning Services and Language Extensions" + "Java"
       feature must have been selected during SQL Server setup.
   ============================================================================ */

-- 1) Turn on the external script feature (requires a service restart the first time).
EXEC sp_configure 'external scripts enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- >>> Restart the SQL Server service now if this value just changed from 0 to 1. <<<

-- 2) Confirm the Java external language exists on the instance.
--    On a properly installed 2019+ instance, 'Java' is already registered.
SELECT external_language_id, name
FROM sys.external_languages
WHERE name = N'Java';
GO

/* If the SELECT above returns no rows, register Java once (adjust the path to
   your instance's Binn folder, e.g. MSSQL16.MSSQLSERVER for SQL 2022):

CREATE EXTERNAL LANGUAGE Java
FROM (
    CONTENT = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\java-lang-extension.zip',
    FILE_NAME = N'javaextension.dll'
);
GO
*/
