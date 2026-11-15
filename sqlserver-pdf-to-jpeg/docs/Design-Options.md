# Design Options — PDF (in a DB column) → table of JPEG pages

Approaches considered for turning a PDF stored in a SQL Server `VARBINARY(MAX)`
column into a table of `(PageNumber, JpegBytes[, PageText])`, with trade-offs and
the rationale for the option this project implements.

> **Chosen:** Option 2 — SQL Server **Java Language Extension** with Apache PDFBox.
> See "Why we chose #2" at the bottom.

---

## In-process inside SQL Server

### 1. SQL CLR table-valued function (.NET)
A streaming CLR TVF (`RETURNS TABLE … AS EXTERNAL NAME`) reads the blob (passed in,
or fetched via a context connection) and yields one row per page.
- **Pros:** True inline TVF — `SELECT * FROM fn(…)`, composes in `CROSS APPLY`/`JOIN`,
  parameterized, no cache needed. The only option with streaming-TVF ergonomics.
- **Cons:** .NET Framework only; runs in-process, so a native renderer (PDFium/Ghostscript)
  risks the engine and needs `UNSAFE`. Pure-managed rendering ⇒ a commercial lib
  (Aspose/Spire). A CLR→REST variant offloads the work (see #4).
- **Best when:** you need the TVF shape and already have a CLR+service.

### 2. Language Extension — Java (PDFBox) or Python (PyMuPDF/pdf2image)  ← implemented
`sp_execute_external_script` feeds the blob to out-of-process code (this repo uses
PDFBox; Python `PyMuPDF`/`pdf2image` is an equivalent alternative).
- **Pros:** Out-of-process (can't crash the engine), free/open-source renderer, no
  network, batch-friendly, also extracts text (PDFBox `PDFTextStripper`).
- **Cons:** Proc-only — no streaming TVF, so results go to a cache table that a TVF/view
  reads. One-time feature enable + JDK/permissions.
- **Best when:** fully in-DB, open-source, isolated. (This project's situation.)

## Out-of-process, driven by SQL Server

### 3. Native/console worker + an invocation mechanism
A standalone renderer (e.g. **Delphi + ImageEn**, or a .NET/Python console) reads the
column and writes pages back. SQL triggers it via:
- **Service Broker + External Activator** (event-driven, durable, back-pressure-friendly),
- **SQL Agent job** draining a work/queue table (this repo's `09_async_queue.sql` pattern),
- **`xp_cmdshell`** (simple, usually disabled for security).
- **Pros:** Heavy work entirely off `sqlservr.exe`; reuse ImageEn/any engine; scales to N workers.
- **Cons:** More moving parts; async (cache table, not inline).
- **Best when:** high volume, or you must keep ImageEn.

### 4. CLR (or proc) → REST microservice
A thin CLR TVF / proc POSTs the PDF bytes to a service (e.g. Delphi XData) that renders
and returns the pages.
- **Pros:** Reuses Delphi/ImageEn, keeps rendering out of the DB process, still exposable
  as a TVF.
- **Cons:** Needs the service running + reachable; network hop; DB depends on an endpoint.
- **Best when:** you already have the service and just need to feed it column bytes.

## Outside SQL Server entirely

### 5. Application / middle tier
The app reads the blob over a normal query and renders client-side (ImageEn, PDFium,
PDF.js, ImageMagick/Ghostscript).
- **Pros:** Zero DB-server footprint, no feature enablement, easiest to scale/sandbox,
  widest renderer choice.
- **Cons:** Not available as a `SELECT`; each consuming app re-implements it.
- **Best when:** rendering is a presentation concern, not a data concern.

---

## Cross-cutting choices (apply to any option)

- **On-demand vs. precomputed cache.** Render live per request, or render once into a
  `Pages(KeyValue, PageNumber, JpegBytes[, PageText])` table and `SELECT` thereafter.
  Rendering is expensive → caching usually wins; trigger it on insert/update.
- **Sync vs. async trigger.** Synchronous = pages ready immediately but blocks the write;
  async queue + worker = instant writes, background render, dead-letter on failure.
- **Format & options.** JPEG (small) vs PNG/BMP (lossless/large); DPI; image and text each
  independently optional.
- **Key-type genericity.** Echo an INT key through the renderer, or use a surrogate
  row-number map for GUID/string keys.

## Quick picker

| Priority | Pick |
|---|---|
| Inline `SELECT * FROM fn(pdf)` ergonomics | #1 CLR TVF (or #4 CLR→REST) |
| Fully in-DB, open-source, isolated | **#2 Language Extension** (this repo) |
| Keep Delphi/ImageEn, high volume | #3 worker + Service Broker, or #4 REST |
| Keep it out of the DB entirely | #5 app tier |

---

## Why we chose #2 (Java Language Extension + PDFBox)

- **Self-contained & in-engine:** a plain `EXEC`/`SELECT` against SQL Server produces the
  pages; no external service to deploy, run, or monitor, and the PDF bytes never leave the
  server.
- **Process isolation:** rendering runs in the out-of-process Launchpad host, so a PDFBox
  fault or memory spike cannot destabilize `sqlservr.exe` — the main risk of an in-process
  CLR renderer.
- **No licensing cost:** Apache PDFBox is Apache-2.0; the pure-managed CLR path would have
  meant a commercial renderer (Aspose/Spire).
- **Text for free:** the same PDFBox pass extracts per-page text (digital PDFs), satisfying
  the image + text requirement in one component.
- **Generic & cache-friendly:** one executor serves any table; the proc/trigger/queue layer
  handles per-table wiring, optional outputs, and sync-or-async rendering.

**Accepted trade-off:** the extension is proc-only, so there is no streaming TVF; instead we
render into a cache table that a TVF/view reads. If streaming-TVF ergonomics ever become a
hard requirement, Option 1 (CLR TVF) or Option 4 (CLR→REST) are the fallbacks — and the
existing cache tables remain useful either way.
