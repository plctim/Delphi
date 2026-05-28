/* ============================================================================
   02 - Register the Java libraries in the target database.
   Run in the DATABASE that will call the converter. Re-run after each new build
   of pdf-to-jpeg.jar (ALTER EXTERNAL LIBRARY) to deploy a new version.

   Adjust the two CONTENT paths to match your environment.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

/* ----------------------------------------------------------------------------
   (a) The Microsoft Java Language Extension SDK jar.
       Ships with SQL Server. Typical path (SQL 2022 default instance):
         C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\mssql-java-lang-extension.jar
       Some installations already expose the SDK to the runtime; if CREATE fails
       saying it already exists, you can skip this block.
   ---------------------------------------------------------------------------- */
CREATE EXTERNAL LIBRARY [mssql-java-lang-extension]
FROM (CONTENT = N'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\mssql-java-lang-extension.jar')
WITH (LANGUAGE = 'Java');
GO

/* ----------------------------------------------------------------------------
   (b) Our application uber-jar (PDFBox bundled in).
       This is target/pdf-to-jpeg.jar produced by `mvn package`.
       Copy it somewhere the SQL Server service account can read, then point
       CONTENT at it. (The bytes are stored inside the database, so the path is
       only read at CREATE/ALTER time.)
   ---------------------------------------------------------------------------- */
CREATE EXTERNAL LIBRARY [pdf-to-jpeg]
FROM (CONTENT = N'C:\Deploy\pdf-to-jpeg.jar')
WITH (LANGUAGE = 'Java');
GO

/* To deploy a rebuilt jar later, use ALTER instead of CREATE:

ALTER EXTERNAL LIBRARY [pdf-to-jpeg]
FROM (CONTENT = N'C:\Deploy\pdf-to-jpeg.jar')
WITH (LANGUAGE = 'Java');
GO
*/

-- Verify registration.
SELECT name FROM sys.external_libraries ORDER BY name;
GO
