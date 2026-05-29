# SQL Server Java Language Extension — PDF → JPEG

Renders **each page of a PDF** that lives in a SQL Server `VARBINARY(MAX)` column
into a JPEG, and returns the result as a table of `(DocId, PageNumber, JpegBytes)`.

It runs **inside the SQL Server Java Language Extension** (`sp_execute_external_script`),
so the PDF bytes never leave the database engine's environment — no REST hop and no
file on disk required.

> **Why Java/PDFBox here instead of CLR + ImageEn?**
> A SQL CLR assembly runs .NET Framework in-process and can't host native Delphi/ImageEn
> code. The Language Extension runs out-of-process in a JRE, where
> [Apache PDFBox](https://pdfbox.apache.org/) (pure Java, Apache-2.0) renders pages to
> images with no native dependency and no license cost. This trades away ImageEn but gains
> process isolation and a free renderer. If you'd rather keep ImageEn, the alternative is
> to keep your existing CLR→Delphi service and just feed it the column bytes instead of a
> file path.

---

## Contents

| Path | Purpose |
|------|---------|
| `pom.xml` | Maven build → single uber-jar `target/pdf-to-jpeg.jar` (PDFBox bundled). |
| `src/main/java/com/porterlee/pdf/PdfToJpeg.java` | The executor (`extends AbstractSqlServerExtensionExecutor`). |
| `sql/01_enable_external_scripts.sql` | Enable the feature; confirm Java is installed. |
| `sql/02_create_external_libraries.sql` | Register the SDK jar + the app jar in the DB. |
| `sql/03_create_procedure.sql` | `dbo.ConvertPdfToJpeg` wrapper proc. |
| `sql/04_demo.sql` | Load a PDF into a column and convert it. |

---

## Requirements

- **SQL Server 2019 (15.x) or later, on Windows**, with the
  *Machine Learning Services and Language Extensions* feature **and the Java runtime**
  selected at setup. (Java Language Extensions are Windows-only.)
- **JDK 8+** and **Maven** on your build machine.

---

## Build

The Microsoft SDK jar ships with SQL Server and is referenced as a `provided`
dependency. Install it into your local Maven repo once (adjust the path/instance):

```bat
mvn install:install-file ^
  -Dfile="C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Binn\mssql-java-lang-extension.jar" ^
  -DgroupId=com.microsoft.sqlserver ^
  -DartifactId=mssql-java-lang-extension ^
  -Dversion=1.0 ^
  -Dpackaging=jar
```

Then build the uber-jar:

```bat
mvn clean package
```

Output: **`target/pdf-to-jpeg.jar`** (contains PDFBox + FontBox + commons-logging;
the SDK is excluded because the runtime provides it).

---

## Deploy

1. **Enable the feature** — run `sql/01_enable_external_scripts.sql` (restart the
   SQL Server service the first time `external scripts enabled` flips to 1).
2. **Copy** `target/pdf-to-jpeg.jar` to a path the SQL Server service account can read
   (e.g. `C:\Deploy\pdf-to-jpeg.jar`).
3. **Register the libraries** — edit the two `CONTENT` paths and the database name in
   `sql/02_create_external_libraries.sql`, then run it. Use `ALTER EXTERNAL LIBRARY`
   to push later rebuilds.
4. **Create the proc** — run `sql/03_create_procedure.sql` (point `@input_data_1` at
   your real table/columns).

---

## Use

```sql
-- One row per page: DocId, PageNumber (1-based), JpegBytes (VARBINARY(MAX))
EXEC dbo.ConvertPdfToJpeg @DocId = 1, @Dpi = 150;
```

`@Dpi` is optional (default 150). Higher DPI = larger, sharper JPEGs.

The proc passes the PDF in as the input dataset (`SELECT DocId, PdfBytes ...`) and the
executor emits a row per rendered page. You can feed **multiple PDFs** at once by widening
the input query's `WHERE` clause — `DocId` is echoed on every output row so pages stay
attributable.

---

## Data contract

**Input dataset** (order matters — columns are read by position):

| # | Column | SQL type | Java type |
|---|--------|----------|-----------|
| 0 | DocId | `INT` | `int` |
| 1 | PdfBytes | `VARBINARY(MAX)` | `byte[]` |

**Output dataset** (`WITH RESULT SETS`):

| # | Column | SQL type |
|---|--------|----------|
| 0 | DocId | `INT` |
| 1 | PageNumber | `INT` (1-based) |
| 2 | JpegBytes | `VARBINARY(MAX)` |

`VARBINARY(MAX)` ↔ `byte[]` is supported for both input and output datasets in the Java
extension (per the Microsoft data-type mapping).

---

## Troubleshooting

- **`ImageWriter` / fonts** — rendering uses `java.awt` in headless mode (set by a static
  initializer). If non-embedded fonts render poorly, install standard fonts on the server.
- **Output column type metadata** — the executor describes `JpegBytes` as
  `java.sql.Types.VARBINARY`. If a future SQL Server build rejects this for `VARBINARY(MAX)`,
  switch the metadata in `buildOutput(...)` to `java.sql.Types.LONGVARBINARY`. The
  `WITH RESULT SETS` clause already declares `VARBINARY(MAX)`.
- **Memory** — large or high-DPI PDFs are memory-heavy. The extension runs under the
  *external resource pool*; raise its `MAX_MEMORY_PERCENT` if you see allocation failures.
- **Permissions** — the principal running the proc needs `EXECUTE ANY EXTERNAL SCRIPT`.
- **Not tested in this environment** — these files were scaffolded but not compiled or run
  against a live SQL Server instance here. Build with `mvn package` and run `sql/04_demo.sql`
  against a 2019+ instance to validate end-to-end.
```
