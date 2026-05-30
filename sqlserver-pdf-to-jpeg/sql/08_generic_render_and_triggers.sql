/* ============================================================================
   Generic PDF -> JPEG rendering for ANY table.

   The Java executor (com.porterlee.pdf.PdfToJpeg) is a pure transform:
       (DocId INT, PdfBytes VARBINARY(MAX))  ->  (DocId, PageNumber, JpegBytes)
   It knows nothing about tables. All "which table / which columns" logic lives
   here in T-SQL, so NO Java rebuild is needed to support a new table.

   Constraint: the key column is echoed through Java's integer channel, so the
   key must be an integer type (INT / IDENTITY). For GUID/string keys, a
   surrogate row-number mapping plus a getLongColumn/getStringColumn change in
   the Java executor is required.
   ============================================================================ */

USE [YourDatabase];   -- <-- change to your database
GO

-- ---------------------------------------------------------------------------
-- Generic renderer: point it at any table that stores PDFs in a VARBINARY(MAX)
-- column. Creates the target cache table on first use; (re)renders rows and
-- caches one row per page as (KeyValue, PageNumber, JpegBytes).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.RenderPdfTableToJpegs
    @SourceTable  SYSNAME,
    @KeyColumn    SYSNAME,
    @PdfColumn    SYSNAME,
    @TargetTable  SYSNAME,
    @SourceSchema SYSNAME = N'dbo',
    @TargetSchema SYSNAME = N'dbo',
    @Dpi          INT     = 150,
    @KeyList      NVARCHAR(MAX) = NULL   -- optional comma-separated INTEGER keys to limit scope
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @src NVARCHAR(512) = QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable),
            @tgt NVARCHAR(512) = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable),
            @k   NVARCHAR(258) = QUOTENAME(@KeyColumn),
            @p   NVARCHAR(258) = QUOTENAME(@PdfColumn),
            @sql NVARCHAR(MAX);

    -- Validate objects (defends against typos and SYSNAME injection)
    IF OBJECT_ID(@src) IS NULL THROW 50001, 'Source table not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@src) AND name = @KeyColumn)
        THROW 50002, 'Key column not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@src) AND name = @PdfColumn)
        THROW 50003, 'PDF column not found.', 1;
    -- @KeyList is interpolated into the query, so only allow digits/commas/spaces
    IF @KeyList IS NOT NULL AND @KeyList LIKE N'%[^0-9, ]%'
        THROW 50004, '@KeyList must be a comma-separated list of integer keys.', 1;

    DECLARE @scope NVARCHAR(MAX) =
        CASE WHEN @KeyList IS NULL OR @KeyList = N'' THEN N''
             ELSE N' AND ' + @k + N' IN (' + @KeyList + N')' END;

    -- 1) Create the target cache table if missing
    IF OBJECT_ID(@tgt) IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + @tgt + N' (
            KeyValue   INT            NOT NULL,
            PageNumber INT            NOT NULL,
            JpegBytes  VARBINARY(MAX) NOT NULL,
            PageText   NVARCHAR(MAX)  NULL,
            RenderedAt DATETIME2      NOT NULL CONSTRAINT ' + QUOTENAME(N'DF_' + @TargetTable + N'_RenderedAt') + N' DEFAULT SYSUTCDATETIME(),
            CONSTRAINT ' + QUOTENAME(N'PK_' + @TargetTable) + N' PRIMARY KEY (KeyValue, PageNumber));';
        EXEC sys.sp_executesql @sql;
    END
    ELSE IF NOT EXISTS (SELECT 1 FROM sys.columns
                        WHERE object_id = OBJECT_ID(@tgt) AND name = N'PageText')
    BEGIN
        -- Upgrade an older target table created before text extraction existed.
        SET @sql = N'ALTER TABLE ' + @tgt + N' ADD PageText NVARCHAR(MAX) NULL;';
        EXEC sys.sp_executesql @sql;
    END

    -- 2) Clear stale pages for the rows we are about to (re)render
    SET @sql = N'DELETE FROM ' + @tgt + N' WHERE KeyValue IN
                 (SELECT ' + @k + N' FROM ' + @src + N' WHERE ' + @p + N' IS NOT NULL' + @scope + N');';
    EXEC sys.sp_executesql @sql;

    -- 3) Render + cache. Java reads @input_data_1; output rows land in the target.
    DECLARE @inputQuery NVARCHAR(MAX) =
        N'SELECT ' + @k + N' AS DocId, ' + @p + N' AS PdfBytes FROM ' + @src +
        N' WHERE ' + @p + N' IS NOT NULL' + @scope + N';';

    SET @sql = N'
        INSERT INTO ' + @tgt + N' (KeyValue, PageNumber, JpegBytes, PageText)
        EXEC sp_execute_external_script
            @language = N''Java'', @script = N''com.porterlee.pdf.PdfToJpeg'',
            @input_data_1 = @iq, @params = N''@dpi INT'', @dpi = @dpi
        WITH RESULT SETS ((KeyValue INT, PageNumber INT, JpegBytes VARBINARY(MAX), PageText NVARCHAR(MAX)));';
    EXEC sys.sp_executesql @sql, N'@iq NVARCHAR(MAX), @dpi INT', @iq = @inputQuery, @dpi = @Dpi;
END
GO


/* ============================================================================
   AFTER INSERT/UPDATE triggers.

   Triggers are per-table (each names its own table), so this is a template
   plus a working example for dbo.Documents.

   WARNING: this renders SYNCHRONOUSLY inside the DML transaction -- the
   insert/update won't return until rendering completes, and a render failure
   rolls back the write. Fine for low-volume/interactive inserts. For bulk
   loads, use a lightweight "enqueue only" trigger + a SQL Agent job that
   drains the queue and calls dbo.RenderPdfTableToJpegs out-of-band.
   ============================================================================ */

/* ----- TEMPLATE: copy per source table, replace <...> -----------------------
CREATE OR ALTER TRIGGER dbo.trg_<SourceTable>_RenderPdf
ON dbo.<SourceTable>
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(<PdfColumn>) RETURN;                 -- skip updates that didn't touch the PDF

    DECLARE @keys NVARCHAR(MAX);
    SELECT @keys = STRING_AGG(CONVERT(NVARCHAR(20), <KeyColumn>), N',')
    FROM inserted WHERE <PdfColumn> IS NOT NULL;       -- multi-row safe
    IF @keys IS NULL RETURN;

    EXEC dbo.RenderPdfTableToJpegs
        @SourceTable = N'<SourceTable>', @KeyColumn = N'<KeyColumn>',
        @PdfColumn   = N'<PdfColumn>',   @TargetTable = N'<TargetTable>',
        @Dpi = 150, @KeyList = @keys;
END
GO
--------------------------------------------------------------------------- */

-- ----- Concrete example: dbo.Documents -> dbo.DocumentsPages ----------------
CREATE OR ALTER TRIGGER dbo.trg_Documents_RenderPdf
ON dbo.Documents
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(PdfBytes) RETURN;

    DECLARE @keys NVARCHAR(MAX);
    SELECT @keys = STRING_AGG(CONVERT(NVARCHAR(20), DocId), N',')
    FROM inserted WHERE PdfBytes IS NOT NULL;
    IF @keys IS NULL RETURN;

    EXEC dbo.RenderPdfTableToJpegs
        @SourceTable = N'Documents', @KeyColumn = N'DocId',
        @PdfColumn   = N'PdfBytes',  @TargetTable = N'DocumentsPages',
        @Dpi = 150, @KeyList = @keys;
END
GO
