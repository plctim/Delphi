# PDF → JPEG in SQL Server — Overview for the SQL Server IT Manager

## What it does
Converts PDF files that are stored in a database column (`VARBINARY(MAX)`) into
one JPEG image **per page**, entirely inside SQL Server. Results are returned as
a normal result set / cached in a table as `(KeyValue, PageNumber, JpegBytes)`.
It works for **any table** that holds PDFs — the source table, key column, PDF
column, and output table are all parameters.

## How it works
- Uses the built-in **SQL Server Java Language Extension** (`sp_execute_external_script`).
- The rendering engine is **Apache PDFBox** (open-source, Apache 2.0 license — no
  licensing cost), packaged in a single Java file (`pdf-to-jpeg.jar`).
- The Java code runs **out-of-process** in SQL Server's *Launchpad* host, **not**
  inside the database engine (`sqlservr.exe`). A fault in rendering cannot crash
  the SQL instance; CPU/memory is governed by the external resource pool.
- Stored procedures and optional triggers drive it; an optional SQL Agent job
  handles bulk/asynchronous rendering.

## One-time server prerequisites (what we need from IT)
1. **Enable External Scripts** (`sp_configure 'external scripts enabled', 1`) — requires a **one-time SQL Server service restart**.
2. **Java Language Extension** installed on the instance (feature of SQL Server 2019+).
3. **Microsoft OpenJDK 17** installed (LTS; 17 is the supported maximum for the extension).
4. Grant the sandbox read/execute on the JDK folder:
   `icacls "<JDK path>" /grant *S-1-15-2-1:(OI)(CI)RX /T`
5. Register two jars in the database (`CREATE EXTERNAL LIBRARY`): the Microsoft SDK
   jar (ships with SQL Server) and our `pdf-to-jpeg.jar`.

## Security posture
- **No network/internet access required** — conversion happens in-engine; no external
  service or REST call, and PDFs never leave the server.
- Callers need the `EXECUTE ANY EXTERNAL SCRIPT` permission; access is otherwise
  governed by normal database permissions on the procs/tables.
- The application jar is stored **inside the database**, so it is captured by normal
  database backups; the JDK and Language Extension are server-level installs to record
  in the build/runbook.

## Operations & maintenance
- **Triggers (optional)** auto-render when a PDF is inserted/updated. Two modes:
  - *Synchronous* — pages ready immediately (best for low-volume/interactive).
  - *Asynchronous queue + SQL Agent job* — recommended for bulk loads; the write
    returns instantly and rendering happens in the background. Failures are recorded
    in a **dead-letter table** for review (does not block the queue).
- **Storage growth** — rendered JPEGs are stored in the database; size scales with
  page count and DPI (default 150). Plan capacity / archival accordingly.
- **Monitoring** — for the async option, watch the SQL Agent job and the
  `PdfRenderDeadLetter` table.

## Risk summary
- Out-of-process design keeps rendering isolated from the database engine.
- Open-source renderer, no third-party licensing.
- Main considerations are routine: the one-time feature enable + restart, the JDK
  install/permissions, and database storage growth for the generated images.
