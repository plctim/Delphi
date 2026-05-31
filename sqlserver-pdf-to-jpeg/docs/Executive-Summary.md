# Executive Summary — PDF → JPEG in SQL Server

We have added the ability to convert PDF files (already stored in our SQL Server
database) into per-page JPEG images directly within SQL Server, on demand or
automatically when a PDF is added. It uses SQL Server's built-in Java extension
with the free, open-source Apache PDFBox renderer, runs in an isolated process
that cannot affect database stability, requires no internet access (documents
never leave the server), and carries no third-party licensing cost. The one-time
setup is a standard SQL Server feature enablement plus a Java runtime install;
ongoing operation is handled by stored procedures and an optional background job,
and the generated images are stored in the database and covered by normal backups.
