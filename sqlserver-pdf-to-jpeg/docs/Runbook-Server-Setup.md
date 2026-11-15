# Server Setup Runbook — PDF → JPEG (SQL Server Java Extension)

Run these steps **in order**, as a local administrator / `sysadmin`. Substitute
your instance folder (`MSSQL17.MSSQLSERVER` shown), JDK version folder, and
database name where noted. Jars are deployed from `C:\PlcPdfHelper\`.

> One-time per SQL Server instance. Most steps are server-level; steps 6–7 are per database.

---

## 1. Install the Java runtime (OpenJDK 17 — supported maximum)
- Install `microsoft-jdk-17.x.x-windows-x64.msi` from https://learn.microsoft.com/java/openjdk/download
- Note the install path, e.g. `C:\Program Files\Microsoft\jdk-17.0.19.x-hotspot`.

## 2. Install the Java Language Extension binaries
- Download `java-lang-extension-windows-release.zip` from
  https://github.com/microsoft/sql-server-language-extensions/releases
- Place `javaextension.dll` and `mssql-java-lang-extension.jar` into the instance's Binn folder:
  `C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Binn\`

## 3. Grant the sandbox access to the JDK (required)
The extension runs in an AppContainer that must read the JDK. From an **elevated** prompt:
```bat
icacls "C:\Program Files\Microsoft\jdk-17.0.19.x-hotspot" /grant *S-1-15-2-1:(OI)(CI)RX /T
```

## 4. Enable external scripts (one-time, requires service restart)
```sql
EXEC sp_configure 'external scripts enabled', 1;
RECONFIGURE WITH OVERRIDE;
```
Then **restart the SQL Server service**. Verify after restart:
```sql
SELECT name, value_in_use FROM sys.configurations WHERE name = 'external scripts enabled';  -- expect 1
```

## 5. Confirm the Java external language is registered
```sql
SELECT external_language_id, name FROM sys.external_languages WHERE name = N'Java';
```
If it returns no rows, register it (adjust path):
```sql
CREATE EXTERNAL LANGUAGE Java
FROM (CONTENT = N'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Binn\java-lang-extension.zip',
      FILE_NAME = N'javaextension.dll');
```

## 6. Copy and register the jars  (per database)
- Copy `mssql-java-lang-extension.jar` and the application `pdf-to-jpeg.jar` to `C:\PlcPdfHelper\`
  (a path the SQL Server service account can read).
- Run `sql/02_create_external_libraries.sql` (sets `USE <YourDatabase>` and the two `CREATE EXTERNAL LIBRARY` paths). Verify:
```sql
SELECT name FROM sys.external_libraries ORDER BY name;  -- expect mssql-java-lang-extension, pdf-to-jpeg
```

## 7. Deploy the database objects  (per database)
Run, in order:
- `sql/03_create_procedure.sql`  — `dbo.ConvertPdfToJpeg`
- `sql/08_generic_render_and_triggers.sql` — generic renderer + synchronous trigger (optional)
- `sql/09_async_queue.sql` — async queue + drain proc + enqueue trigger (optional; use instead of the sync trigger)

## 8. Smoke test
```sql
-- Load a sample PDF and convert it (see sql/04_demo.sql)
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;   -- expect one row per page, JpegBytes starting 0xFFD8FF
```

## 9. (Async option) Create the SQL Agent job
Run the commented `msdb` block at the bottom of `sql/09_async_queue.sql` to drain
the queue every minute. Confirm the job exists and is enabled.

---

## Permissions for application callers
```sql
GRANT EXECUTE ANY EXTERNAL SCRIPT TO [your_app_login_or_role];
GRANT EXECUTE ON dbo.ConvertPdfToJpeg TO [your_app_login_or_role];
-- plus EXECUTE on dbo.RenderPdfTableToJpegs / SELECT on the page tables as needed
```

## Rollback / uninstall (per database)
```sql
-- DROP the triggers, procs, functions, page/queue tables as applicable, then:
DROP EXTERNAL LIBRARY [pdf-to-jpeg];
DROP EXTERNAL LIBRARY [mssql-java-lang-extension];
```
Disabling the feature instance-wide (optional): `sp_configure 'external scripts enabled', 0` + restart.

## Operational checks
- Async failures:   `SELECT * FROM dbo.PdfRenderDeadLetter ORDER BY FailedAt DESC;`
- Queue depth:      `SELECT COUNT(*) FROM dbo.PdfRenderQueue;`
- Storage growth:   generated JPEGs are stored in the page tables (size ≈ pages × DPI); monitor and archive as needed.
